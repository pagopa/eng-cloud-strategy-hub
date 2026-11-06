terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72.0, < 6.0.0"
    }
  }
}
provider "aws" { region = "eu-south-1" }
provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}
module "backup" {
  for_each = toset(["orders", "payments"])
  source   = "../../.."
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
  aws_region      = "eu-south-1"
  dr_region       = "eu-central-1"
  environment     = "prod"
  solution_prefix = "test-${each.key}-prod"
  selection_tags  = { backup-workload = each.key }
}
module "counted" {
  count  = 1
  source = "../../.."
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
  aws_region      = "eu-south-1"
  dr_region       = "eu-central-1"
  environment     = "prod"
  solution_prefix = "test-counted-prod"
  selection_tags  = { backup-workload = "counted" }
}
output "vault_names" {
  value = concat([for backup in module.backup : backup.vault_name], [for backup in module.counted : backup.vault_name])
}
