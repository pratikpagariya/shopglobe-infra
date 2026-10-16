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

# Terraform WILL see this password and it WILL be in state. That is the known
# tradeoff, and it is why the state bucket is encrypted, versioned and access-
# restricted. Putting it in Secrets Manager means External Secrets pulls it
# into the cluster, so it never reaches a manifest or a git repo.
resource "random_password" "db" {
  length  = 32
  special = false # some AWS engines reject characters that also break URIs
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "shopglobe/${var.environment}/catalog-db"
  recovery_window_in_days = 0 # 0 = delete immediately; 7-30 in real prod
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "shop"
    password = random_password.db.result
    host     = module.rds.db_host
    port     = 5432
    dbname   = "shopglobe"
  })
}

module "rds" {
  source = "../../modules/rds"

  project     = "shopglobe"
  environment = var.environment
  identifier  = "catalog"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.db_subnet_ids

  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  parameter_group_family = "postgres16"

  db_parameters = [
    {
      name  = "max_connections"
      value = "100"
      # STATIC parameter -- Postgres reads it only at startup, so it needs a
      # reboot. Leaving this "immediate" makes RDS reject the apply.
      # Deliberately low: scaling past ~14 replicas exhausts it, which is the
      # pool_size x workers x replicas lesson made concrete.
      apply_method = "pending-reboot"
    },
    {
      name  = "log_min_duration_statement"
      value = "200"
      # DYNAMIC -- takes effect without a restart, so the default
      # apply_method = "immediate" is correct. This is how you find the N+1.
    },
  ]

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name     = "shopglobe"
  db_username = "shop"
  db_password = random_password.db.result

  # TWO security groups, deliberately. EKS automatically creates its own
  # cluster security group and attaches it to managed node group instances,
  # IN ADDITION to anything this module defines. Pod egress carries the
  # EKS-managed one, so allowing only the module's node SG produces a silent
  # connection timeout that looks like a routing problem.
  allowed_security_group_ids = [
    module.eks.node_security_group_id,
    module.eks.eks_managed_cluster_security_group_id,
  ]

  multi_az                = var.rds_multi_az
  backup_retention_period = 1
  skip_final_snapshot     = true  # demo stack only
  deletion_protection     = false # true in real prod
  apply_immediately       = true

  tags = {}
}

module "sqs_payments" {
  source   = "../../modules/sqs"
  for_each = local.app_envs

  project = "shopglobe"
  # The APP env, not var.environment, so the names come out
  # shopglobe-dev-payments, shopglobe-stage-payments, shopglobe-prod-payments.
  environment = each.key
  queue_name  = "payments"

  # payment-worker takes ~0.4s worst case. 30s is ~75x headroom.
  visibility_timeout_seconds = 30
  max_receive_count          = 3

  tags = { AppEnv = each.key }
}

# The queue that already exists becomes the "prod" instance. Without this,
# Terraform sees one resource removed and three added, so it would DESTROY the
# live queue (and every message in it) to recreate it at a new address.
moved {
  from = module.sqs_payments
  to   = module.sqs_payments["prod"]
}

module "redis" {
  source = "../../modules/redis"

  project     = "shopglobe"
  environment = var.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.db_subnet_ids

  # Same two-SG lesson as RDS: pods leave with the EKS-managed cluster SG.
  allowed_security_group_ids = [
    module.eks.node_security_group_id,
    module.eks.eks_managed_cluster_security_group_id,
  ]

  node_type = var.redis_node_type
  replicas  = var.redis_replicas

  tags = {}
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

  # The namespace layer ships default-deny NetworkPolicies, and until this was
  # on they were decorative: the VPC CNI ignores NetworkPolicy unless told
  # otherwise. Note what it switches on: prod's default-deny-ingress now
  # really blocks anything from outside the namespace -- an ALB in front of
  # prod would need its own allow rule.
  enable_network_policy = true

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
  # The 12 app-env associations live in app-envs.tf; these are the platform ones.
  pod_identity_associations = merge(local.app_pod_identities, {
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
            Resource = "arn:aws:ecr:${var.region}:${local.account_id}:repository/shopglobe-${var.environment}-*"
          },
        ]
      })
    }
  })

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
      ] : s => {
      # A tag can never be re-pointed. This is what makes "which code is
      # running?" answerable -- with mutable tags, two pods claiming the same
      # version can be running different code and you cannot reproduce a bug.
      image_tag_mutability = "IMMUTABLE"
      scan_on_push         = true
    }
  }

  apply_default_lifecycle_policy = true
  default_untagged_image_count   = 1
  default_tagged_image_count     = 10

  tags = {}
}
