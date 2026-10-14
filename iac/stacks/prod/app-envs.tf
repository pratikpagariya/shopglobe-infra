# App environments are NAMESPACES on this one cluster (README). The cluster is
# shared; the data must not be. Each app env gets its own queue, bucket, topic
# and JWT key, and each namespace's pods get a role that reaches ONLY its own
# env's copy. Without this, an order placed in shopglobe-dev would be charged
# by prod's payment-worker -- both would read the same queue.
locals {
  app_envs = toset(["dev", "stage", "prod"])
}

resource "aws_s3_bucket" "media" {
  for_each = local.app_envs

  # Bucket names are global across ALL AWS accounts; the account id suffix
  # keeps this one from colliding with a stranger's.
  bucket        = "shopglobe-${each.key}-media-${local.account_id}"
  force_destroy = true # demo: lets `terraform destroy` empty it first

  tags = { AppEnv = each.key }
}

resource "aws_s3_bucket_public_access_block" "media" {
  for_each = aws_s3_bucket.media

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sns_topic" "notifications" {
  for_each = local.app_envs

  name = "shopglobe-${each.key}-notifications"
  tags = { AppEnv = each.key }
}

# auth-svc reports NOT ready outside dev while it still has its built-in key.
# One key per env: a token minted in dev must not verify in prod.
resource "random_password" "jwt" {
  for_each = local.app_envs

  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  for_each = local.app_envs

  name                    = "shopglobe/${each.key}/auth-jwt"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  for_each = local.app_envs

  secret_id     = aws_secretsmanager_secret.jwt[each.key].id
  secret_string = jsonencode({ JWT_SECRET = random_password.jwt[each.key].result })
}

# One role per (service, app env). A Pod Identity association is keyed on
# cluster + NAMESPACE + service account, so shopglobe-dev/order-svc and
# shopglobe-prod/order-svc are different identities -- which is what lets
# dev's role be denied prod's queue.
locals {
  app_pod_identities = merge([
    for env in local.app_envs : {
      "order-svc-${env}" = {
        namespace       = "shopglobe-${env}"
        service_account = "order-svc"
        inline_policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
            Resource = module.sqs_payments[env].queue_arn
          }]
        })
      }

      "payment-worker-${env}" = {
        namespace       = "shopglobe-${env}"
        service_account = "payment-worker"
        inline_policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
            Resource = module.sqs_payments[env].queue_arn
          }]
        })
      }

      "media-svc-${env}" = {
        namespace       = "shopglobe-${env}"
        service_account = "media-svc"
        inline_policy = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              # HeadBucket (the readiness check) is authorised by ListBucket on
              # the BUCKET arn. Object actions go on bucket/*. Mixing the two
              # up is the classic S3 AccessDenied.
              Effect   = "Allow"
              Action   = ["s3:ListBucket"]
              Resource = aws_s3_bucket.media[env].arn
            },
            {
              # A presigned URL carries THIS role's permissions: whoever holds
              # the URL can do exactly what this pod could, until it expires.
              Effect   = "Allow"
              Action   = ["s3:GetObject", "s3:PutObject"]
              Resource = "${aws_s3_bucket.media[env].arn}/*"
            },
          ]
        })
      }

      "notify-svc-${env}" = {
        namespace       = "shopglobe-${env}"
        service_account = "notify-svc"
        inline_policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["sns:Publish", "sns:GetTopicAttributes"]
            Resource = aws_sns_topic.notifications[env].arn
          }]
        })
      }
    }
  ]...)
}
