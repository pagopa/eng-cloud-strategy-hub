# data "external" "terrasops" {
#   for_each = toset(local.secret_scopes)

#   program = ["bash", "terrasops.sh"]
#   query = {
#     path = "secrets/${each.key}/${var.location_short}-${var.env}"
#   }
# }

# locals {
#   all_enc_secrets_value = {
#     for key, ext in data.external.terrasops :
#     key => can(ext.result) ? [
#       for k, v in ext.result : {
#         sec_val = v
#         sec_key = k
#       }
#     ] : []
#   }

#   secrets_flat = flatten([
#     for scope, secrets in local.all_enc_secrets_value : [
#       for s in secrets : merge(s, { key_vault = scope })
#     ]
#   ])

#   secrets_by_name = {
#     for s in local.secrets_flat : "${s.key_vault}-${s.sec_key}" => s
#   }
# }

# resource "aws_secretsmanager_secret" "sops_secret" {
#   for_each = local.secrets_by_name

#   name       = "${local.project_nodomain}-${each.value.key_vault}-${each.value.sec_key}"
#   kms_key_id = aws_kms_key.sops_key[each.value.key_vault].arn
# }

# resource "aws_secretsmanager_secret_version" "sops_secret_value" {
#   for_each = local.secrets_by_name

#   secret_id     = aws_secretsmanager_secret.sops_secret[each.key].id
#   secret_string = each.value.sec_val
# }
