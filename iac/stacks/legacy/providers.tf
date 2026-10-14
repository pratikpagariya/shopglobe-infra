terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.80" }
  }
  backend "s3" {
    key            = "stacks/legacy/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "shopglobe-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "shopglobe", Env = "legacy", Service = "monolith-host"
      Owner   = var.owner, CostCenter = "learning", ManagedBy = "terraform"
    }
  }
}

data "aws_availability_zones" "available" { state = "available" }

# Canonical's published AMI id, looked up not hardcoded -- a hardcoded AMI is
# stale within a month and is region-specific.
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
  name = "shopglobe-legacy"
}
