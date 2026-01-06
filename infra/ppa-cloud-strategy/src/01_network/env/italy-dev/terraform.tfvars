# general
prefix         = "csh"
env_short      = "d"
env            = "dev"
domain         = "core"
location       = "italy"
location_short = "ita"
aws_region     = "eu-south-1"

vpc_name                  = "sch-vpc"
vpc_cidr                  = "10.0.0.0/16"
azs                       = ["eu-south-1a", "eu-south-1b", "eu-south-1c"]
vpc_private_subnets_cidr  = ["10.0.80.0/20", "10.0.64.0/20", "10.0.48.0/20"]
vpc_public_subnets_cidr   = ["10.0.120.0/21", "10.0.112.0/21", "10.0.104.0/21"]
vpc_internal_subnets_cidr = ["10.0.32.0/20", "10.0.16.0/20", "10.0.0.0/20"]
enable_nat_gateway        = false
single_nat_gateway        = false
