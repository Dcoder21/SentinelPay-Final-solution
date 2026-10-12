terraform {

  required_version = ">= 1.7.0"

  required_providers {

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {

  region = var.aws_region

  default_tags {

    tags = {
      Project = var.project_name

      Environment = var.environment

      ManagedBy = "Terraform"
    }
  }
}