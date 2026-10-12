terraform {

  backend "s3" {

    bucket = "sentinelpay-terraform-state-683b3118"

    key = "environments/dev/terraform.tfstate"

    region = "eu-west-1"

    encrypt = true

    dynamodb_table = "sentinelpay-terraform-locks"
  }
}
