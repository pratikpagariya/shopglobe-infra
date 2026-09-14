###############################################################################
# EKS Module — main.tf
# Uses EKS Pod Identity (NOT IRSA)
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(var.tags, {
    Module = "eks"
  })
}

###############################################################################
# IAM — EKS Cluster Role
###############################################################################
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

###############################################################################
# Security Group — EKS Cluster
###############################################################################
resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_security_group_rule" "cluster_ingress_nodes" {
  description              = "Allow nodes to communicate with cluster API server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

###############################################################################
# Security Group — EKS Nodes
###############################################################################
resource "aws_security_group" "node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS managed node group security group"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name                                             = "${local.name_prefix}-eks-node-sg"
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "owned"
  })
}

resource "aws_security_group_rule" "node_ingress_self" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_ingress_cluster" {
  description              = "Allow cluster control plane to communicate with nodes"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "node_ingress_cluster_443" {
  description              = "Allow cluster control plane webhook traffic to nodes"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

###############################################################################
# EKS Cluster
###############################################################################
resource "aws_eks_cluster" "this" {
  name     = "${local.name_prefix}-eks"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_creator_admin
  }

  enabled_cluster_log_types = var.cluster_log_types

  dynamic "encryption_config" {
    for_each = var.cluster_encryption_key_arn != null ? [1] : []
    content {
      resources = ["secrets"]
      provider {
        key_arn = var.cluster_encryption_key_arn
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
  ]
}

###############################################################################
# IAM — Node Group Role
###############################################################################
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

###############################################################################
# EKS Managed Node Groups
###############################################################################
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-ng-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  ami_type       = each.value.ami_type
  disk_size      = each.value.disk_size

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable_percentage = lookup(each.value, "max_unavailable_percentage", 33)
  }

  dynamic "taint" {
    for_each = lookup(each.value, "taints", [])
    content {
      key    = taint.value.key
      value  = lookup(taint.value, "value", null)
      effect = taint.value.effect
    }
  }

  labels = each.value.labels

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ng-${each.key}"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_readonly,
  ]
}

###############################################################################
# Cluster Autoscaler discovery tags on each node group's ASG.
# EKS does NOT propagate node-group tags to the underlying ASG, so the
# cluster-autoscaler (auto-discovery mode) cannot find the group without these.
# Tag the ASG directly so it can scale the group up/down on pod pressure.
###############################################################################
resource "aws_autoscaling_group_tag" "ca_enabled" {
  for_each               = aws_eks_node_group.this
  autoscaling_group_name = each.value.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "ca_cluster" {
  for_each               = aws_eks_node_group.this
  autoscaling_group_name = each.value.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${aws_eks_cluster.this.name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

###############################################################################
# EKS Add-ons
###############################################################################
locals {
  default_addons = {
    coredns = {
      addon_version = lookup(var.addon_versions, "coredns", null)
    }
    kube-proxy = {
      addon_version = lookup(var.addon_versions, "kube-proxy", null)
    }
    vpc-cni = {
      addon_version = lookup(var.addon_versions, "vpc-cni", null)
    }
    # Pod Identity Agent — required for EKS Pod Identity
    eks-pod-identity-agent = {
      addon_version = lookup(var.addon_versions, "eks-pod-identity-agent", null)
    }
  }

  all_addons = merge(local.default_addons, var.additional_addons)
}

resource "aws_eks_addon" "this" {
  for_each = local.all_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-addon-${each.key}"
  })

  depends_on = [aws_eks_node_group.this]
}

###############################################################################
# Pod Identity — IAM Roles for pods
# Uses EKS Pod Identity (NOT IRSA)
###############################################################################
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  for_each = var.pod_identity_associations

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_eks_cluster.this.arn]
    }
  }
}

resource "aws_iam_role" "pod_identity" {
  for_each = var.pod_identity_associations

  name               = "${local.name_prefix}-pod-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role[each.key].json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-pod-${each.key}"
  })
}

# Attach managed policies to pod identity roles
resource "aws_iam_role_policy_attachment" "pod_identity_managed" {
  for_each = {
    for pair in flatten([
      for role_key, assoc in var.pod_identity_associations : [
        for policy_arn in assoc.managed_policy_arns : {
          key        = "${role_key}__${replace(policy_arn, "/", "_")}"
          role_key   = role_key
          policy_arn = policy_arn
        }
      ]
    ]) : pair.key => pair
  }

  role       = aws_iam_role.pod_identity[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

# Attach inline policies to pod identity roles
resource "aws_iam_role_policy" "pod_identity_inline" {
  for_each = {
    for k, v in var.pod_identity_associations : k => v
    if v.inline_policy != null
  }

  name   = "${local.name_prefix}-pod-${each.key}-policy"
  role   = aws_iam_role.pod_identity[each.key].id
  policy = each.value.inline_policy
}

# EKS Pod Identity Associations — links K8s service account to IAM role
resource "aws_eks_pod_identity_association" "this" {
  for_each = var.pod_identity_associations

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.pod_identity[each.key].arn

  tags = merge(local.common_tags, {
    Name           = "${local.name_prefix}-pod-identity-${each.key}"
    ServiceAccount = each.value.service_account
    Namespace      = each.value.namespace
  })

  depends_on = [aws_eks_addon.this]
}
