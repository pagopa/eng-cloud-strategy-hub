# Preset: hourly-backup

Wrapper sottile sopra [`backup-plan`](../../backup-plan/) per workload a basso RPO che necessitano di un recovery point ogni ora (decisione §5 — estensioni di piano a livello di team).

Default: pianificazione oraria, retention di 7 giorni, finestra di avvio di 60 minuti.

```hcl
module "hourly" {
  source = "git::https://github.com/pagopa/<nome-repo>.git//modules/backup/modules/presets/hourly-backup?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn
  selection_tags  = { "backup-policy" = "hourly" }
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
