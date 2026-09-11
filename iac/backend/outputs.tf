output "state_bucket" { value = aws_s3_bucket.state.id }
output "lock_table"   { value = aws_dynamodb_table.lock.name }
output "account_id"   { value = local.account_id }

# Paste-ready backend block for the dev/stage/prod stacks on Day 3
output "backend_config" {
  value = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "stacks/<ENV>/terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.lock.name}"
        encrypt        = true
      }
    }
  EOT
}
