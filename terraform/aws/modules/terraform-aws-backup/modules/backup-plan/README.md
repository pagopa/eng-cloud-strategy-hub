# backup-plan (sotto-modulo)

Mattoncino riusabile che crea un `aws_backup_plan` con una o più regole e una `aws_backup_selection` (per tag e/o per tipo/ARN). È la **fonte unica di verità** per la logica dei piani di backup in questo repository.

## Chi lo usa

- Il **modulo core** (`terraform-aws-backup`) per il piano giornaliero di default.
- I **preset** sotto `presets/` (hourly, long-retention, archival, weekly-full), che sono wrapper sottili con default opinati.
- I **team di prodotto** direttamente, per aggiungere piani su misura accanto a quello di default.

## Utilizzo

```hcl
module "extra_plan" {
  source = "git::https://github.com/pagopa/<nome-repo>.git//modules/backup/modules/backup-plan?ref=v1.0.0"

  plan_name    = "team-payments-hourly"
  iam_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-policy" = "hourly"
  }

  rules = [
    {
      rule_name         = "hourly"
      target_vault_name = module.backup.vault_name
      schedule          = "cron(0 * * * ? *)"
      delete_after      = 7
    }
  ]
}
```

## Input

Vedi [variables.tf](./variables.tf). Ogni elemento di `rules` supporta: `rule_name`, `target_vault_name`, `schedule`, `start_window`, `completion_window`, `enable_continuous_backup`, `cold_storage_after`, `delete_after`, `recovery_point_tags` e una lista di `copy_actions` (ciascuna con `destination_vault_arn`, `cold_storage_after`, `delete_after`).

### Selezione delle risorse

Fornisci almeno un criterio; più criteri si combinano in **unione**:

| Variabile | Seleziona per |
|-----------|---------------|
| `selection_tags` | Tag della risorsa (metodo predefinito) |
| `resource_types` | Tutte le risorse di un tipo di servizio via ARN wildcard (es. `["DynamoDB","S3"]`) |
| `resource_arns` | ARN espliciti o wildcard |
| `excluded_resource_arns` | ARN da escludere (`not_resources`) |

Tipi supportati da `resource_types`: **S3, DynamoDB, EC2, EBS, RDS, Aurora, EFS**. AWS Backup ammette al massimo 30 ARN wildcard per selezione.

> **Aggiungere un nuovo tipo:** l'insieme dei tipi supportati è definito dalla mappa `resource_type_arns` in [locals.tf](./locals.tf). Per aggiungere un tipo basta inserire una riga in quella mappa con il relativo pattern ARN wildcard; la validazione dei tipi ammessi si aggiorna automaticamente. Se passi a `resource_types` un tipo non presente nella mappa, il `plan` fallisce con un messaggio esplicito (nessun fallimento silenzioso).
>
> Nota: questo vincolo riguarda **solo** la selezione per tipo. La selezione per **tag** non è limitata da questa lista — qualsiasi risorsa di un tipo supportato da AWS Backup che porta i tag indicati viene protetta.

> **Nota sul lifecycle:** quando `cold_storage_after` è impostato (> 0), `delete_after` deve essere almeno `cold_storage_after + 90` (requisito di AWS Backup).

## Output

| Nome | Descrizione |
|------|-------------|
| `plan_id` | ID del piano di backup |
| `plan_arn` | ARN del piano di backup |
| `selection_id` | ID della selezione di backup |
