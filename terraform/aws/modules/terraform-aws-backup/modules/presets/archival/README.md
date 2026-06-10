# Preset: archival

Wrapper sottile sopra [`backup-plan`](../../backup-plan/) per l'archiviazione a lungo termine ottimizzata sui costi: i recovery point passano presto in cold storage e vengono conservati per anni.

Default: retention di 3650 giorni, passaggio a cold storage dopo 30 giorni, giornaliero alle 03:00 UTC.

```hcl
module "archival" {
  source = "git::https://github.com/pagopa/<nome-repo>.git//modules/backup/modules/presets/archival?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn
  selection_tags  = { "backup-policy" = "archival" }
}
```

| Input | Default | Descrizione |
|-------|---------|-------------|
| `vault_name` | — | Vault esistente dal modulo core |
| `backup_role_arn` | — | ARN del ruolo di backup dal modulo core |
| `selection_tags` | — | Tag che selezionano le risorse per questo piano |
| `retention_days` | 3650 | Retention in giorni |
| `cold_storage_after` | 30 | Passaggio a cold storage (deve essere ≥ 90 sotto la retention) |
| `schedule` | `cron(0 3 * * ? *)` | Pianificazione del backup |
| `tags` | `{}` | Tag aggiuntivi |

Output: `plan_id`.

> AWS Backup richiede `delete_after >= cold_storage_after + 90`.
