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
