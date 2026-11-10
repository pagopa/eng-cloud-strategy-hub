# terraform-aws-backup-alerting

Modulo Terraform per l'alerting di AWS Backup. Crea regole EventBridge, un topic SNS e le relative sottoscrizioni per notificare ai team i job di backup falliti via email.

The module is independently callable and requires only the caller's primary AWS provider. Modules composed in one root share deployment and state; separate state is a caller decision.

Replace `<COMMIT_SHA>` in the Git sources below with a published immutable commit
that has passed the required CI checks. The proposed `aws-backup-v1.0.0` release
is not published or verified. Callers own credentials, assume-role configuration,
backend, and unique workload/environment/region-specific resource prefixes.

## Indice

- [Come funziona](#come-funziona)
- [Utilizzo rapido](#utilizzo-rapido)
- [Consumer setup and regional scope](#consumer-setup-and-regional-scope)
- [Requisiti](#requisiti)
- [Architettura](#architettura)
- [Funzionalità](#funzionalità)
- [Eventi intercettati](#eventi-intercettati)
- [Endpoint di notifica](#endpoint-di-notifica)
- [Usare un topic SNS esistente](#usare-un-topic-sns-esistente)
- [Input](#input)
- [Output](#output)
- [Relazione con il modulo core](#relazione-con-il-modulo-core)

## Come funziona

AWS Backup emette eventi sullo stato dei job. Questo modulo crea una regola EventBridge che intercetta i job falliti (backup, copy, restore) e li inoltra a un topic SNS, che a sua volta li recapita agli indirizzi email configurati. Una seconda regola monitora la cancellazione e la disabilitazione delle chiavi KMS di backup. Il topic SNS è cifrato con una chiave customer-managed (CMK).

## Utilizzo rapido

```hcl
module "backup_alerting" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup-alerting?ref=<COMMIT_SHA>"

  providers = { aws = aws }

  solution_prefix = "payments-prod-eu-south-1"

  # Monitora la CMK del backup contro la cancellazione accidentale
  kms_key_ids = [module.backup.kms_key_id]

  # Alert via email
  email_endpoints = ["team-payments-oncall@pagopa.it"]

  tags = {
    "backup-owner" = "team-payments"
  }
}
```

> Le sottoscrizioni email richiedono una conferma: ogni indirizzo riceve un messaggio di conferma da AWS SNS e deve cliccare il link prima di ricevere gli alert.

## Consumer setup and regional scope

Use the same integration in non-production and production, with environment-
specific prefixes and recipients. Declare the caller's AWS provider before the
module call. See the [core consumer guide](../terraform-aws-backup/README.md)
for minimal configurations and the difference between snapshots and PITR.

- `solution_prefix` must contain 2-45 characters and names this module's rules,
  topic, and KMS alias. It does not
  select workload resources or restrict backup-job events to that prefix.
- `kms_key_ids` scopes the KMS event filter. Use `[module.backup.kms_key_id]`
  for the primary vault key. An empty list leaves the KMS rule unfiltered by key.
- This module has no `selection_tags` input. Backup/copy/restore event filtering
  uses configured event types and states, not the core's workload tags.
- It is independently callable without core if the caller supplies the required
  values. Composing both in one root does not give them separate state.
- SNS confirmation and real delivery tests are required. Mocked policies and
  subscription creation are not evidence that recipients receive alerts.

Backup and copy events are matched on `detail.state`; restore events are
matched on `detail.status`. The rule accepts either field through an OR
condition, using `backup_failure_event_states` for both.

`kms_key_ids` accepts key IDs or key ARNs. The KMS rule matches both forms of
`requestParameters.keyId`, including multi-Region key IDs. ARN suffix matching
covers requests using the ARN rather than the ID. Monitoring remains scoped
to the provider's account and Region.

### Compatibility

Only email subscriptions are managed. Remove the former webhook, SQS, and
Lambda endpoint inputs from callers before upgrading. An apply removes any
non-email subscriptions previously managed by this module; it does not delete
their destination queues or functions. Review the consumer's saved plan before
applying. Existing topics may retain subscriptions managed outside this module.
Prefixes longer than 45 characters are now rejected.

For DR coverage in production, add a separate regional instance:

```hcl
module "backup_alerting_dr" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup-alerting?ref=<COMMIT_SHA>"

  providers = { aws = aws.dr }

  solution_prefix = "payments-prod-eu-central-1"
  kms_key_ids     = [module.backup.dr_kms_key_id]
  email_endpoints = ["oncall@example.com"]
}
```

This assumes the production core and caller's `aws.dr` provider already exist.
Do not use this block for non-production, where the core DR key ID is null.
Primary-region alerting does not automatically observe the DR region.

## Requisiti

| Nome | Versione |
|------|----------|
| terraform | >= 1.5.0 |
| aws | >= 5.30.0, < 6.0.0 |

## Architettura

```
                    AWS Backup
                        │
                  emette eventi
                        │
                        ▼
              ┌─────────────────┐
              │  EventBridge     │
              │                  │
              │ Regola: stato=FAIL│
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │   Topic SNS      │
              └────────┬────────┘
                       │
                       ▼
                     Email
```

## Funzionalità

- **Regola EventBridge per i fallimenti** — intercetta gli stati `FAILED`, `EXPIRED`, `ABORTED` per i job di backup, copy e restore.
- **Regola EventBridge per la cancellazione delle chiavi KMS** — avvisa quando una CMK di backup viene schedulata per la cancellazione o disabilitata (evento critico).
- **Topic SNS** — hub di fan-out per le notifiche email.
- **Notifiche email** — sottoscrizioni SNS per gli indirizzi configurati, con conferma richiesta.
- **Topic esistente (bring-your-own)** — in alternativa alla creazione di un nuovo topic.
- **Cifratura e sicurezza** — topic cifrato con CMK; la policy del topic limita la pubblicazione alle sole regole EventBridge del modulo (protezione confused-deputy) e impone TLS.

## Eventi intercettati

| Evento | Detail Type | Condizione di trigger |
|--------|-------------|-----------------------|
| Fallimento job di backup | `Backup Job State Change` | `state = FAILED / EXPIRED / ABORTED` |
| Fallimento job di copy | `Copy Job State Change` | `state = FAILED / EXPIRED / ABORTED` |
| Fallimento job di restore | `Restore Job State Change` | `status = FAILED / EXPIRED / ABORTED` |
| Chiave KMS a rischio | `AWS API Call via CloudTrail` | `ScheduleKeyDeletion` o `DisableKey` sulle chiavi monitorate |

> Per monitorare la cancellazione delle chiavi, l'account deve avere CloudTrail attivo (è la sorgente degli eventi `AWS API Call via CloudTrail`). Se `kms_key_ids` è vuoto, la regola monitora tutte le chiavi dell'account.

## Endpoint di notifica

Gli indirizzi email sono opzionali. Puoi indicare più destinatari; gli indirizzi duplicati generano una sola sottoscrizione.

```hcl
email_endpoints = ["oncall@pagopa.it", "team@pagopa.it"]
```

## Usare un topic SNS esistente

Per inoltrare gli alert a un topic già esistente invece di crearne uno nuovo:

```hcl
module "backup_alerting" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup-alerting?ref=<COMMIT_SHA>"

  solution_prefix  = "payments-prod-eu-south-1"
  create_sns_topic = false
  existing_sns_topic_arn = "arn:aws:sns:eu-south-1:123456789012:topic-esistente"

  # Opzionale: lascia che il modulo gestisca anche la policy del topic
  # ATTENZIONE: sovrascrive la policy esistente del topic.
  manage_existing_topic_policy = false
}
```

## Input

| Variabile | Tipo | Obbligatoria | Default | Descrizione |
|-----------|------|--------------|---------|-------------|
| `solution_prefix` | string | no | `backup-solution` | Prefisso di 2-45 caratteri per tutte le risorse di alerting |
| `tag_identifier_prefix` | string | no | `solution_prefix` | Prefisso per il tag Name |
| `enable_backup_failure_alerts` | bool | no | `true` | Crea la regola EventBridge sui fallimenti |
| `backup_failure_event_states` | list(string) | no | FAILED, EXPIRED, ABORTED | Stati che generano un alert |
| `monitored_event_types` | list(string) | no | Backup/Copy/Restore Job State Change | Tipi di evento intercettati |
| `enable_kms_deletion_alert` | bool | no | `true` | Alert sulla cancellazione delle chiavi KMS |
| `kms_key_ids` | list(string) | no | `[]` | ID o ARN delle chiavi da monitorare (vuoto = tutte) |
| `create_sns_topic` | bool | no | `true` | Crea un nuovo topic SNS |
| `existing_sns_topic_arn` | string | no | `null` | ARN del topic esistente da usare |
| `manage_existing_topic_policy` | bool | no | `false` | Gestisce anche la policy del topic esistente (la sovrascrive) |
| `sns_kms_key_arn` | string | no | `null` | CMK esistente per cifrare il topic; se `null` ne viene creata una dedicata |
| `kms_deletion_window_in_days` | number | no | 30 | Finestra di cancellazione della CMK creata dal modulo (7-30) |
| `email_endpoints` | list(string) | no | `[]` | Indirizzi email da sottoscrivere |
| `tags` | map(string) | no | `{}` | Tag aggiuntivi |

## Output

| Nome | Descrizione |
|------|-------------|
| `sns_topic_arn` | ARN del topic SNS degli alert |
| `sns_topic_name` | Nome del topic SNS (null se si usa un topic esistente) |
| `eventbridge_rule_arn` | ARN della regola sui fallimenti di backup |
| `kms_deletion_rule_arn` | ARN della regola sulla cancellazione delle chiavi KMS |
| `sns_kms_key_arn` | ARN della CMK che cifra il topic SNS (null se nessun topic creato) |

## Relazione con il modulo core

```
┌──────────────────────────┐     ┌───────────────────────────────┐
│ terraform-aws-backup     │     │ terraform-aws-backup-alerting │
│                          │     │                               │
│ • Vault + Vault Lock     │     │ • Regole EventBridge          │
│ • Chiavi KMS             │────►│ • Topic SNS + sottoscrizioni  │
│ • Piano + Selezione      │     │ • Endpoint email              │
│ • Ruoli IAM              │     │                               │
│ • Restore Testing        │     │ Input: kms_key_id dal core    │
└──────────────────────────┘     └───────────────────────────────┘
```

The alerting module accepts `kms_key_ids` from core outputs or from independent
caller-managed keys. Its independent API does not create a separate Terraform
state when composed beside core.

When `create_sns_topic = false`, a non-empty `existing_sns_topic_arn` is required,
even if all rules are disabled. Its policy remains caller-managed unless
`manage_existing_topic_policy = true`; that opt-in replaces the existing policy.
Email endpoints are deduplicated.

Primary-region rules do not monitor DR automatically. Deploy another instance
with `providers = { aws = aws.dr }`, a distinct prefix, and the DR key ID when
DR-region coverage is required. Confirm SNS subscriptions and test real alert
delivery separately; mocked policy JSON is not IAM or delivery certification.

CI runs the standalone module and [independent example](./examples/) through
`make terraform-backup-check`. Mocked native tests cover event-pattern structure,
KMS identifier forms, prefix-length boundaries, and email deduplication.
No AWS credentials or real apply are used by the test workflow.

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
| [aws_cloudwatch_event_rule.backup_failures](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_rule.kms_deletion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.backup_failures_sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.kms_deletion_sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_kms_alias.sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_sns_topic.backup_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.backup_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.sns_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.sns_topic_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_failure_event_states"></a> [backup\_failure\_event\_states](#input\_backup\_failure\_event\_states) | Failure states that trigger an alert through backup/copy detail.state or restore detail.status. | `list(string)` | <pre>[<br/>  "FAILED",<br/>  "EXPIRED",<br/>  "ABORTED"<br/>]</pre> | no |
| <a name="input_create_sns_topic"></a> [create\_sns\_topic](#input\_create\_sns\_topic) | Whether to create a new SNS topic. Set to false if you want to use an existing topic. | `bool` | `true` | no |
| <a name="input_email_endpoints"></a> [email\_endpoints](#input\_email\_endpoints) | List of email addresses to subscribe to backup alerts. | `list(string)` | `[]` | no |
| <a name="input_enable_backup_failure_alerts"></a> [enable\_backup\_failure\_alerts](#input\_enable\_backup\_failure\_alerts) | Whether to create the EventBridge rule for backup/copy/restore failures. | `bool` | `true` | no |
| <a name="input_enable_kms_deletion_alert"></a> [enable\_kms\_deletion\_alert](#input\_enable\_kms\_deletion\_alert) | Whether to alert when a KMS key is scheduled for deletion. | `bool` | `true` | no |
| <a name="input_existing_sns_topic_arn"></a> [existing\_sns\_topic\_arn](#input\_existing\_sns\_topic\_arn) | ARN of an existing SNS topic to use. Required when create\_sns\_topic is false. | `string` | `null` | no |
| <a name="input_kms_deletion_window_in_days"></a> [kms\_deletion\_window\_in\_days](#input\_kms\_deletion\_window\_in\_days) | Waiting period in days before deletion of the SNS CMK created by this module. Between 7 and 30. | `number` | `30` | no |
| <a name="input_kms_key_ids"></a> [kms\_key\_ids](#input\_kms\_key\_ids) | List of KMS key IDs or key ARNs to monitor for ScheduleKeyDeletion and DisableKey. Matches requests using either ID or ARN in the provider's account and Region. If empty, monitors all keys. | `list(string)` | `[]` | no |
| <a name="input_manage_existing_topic_policy"></a> [manage\_existing\_topic\_policy](#input\_manage\_existing\_topic\_policy) | When using an existing SNS topic (create\_sns\_topic = false), also manage its access policy so EventBridge can publish. Leave false if the topic policy is managed elsewhere. WARNING: enabling this overwrites the existing topic's policy. | `bool` | `false` | no |
| <a name="input_monitored_event_types"></a> [monitored\_event\_types](#input\_monitored\_event\_types) | List of AWS Backup event detail-types to capture. | `list(string)` | <pre>[<br/>  "Backup Job State Change",<br/>  "Copy Job State Change",<br/>  "Restore Job State Change"<br/>]</pre> | no |
| <a name="input_sns_kms_key_arn"></a> [sns\_kms\_key\_arn](#input\_sns\_kms\_key\_arn) | ARN of an existing customer-managed KMS key to encrypt the SNS topic. If null (default), the module creates a dedicated CMK. AWS-managed keys (e.g. alias/aws/sns) are intentionally not supported — the key policy must allow events.amazonaws.com to call kms:GenerateDataKey* and kms:Decrypt. | `string` | `null` | no |
| <a name="input_solution_prefix"></a> [solution\_prefix](#input\_solution\_prefix) | Prefix for alerting resources created by this solution (EventBridge rules, SNS topic, KMS alias). Must be 2-45 characters so EventBridge rule names stay within 64 characters. | `string` | `"backup-solution"` | no |
| <a name="input_tag_identifier_prefix"></a> [tag\_identifier\_prefix](#input\_tag\_identifier\_prefix) | Prefix for the Name tag applied to resources created by this solution. Defaults to solution\_prefix. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_eventbridge_rule_arn"></a> [eventbridge\_rule\_arn](#output\_eventbridge\_rule\_arn) | ARN of the EventBridge rule for backup failures. |
| <a name="output_kms_deletion_rule_arn"></a> [kms\_deletion\_rule\_arn](#output\_kms\_deletion\_rule\_arn) | ARN of the EventBridge rule for KMS key deletion alerts. |
| <a name="output_sns_kms_key_arn"></a> [sns\_kms\_key\_arn](#output\_sns\_kms\_key\_arn) | ARN of the customer-managed KMS key encrypting the SNS topic (the one created by this module, or the one passed in via sns\_kms\_key\_arn). Null if no topic is created. |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS topic for backup alerts. |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | Name of the SNS topic. Null if using an existing topic. |
<!-- END_TF_DOCS -->