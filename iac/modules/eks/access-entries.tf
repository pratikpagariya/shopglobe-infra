# Direction matters, and interviewers probe it:
#   Pod Identity     = pod  -> AWS   (a workload assuming an IAM role)
#   Access Entries   = AWS  -> cluster (an IAM principal getting k8s RBAC)
# Opposite arrows, different problems.

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  type              = each.value.type
  kubernetes_groups = each.value.kubernetes_groups

  tags = merge(local.common_tags, { Name = each.key })
}

# A nested for_each is not allowed, so flatten entry x policy into one map
# first. This merge([...]...) idiom is the standard way -- note the trailing
# ellipsis, which expands the list into merge()'s arguments.
locals {
  access_policy_pairs = merge([
    for entry_key, entry in var.access_entries : {
      for policy_key, policy in entry.policies :
      "${entry_key}:${policy_key}" => {
        principal_arn     = entry.principal_arn
        policy_arn        = policy.policy_arn
        access_scope_type = policy.access_scope_type
        namespaces        = policy.namespaces
      }
    }
  ]...)
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.access_policy_pairs

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope_type
    namespaces = each.value.access_scope_type == "namespace" ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.this]
}
