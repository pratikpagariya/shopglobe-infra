terraform {
  backend "s3" {
    key            = "bootstrap/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "shopglobe-tflock"
    encrypt        = true
  }
}
