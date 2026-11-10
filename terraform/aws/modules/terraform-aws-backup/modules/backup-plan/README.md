# backup-plan (sotto-modulo)

Mattoncino riusabile che crea un `aws_backup_plan` con una o più regole e una `aws_backup_selection` (per tag e/o per tipo/ARN). È la **fonte unica di verità** per la logica dei piani di backup in questo repository.

## Chi lo usa

- Il **modulo core** (`terraform-aws-backup`) per il piano giornaliero di default.
- I **preset** sotto `presets/` (hourly, long-retention, archival, weekly-full), che sono wrapper sottili con default opinati.
- I **team di prodotto** direttamente, per aggiungere piani su misura accanto a quello di default.

## Utilizzo

```hcl
module "extra_plan" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup/modules/backup-plan?ref=aws-backup-v1.0.0"

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
      delete_after      = 35
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
| `rules` | Effective native rule set, including lifecycle and copy actions. |
| `selection_tags` | Effective native ListOfTags set; multiple tags use OR. |

The Git ref above is a proposed, unpublished first release; use an available
immutable commit containing the changes until it is published. Callers supply
the AWS provider, role, and existing vault names.

Rule names must be unique. Retention must be positive whole days. Snapshot and
copy cold transition requires at least 90 subsequent retained days. Continuous
retention is 1-35 days and cannot use cold storage. Copying a continuous recovery
point does not certify PITR at the destination.

Tag entries use AWS `ListOfTags` OR semantics; they are not `Conditions` AND.
Resource ARNs and types remain a union, and exclusions remain `NotResources`.
External vault minima/maxima and service-specific cold/copy availability are
caller-owned: this module cannot infer an external vault's lock settings.

Native [tests](./tests/) run in CI through `make terraform-backup-check`.

The final selection name must use 1-50 letters, digits, hyphens, underscores,
or periods. Set `selection_name` explicitly if `<plan_name>-selection` is too
long. Existing valid names are preserved; the module never truncates them.

Each inclusion or exclusion list supports up to 500 distinct ARNs, including
at most 30 wildcard ARNs. Service-derived patterns count toward the inclusion
limit. `selection_tags` supports at most 30 entries. Start windows must be at
least 60 whole minutes; completion windows must be positive whole minutes.

`Aurora` expands to `arn:aws:rds:*:*:cluster:*`, which is not an engine filter
and can also match DocumentDB or Neptune clusters, subject to service opt-in.
For Aurora-only scope, omit `resource_types` and use exact, caller-verified
Aurora cluster `resource_arns` with no additional OR tags, or use only a
dedicated selection tag. Adding a tag does not narrow a type-wide wildcard.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.30.0, < 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.30.0, < 6.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_backup_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_iam_role_arn"></a> [iam\_role\_arn](#input\_iam\_role\_arn) | ARN of the IAM role AWS Backup assumes to run the plan (usually the backup role from the core module). | `string` | n/a | yes |
| <a name="input_plan_name"></a> [plan\_name](#input\_plan\_name) | Name of the backup plan. Also used as a prefix for the selection name. | `string` | n/a | yes |
| <a name="input_rules"></a> [rules](#input\_rules) | List of backup rules for the plan. Each rule supports lifecycle, continuous<br/>backup and cross-region copy actions. Optional attributes fall back to<br/>sensible defaults. | <pre>list(object({<br/>    rule_name                = string<br/>    target_vault_name        = string<br/>    schedule                 = string<br/>    start_window             = optional(number, 480)<br/>    completion_window        = optional(number, 960)<br/>    enable_continuous_backup = optional(bool, false)<br/>    cold_storage_after       = optional(number, 0)<br/>    delete_after             = number<br/>    recovery_point_tags      = optional(map(string), {})<br/>    copy_actions = optional(list(object({<br/>      destination_vault_arn = string<br/>      cold_storage_after    = optional(number, 0)<br/>      delete_after          = number<br/>    })), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_excluded_resource_arns"></a> [excluded\_resource\_arns](#input\_excluded\_resource\_arns) | Optional list of resource ARNs (or wildcard ARNs) to exclude from selection (not\_resources). Useful to exclude ephemeral resources when selecting by service type. | `list(string)` | `[]` | no |
| <a name="input_resource_arns"></a> [resource\_arns](#input\_resource\_arns) | Optional list of explicit resource ARNs (or wildcard ARNs) to select. Combined (OR) with resource\_types and selection\_tags. | `list(string)` | `[]` | no |
| <a name="input_resource_types"></a> [resource\_types](#input\_resource\_types) | Optional list of AWS service types to select ALL of their resources via<br/>wildcard ARNs (e.g. ["DynamoDB", "S3", "RDS"]). An alternative to tag-based<br/>selection.<br/><br/>The set of supported types is defined by the resource\_type\_arns map in<br/>locals.tf (currently: S3, DynamoDB, EC2, EBS, RDS, Aurora, EFS). To add a<br/>new type, add a single entry to that map.<br/>Note: AWS Backup allows at most 30 wildcard ARNs per selection. | `list(string)` | `[]` | no |
| <a name="input_selection_name"></a> [selection\_name](#input\_selection\_name) | Name of the backup selection. Defaults to "<plan\_name>-selection". | `string` | `null` | no |
| <a name="input_selection_tags"></a> [selection\_tags](#input\_selection\_tags) | Tag key/value pairs used to select resources for this plan. Combined (OR) with resource\_types and resource\_arns when those are set. | `map(string)` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the backup plan. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_plan_arn"></a> [plan\_arn](#output\_plan\_arn) | ARN of the backup plan. |
| <a name="output_plan_id"></a> [plan\_id](#output\_plan\_id) | ID of the backup plan. |
| <a name="output_rules"></a> [rules](#output\_rules) | Effective native rule set, including lifecycle and copy actions. External vault lock compatibility remains caller-owned. |
| <a name="output_selection_id"></a> [selection\_id](#output\_selection\_id) | ID of the backup selection. |
| <a name="output_selection_tags"></a> [selection\_tags](#output\_selection\_tags) | Effective native ListOfTags selection set. Multiple entries use OR, not Conditions/AND. |
<!-- END_TF_DOCS -->