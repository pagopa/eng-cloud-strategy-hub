# Preset: long-retention

Wrapper sottile sopra [`backup-plan`](../../backup-plan/) per la conservazione normativa a lungo termine (decisione §7.3 — ≥ 10 anni per dati critici e tracciati di pagamento).

Default: retention di 3650 giorni, passaggio a cold storage dopo 90 giorni, giornaliero alle 02:00 UTC.

```hcl
module "long_retention" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup/modules/presets/long-retention?ref=aws-backup-v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn
  selection_tags  = { "backup-data-class" = "critical" }
}
```

| Input | Default | Descrizione |
|-------|---------|-------------|
| `vault_name` | — | Vault esistente dal modulo core |
| `backup_role_arn` | — | ARN del ruolo di backup dal modulo core |
| `selection_tags` | — | Tag che selezionano le risorse per questo piano |
| `retention_days` | 3650 | Retention in giorni |
| `cold_storage_after` | 90 | Passaggio a cold storage (deve essere ≥ 90 sotto la retention) |
| `schedule` | `cron(0 2 * * ? *)` | Pianificazione del backup |
| `tags` | `{}` | Tag aggiuntivi |

Output: `plan_id`.

The release ref is proposed and unpublished; use an available immutable commit
containing the changes until publication. Callers own the AWS provider, existing
vault, IAM role, and compatibility with external vault lock bounds. Retention
must leave at least 90 days after cold transition; service support is not
inferred from tags. Native [tests](./tests/) run in CI through
`make terraform-backup-check`.

Optional `plan_name` and `selection_name` inputs preserve the current defaults.
The final selection name must fit 50 characters. Without overrides, `vault_name`
must fit 20 characters. For a longer existing vault name, pass a shorter
`selection_name`; do not rename the vault or truncate existing names.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.30.0, < 6.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_plan"></a> [plan](#module\_plan) | ../../backup-plan | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the backup IAM role (from the core module output). | `string` | n/a | yes |
| <a name="input_selection_tags"></a> [selection\_tags](#input\_selection\_tags) | Tags to select resources for long-retention backup. | `map(string)` | n/a | yes |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the existing backup vault (from the core module). | `string` | n/a | yes |
| <a name="input_cold_storage_after"></a> [cold\_storage\_after](#input\_cold\_storage\_after) | Days before transitioning to cold storage. Must be at least 90 days below retention\_days. | `number` | `90` | no |
| <a name="input_plan_name"></a> [plan\_name](#input\_plan\_name) | Optional explicit plan name. Defaults to <vault\_name>-long-retention-plan. | `string` | `null` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Retention period in days. Defaults to 10 years. | `number` | `3650` | no |
| <a name="input_schedule"></a> [schedule](#input\_schedule) | Cron expression for the backup schedule. | `string` | `"cron(0 2 * * ? *)"` | no |
| <a name="input_selection_name"></a> [selection\_name](#input\_selection\_name) | Optional explicit selection name. Defaults to <plan\_name>-selection; the final name must use 1-50 letters, digits, underscores, periods or hyphens. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_plan_id"></a> [plan\_id](#output\_plan\_id) | n/a |
<!-- END_TF_DOCS -->