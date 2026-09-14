###############################################################################
# Secrets Manager Module — main.tf
# Generic, reusable module. Driven by a map(object).
#
# Each secret can either:
#   - store an explicit value (secret_string), OR
#   - auto-generate a random password (generate = true), optionally wrapped
#     as JSON { "username": ..., "password": ... } when username is set, OR
#   - be created empty (no version) so an operator/app sets the value later.
#
# SENSITIVITY: some inputs are sensitive (e.g. a token injected via
# secret_string). Terraform forbids sensitive values in `for_each`, and any
# comprehension whose FILTER reads `secret_string` inherits that sensitivity.
# So every for_each iterates over NON-sensitive KEY SETS (the key names are not
# secret); the sensitive values are read only INSIDE the resources, where that
# is allowed. nonsensitive() is applied ONLY to the derived key sets, never to
# an actual secret value.
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(var.tags, {
    Module = "secrets"
  })

  # All secret keys (non-sensitive identifiers) — used to create the containers.
  all_keys = nonsensitive(toset(keys(var.secrets)))

  # Keys needing a generated password (generate=true, no explicit value). The
  # filter reads secret_string (may be sensitive), so the comprehension result
  # is marked sensitive — but the keys are not secret, so strip the mark.
  generated_keys = nonsensitive(toset([
    for k, v in var.secrets : k
    if v.generate && v.secret_string == null
  ]))

  # Keys that get a stored value (explicit secret_string OR generated).
  with_version_keys = nonsensitive(toset([
    for k, v in var.secrets : k
    if v.secret_string != null || v.generate
  ]))
}

###############################################################################
# Random passwords (only for generate=true without an explicit value)
###############################################################################
resource "random_password" "this" {
  for_each = local.generated_keys

  length           = var.secrets[each.key].length
  special          = var.secrets[each.key].special
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

###############################################################################
# Secret containers
###############################################################################
resource "aws_secretsmanager_secret" "this" {
  for_each = local.all_keys

  name                    = "${local.name_prefix}-${each.key}"
  description             = var.secrets[each.key].description
  recovery_window_in_days = var.secrets[each.key].recovery_window_in_days
  kms_key_id              = var.kms_key_id

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${each.key}"
    Secret = each.key
  })
}

###############################################################################
# Secret values  (sensitive values are fine HERE — they're just not allowed in
# for_each). The ternary reads secret_string only inside the resource.
###############################################################################
resource "aws_secretsmanager_secret_version" "this" {
  for_each = local.with_version_keys

  secret_id = aws_secretsmanager_secret.this[each.key].id

  secret_string = var.secrets[each.key].secret_string != null ? var.secrets[each.key].secret_string : (
    var.secrets[each.key].username != null
    ? jsonencode({ username = var.secrets[each.key].username, password = random_password.this[each.key].result })
    : jsonencode({ password = random_password.this[each.key].result })
  )

  lifecycle {
    # Allow values to be rotated out-of-band without Terraform reverting them.
    ignore_changes = [secret_string]
  }
}
