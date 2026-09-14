module "vpc" {
  source = "../../modules/vpc"

  project     = "shopglobe"
  environment = var.environment
  region      = var.region

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  db_subnet_cidrs      = var.db_subnet_cidrs

  single_nat_gateway      = var.single_nat_gateway
  enable_vpc_endpoints    = var.enable_vpc_endpoints
  enable_flow_logs        = var.enable_flow_logs
  flow_log_retention_days = var.flow_log_retention_days

  tags = {}
}

# KMS envelope encryption for Kubernetes Secrets at rest in etcd. Without
# this, "encrypted" means base64 -- which is encoding, not encryption.
resource "aws_kms_key" "eks" {
  description             = "shopglobe-${var.environment} EKS secrets envelope encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/shopglobe-${var.environment}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# The AWS Load Balancer Controller policy is ~200 lines and published upstream.
# Fetch it rather than transcribing it -- see the command below.
resource "aws_iam_policy" "lb_controller" {
  name   = "shopglobe-${var.environment}-lb-controller"
  policy = file("${path.module}/policies/lb-controller.json")
}

# A read-only identity, to prove Access Entries actually scope. Without a
# second principal there is nothing to demonstrate -- the creator role is
# already cluster-admin.
resource "aws_iam_role" "viewer" {
  name = "shopglobe-${var.environment}-viewer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
    }]
  })
}


module "eks" {
  source     = "../../modules/eks"
  depends_on = [aws_iam_policy.lb_controller]

  project     = "shopglobe"
  environment = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_version    = var.cluster_version

  # Public endpoint so you can reach it from WSL. Restricting public_access_cidrs
  # to your IP is the next hardening step; private-only needs a bastion or VPN.
  endpoint_private_access = true
  endpoint_public_access  = true
  public_access_cidrs     = ["0.0.0.0/0"]

  cluster_log_types          = ["api", "audit", "authenticator"]
  cluster_encryption_key_arn = aws_kms_key.eks.arn

  authentication_mode     = "API"
  bootstrap_creator_admin = true

  # bootstrap_creator_admin already created a cluster-admin entry for
  # shopglobe-terraform. An entry is unique per (cluster, principal), so a
  # second entry for the same role is a 409. This one uses a SEPARATE role,
  # which is also the only way the namespace-scoping demo means anything.
  access_entries = {
    dev_viewer = {
      principal_arn = aws_iam_role.viewer.arn
      policies = {
        view_dev = {
          policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope_type = "namespace"
          namespaces        = ["shopglobe-dev"]
        }
      }
    }
  }

  node_groups = var.node_groups

  # Pod Identity: cluster+namespace+serviceaccount -> IAM role. No OIDC trust
  # policy, no ServiceAccount annotation, and zero static keys in the cluster.
  pod_identity_associations = {
    cluster-autoscaler = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect = "Allow"
          Action = [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeScalingActivities",
            "autoscaling:DescribeTags",
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup",
            "ec2:DescribeLaunchTemplateVersions",
            "ec2:DescribeInstanceTypes",
            "eks:DescribeNodegroup",
          ]
          Resource = "*"
        }]
      })
    }

    ebs-csi = {
      namespace           = "kube-system"
      service_account     = "ebs-csi-controller-sa"
      managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
    }

    aws-lb-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      # NOT aws_iam_policy.lb_controller.arn -- that is unknown at plan time and
      # the module uses the ARN as a for_each key. IAM policy ARNs are
      # deterministic, so compose it from values that are already known.
      managed_policy_arns = [
        "arn:aws:iam::${local.account_id}:policy/shopglobe-${var.environment}-lb-controller"
      ]
    }

    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:shopglobe/*"
        }]
      })
    }

    jenkins = {
      namespace       = "jenkins"
      service_account = "jenkins"
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect   = "Allow"
            Action   = ["ecr:GetAuthorizationToken"]
            Resource = "*" # this action does not support resource scoping
          },
          {
            Effect = "Allow"
            Action = [
              "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
              "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
              "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
            ]
            Resource = "arn:aws:ecr:${var.region}:${local.account_id}:repository/shopglobe/*"
          },
        ]
      })
    }
  }

  tags = {}
}

module "ecr" {
  source = "../../modules/ecr"

  project     = "shopglobe"
  environment = var.environment

  repositories = {
    for s in [
      "edge-gateway", "auth-svc", "catalog-svc", "cart-svc",
      "order-svc", "payment-worker", "notify-svc", "media-svc", "jenkins",
    ] : "shopglobe/${s}" => {}
  }

  apply_default_lifecycle_policy = true
  default_untagged_image_count   = 1
  default_tagged_image_count     = 10

  tags = {}
}
