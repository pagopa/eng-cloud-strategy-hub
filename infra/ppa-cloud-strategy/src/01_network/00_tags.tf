module "tag_config" {
  source         = "../tag_config"
  domain         = var.domain
  environment    = var.env
  prefix         = var.prefix
  env_short      = var.env_short
  location       = var.location
  location_short = var.location_short
}
