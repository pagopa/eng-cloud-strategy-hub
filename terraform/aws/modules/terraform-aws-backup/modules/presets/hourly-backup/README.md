# Preset: hourly-backup

Wrapper sottile sopra [`backup-plan`](../../backup-plan/) per workload a basso RPO che necessitano di un recovery point ogni ora (decisione §5 — estensioni di piano a livello di team).

Default: pianificazione oraria, retention di 7 giorni, finestra di avvio di 60 minuti.

```hcl
module "hourly" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup/modules/presets/hourly-backup?ref=aws-backup-v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn
  selection_tags  = { "backup-policy" = "hourly" }
  retention_days = 35 # Override the 7-day default for a production vault.
}
```

| Input | Default | Descrizione |
|-------|---------|-------------|
| `vault_name` | — | Vault esistente dal modulo core |
| `backup_role_arn` | — | ARN del ruolo di backup dal modulo core |
| `selection_tags` | — | Tag che selezionano le risorse per questo piano |
| `retention_days` | 7 | Retention in giorni |
| `schedule` | `cron(0 * * * ? *)` | Pianificazione oraria |
| `tags` | `{}` | Tag aggiuntivi |

Output: `plan_id`.

The release ref is proposed and unpublished; use an available immutable commit
containing the changes until publication. Callers own the AWS provider, existing
vault, and IAM role. The isolated preset defaults to 7 days; it does not infer
external vault lock bounds. Every override must fit those bounds. Native
[tests](./tests/) run in CI through `make terraform-backup-check`.

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
| <a name="input_selection_tags"></a> [selection\_tags](#input\_selection\_tags) | Tags to select resources for hourly backup. Typically more specific than the default plan. | `map(string)` | n/a | yes |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the existing backup vault (from the core module). | `string` | n/a | yes |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Retention for hourly recovery points. | `number` | `7` | no |
| <a name="input_schedule"></a> [schedule](#input\_schedule) | Cron expression for hourly backup. | `string` | `"cron(0 * * * ? *)"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_plan_id"></a> [plan\_id](#output\_plan\_id) | n/a |
<!-- END_TF_DOCS -->