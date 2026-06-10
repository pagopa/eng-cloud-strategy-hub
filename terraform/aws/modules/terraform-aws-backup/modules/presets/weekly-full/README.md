# Preset: weekly-full

Wrapper sottile sopra [`backup-plan`](../../backup-plan/) per un recovery point settimanale garantito, in aggiunta al piano giornaliero di default.

Default: pianificazione settimanale (domenica 02:00 UTC), retention di 90 giorni.

```hcl
module "weekly_full" {
  source = "git::https://github.com/pagopa/<nome-repo>.git//modules/backup/modules/presets/weekly-full?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn
  selection_tags  = { "backup-policy" = "weekly" }
}
```

| Input | Default | Descrizione |
|-------|---------|-------------|
| `vault_name` | — | Vault esistente dal modulo core |
| `backup_role_arn` | — | ARN del ruolo di backup dal modulo core |
| `selection_tags` | — | Tag che selezionano le risorse per questo piano |
| `retention_days` | 90 | Retention in giorni |
| `schedule` | `cron(0 2 ? * SUN *)` | Pianificazione settimanale |
| `tags` | `{}` | Tag aggiuntivi |

Output: `plan_id`.
