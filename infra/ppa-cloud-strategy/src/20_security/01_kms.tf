resource "aws_kms_key" "sops_key" {
  for_each = toset(local.secret_scopes)

  description             = "${local.project_nodomain}-${each.key}-sops"
  deletion_window_in_days = 30
  enable_key_rotation     = var.enable_kms_key_rotation
  tags                    = module.tag_config.tags
}

resource "aws_kms_alias" "sops_key" {
  for_each = toset(local.secret_scopes)

  name          = "alias/${local.project_nodomain}-${each.key}-sops"
  target_key_id = aws_kms_key.sops_key[each.key].key_id
}
