module "idvh_sample" {
  source = "./modules/idvh_sample"

  key_name = "${local.project}-idvh"
  tags     = module.tag_config.tags
}
