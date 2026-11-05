# terraform-aws-backup-alerting

Modulo Terraform per l'alerting di AWS Backup. Crea regole EventBridge, un topic SNS e le relative sottoscrizioni per notificare ai team i job di backup falliti via email (e altri endpoint supportati da SNS).

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

AWS Backup emette eventi sullo stato dei job. Questo modulo crea una regola EventBridge che intercetta i job falliti (backup, copy, restore) e li inoltra a un topic SNS, che a sua volta li recapita ai destinatari configurati (email per il rollout iniziale, oppure webhook, SQS, Lambda). Una seconda regola monitora la cancellazione delle chiavi KMS di backup, un evento critico. Il topic SNS è cifrato con una chiave customer-managed (CMK).

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

- `solution_prefix` names this module's rules, topic, and KMS alias. It does not
  select workload resources or restrict backup-job events to that prefix.
- `kms_key_ids` scopes the KMS event filter. Use `[module.backup.kms_key_id]`
  for the primary vault key. An empty list leaves the KMS rule unfiltered by key.
- This module has no `selection_tags` input. Backup/copy/restore event filtering
  uses configured event types and states, not the core's workload tags.
- It is independently callable without core if the caller supplies the required
  values. Composing both in one root does not give them separate state.
- SNS confirmation and real delivery tests are required. Mocked policies and
  subscription creation are not evidence that recipients receive alerts.

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
              └────┬───────┬────┘
                   │       │
          ┌────────┘       └────────┐
          ▼                         ▼
        Email                 Webhook (Grafana)
```

## Funzionalità

- **Regola EventBridge per i fallimenti** — intercetta gli stati `FAILED`, `EXPIRED`, `ABORTED` per i job di backup, copy e restore.
- **Regola EventBridge per la cancellazione delle chiavi KMS** — avvisa quando una CMK di backup viene schedulata per la cancellazione o disabilitata (evento critico).
- **Topic SNS** — hub di fan-out con supporto per più tipi di sottoscrizione.
- **Endpoint flessibili** — email, webhook HTTPS (Grafana, PagerDuty), SQS, Lambda.
- **Topic esistente (bring-your-own)** — in alternativa alla creazione di un nuovo topic.
- **Cifratura e sicurezza** — topic cifrato con CMK; la policy del topic limita la pubblicazione alle sole regole EventBridge del modulo (protezione confused-deputy) e impone TLS.

## Eventi intercettati

| Evento | Detail Type | Condizione di trigger |
|--------|-------------|-----------------------|
| Fallimento job di backup | `Backup Job State Change` | `state = FAILED / EXPIRED / ABORTED` |
| Fallimento job di copy | `Copy Job State Change` | `state = FAILED / EXPIRED / ABORTED` |
| Fallimento job di restore | `Restore Job State Change` | `state = FAILED / EXPIRED / ABORTED` |
| Chiave KMS a rischio | `AWS API Call via CloudTrail` | `ScheduleKeyDeletion` o `DisableKey` sulle chiavi monitorate |

> Per monitorare la cancellazione delle chiavi, l'account deve avere CloudTrail attivo (è la sorgente degli eventi `AWS API Call via CloudTrail`). Se `kms_key_ids` è vuoto, la regola monitora tutte le chiavi dell'account.

## Endpoint di notifica

Tutti gli endpoint sono opzionali e combinabili. Puoi indicare più destinatari per ciascun tipo.

```hcl
email_endpoints   = ["oncall@pagopa.it", "team@pagopa.it"]
webhook_endpoints = ["https://events.pagerduty.com/integration/xxx/enqueue"]
sqs_endpoints     = ["arn:aws:sqs:eu-south-1:123456789012:backup-alerts"]
lambda_endpoints  = ["arn:aws:lambda:eu-south-1:123456789012:function:process-alert"]
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
| `solution_prefix` | string | no | `backup-solution` | Prefisso per tutte le risorse di alerting |
| `tag_identifier_prefix` | string | no | `solution_prefix` | Prefisso per il tag Name |
| `enable_backup_failure_alerts` | bool | no | `true` | Crea la regola EventBridge sui fallimenti |
| `backup_failure_event_states` | list(string) | no | FAILED, EXPIRED, ABORTED | Stati che generano un alert |
| `monitored_event_types` | list(string) | no | Backup/Copy/Restore Job State Change | Tipi di evento intercettati |
| `enable_kms_deletion_alert` | bool | no | `true` | Alert sulla cancellazione delle chiavi KMS |
| `kms_key_ids` | list(string) | no | `[]` | ID delle chiavi da monitorare (vuoto = tutte) |
| `create_sns_topic` | bool | no | `true` | Crea un nuovo topic SNS |
| `existing_sns_topic_arn` | string | no | `null` | ARN del topic esistente da usare |
| `manage_existing_topic_policy` | bool | no | `false` | Gestisce anche la policy del topic esistente (la sovrascrive) |
| `sns_kms_key_arn` | string | no | `null` | CMK esistente per cifrare il topic; se `null` ne viene creata una dedicata |
| `kms_deletion_window_in_days` | number | no | 30 | Finestra di cancellazione della CMK creata dal modulo (7-30) |
| `email_endpoints` | list(string) | no | `[]` | Indirizzi email da sottoscrivere |
| `webhook_endpoints` | list(string) | no | `[]` | URL webhook HTTPS |
| `sqs_endpoints` | list(string) | no | `[]` | ARN di code SQS |
| `lambda_endpoints` | list(string) | no | `[]` | ARN di funzioni Lambda |
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
│ • Piano + Selezione      │     │ • Endpoint email / webhook    │
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
Endpoints are deduplicated by type.

Primary-region rules do not monitor DR automatically. Deploy another instance
with `providers = { aws = aws.dr }`, a distinct prefix, and the DR key ID when
DR-region coverage is required. Confirm SNS subscriptions and test real alert
delivery separately; mocked policy JSON is not IAM or delivery certification.

CI runs the standalone module and [independent example](./examples/) through
`make terraform-backup-check`. Native validation is pending CI during this
implementation; no AWS credentials or real apply are used by the test workflow.
