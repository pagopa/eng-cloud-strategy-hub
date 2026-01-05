locals {
  secret_env = "${var.location}-${var.env}"

  decrypted_secrets_by_scope = {
    for scope, ext in data.external.terrasops :
    scope => can(ext.result) ? ext.result : {}
  }

  secrets_by_name = merge([
    for scope, secrets in local.decrypted_secrets_by_scope : {
      for key, value in secrets : "${scope}-${key}" => {
        key_vault = scope
        sec_key   = key
        sec_val   = value
      }
    }
  ]...)
}

data "external" "terrasops" {
  for_each = toset(local.secret_scopes)

  program = ["bash", "terrasops.sh"]
  query = {
    env   = local.secret_env
    scope = each.key
  }
}

resource "aws_secretsmanager_secret" "sops_secret" {
  for_each = local.secrets_by_name

  name                    = "${each.value.key_vault}-${each.value.sec_key}"
  kms_key_id              = aws_kms_key.sops_key[each.value.key_vault].arn
  recovery_window_in_days = var.secrets_recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "sops_secret_value" {
  for_each = local.secrets_by_name

  secret_id     = aws_secretsmanager_secret.sops_secret[each.key].id
  secret_string = each.value.sec_val
}
