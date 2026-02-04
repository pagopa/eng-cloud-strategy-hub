module "key_pair" {
  # v2.1.0 (2025-05-07) pinned by commit SHA
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-key-pair.git?ref=9075105cb16824980e01dd31e0e51c5d1ffa5923"

  key_name           = var.key_name
  create_private_key = true
  tags               = var.tags
}
