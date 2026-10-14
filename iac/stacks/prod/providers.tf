terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    # random_password (DB + JWT). Undeclared, Terraform guesses hashicorp/random
    # with no version constraint -- tflint flags it, and a guess is not a pin.
    random = { source = "hashicorp/random", version = "~> 3.9" }
  }
  backend "s3" {
    key            = "stacks/prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "shopglobe-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project    = "shopglobe"
      Env        = var.environment
      Service    = "platform"
      Owner      = var.owner
      CostCenter = "learning"
      ManagedBy  = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}
