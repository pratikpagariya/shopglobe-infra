terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.80" }
  }
}

provider "aws" {
  region = var.region

  # Every resource created by this stack inherits these. A resource CANNOT be
  # created untagged, which is the point -- policy in CI catches the rest.
  default_tags {
    tags = {
      Project    = "shopglobe"
      Env        = var.env
      Service    = "platform"
      Owner      = var.owner
      CostCenter = "learning"
      ManagedBy  = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Account ID is looked up, never hardcoded -- these repos are public, and it
# also makes the code portable to another account with no edits.
locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "shopglobe-tfstate-${local.account_id}"
  lock_table   = "shopglobe-tflock"
}
