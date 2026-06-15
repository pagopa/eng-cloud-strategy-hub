# terraform-aws-backup

Modulo Terraform per la strategia di backup AWS di PagoPA. Crea, per ogni account, l'infrastruttura di backup di base: vault, Vault Lock, piano di backup, ruoli IAM, cifratura KMS e restore testing opzionale.

**L'alerting è gestito da un modulo separato** — [`terraform-aws-backup-alerting`](../terraform-aws-backup-alerting/) — che ha un ciclo di vita indipendente e può essere modificato (cambio destinatari, aggiunta di sottoscrittori) senza toccare l'infrastruttura di backup.

## Indice

- [Come funziona](#come-funziona)
- [Utilizzo rapido](#utilizzo-rapido)
- [Requisiti](#requisiti)
- [Provider](#provider)
- [Architettura](#architettura)
- [Come selezionare le risorse da proteggere](#come-selezionare-le-risorse-da-proteggere)
- [Default per ambiente](#default-per-ambiente)
- [Estendere i backup: preset e piani su misura](#estendere-i-backup-preset-e-piani-su-misura)
- [Struttura del modulo](#struttura-del-modulo)
- [Risorse create](#risorse-create)
- [Input](#input)
- [Output](#output)
- [Note operative](#note-operative)
- [Validazione](#validazione)

## Come funziona

Ogni team usa questo modulo nel **proprio account** per proteggere i workload con AWS Backup. Il modulo crea un vault cifrato con chiave customer-managed (CMK), lo rende immutabile tramite Vault Lock, e gli associa un piano di backup giornaliero che seleziona le risorse da proteggere (per impostazione predefinita, in base ai tag). Il comportamento di default si adatta all'ambiente (`prod` / `nonprod`).

## Utilizzo rapido

L'integrazione minima richiede: i due provider (regione primaria e DR), l'ambiente, un prefisso e il criterio di selezione delle risorse.

```hcl
# I due provider richiesti dal modulo
provider "aws" {
  region = "eu-south-1" # regione primaria del workload
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1" # regione di disaster recovery
}

module "backup" {
  source = "git::https://github.com/pagopa/<nome-repo>.git//modules/backup?ref=v1.0.0"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  environment     = "prod"
  solution_prefix = "team-payments-vault"

  # Seleziona le risorse da proteggere in base al tag (metodo predefinito)
  selection_tags = {
    "backup-policy" = "enabled"
  }

  tags = {
    "backup-owner" = "team-payments"
  }
}

# Alerting (modulo separato, ciclo di vita indipendente)
module "backup_alerting" {
  source = "git::https://github.com/pagopa/<nome-repo>.git//modules/backup-alerting?ref=v1.0.0"

  solution_prefix = "team-payments"
  kms_key_ids     = [module.backup.kms_key_id]
  email_endpoints = ["team-payments-oncall@pagopa.it"]
}
```

Con questa configurazione, ogni risorsa di un tipo supportato che porta il tag `backup-policy = enabled` viene inclusa automaticamente nel piano di backup giornaliero.

Nella cartella [`examples/`](./examples/) trovi configurazioni complete ed eseguibili per i vari scenari (produzione, non-produzione, piani aggiuntivi, PITR, opt-in compliance).

## Requisiti

| Nome | Versione |
|------|----------|
| terraform | >= 1.5.0 |
| aws | >= 5.30.0, < 6.0.0 |

## Provider

Il modulo richiede **due configurazioni di provider**:

- `aws` — regione primaria dove vive il workload.
- `aws.dr` — regione di DR per la copia cross-region. **Va dichiarata anche se la copia cross-region è disattivata** (è un requisito di Terraform per i provider con alias).

```hcl
provider "aws" {
  region = "eu-south-1"
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}
```

> La regione di DR effettiva è determinata dal provider `aws.dr`. Quando abiliti la copia cross-region devi anche valorizzare la variabile `dr_region` con la stessa regione: serve alla validazione contro l'allow-list delle regioni UE.

## Architettura

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Account del workload                                                        │
│                                                                             │
│  terraform-aws-backup (core)          terraform-aws-backup-alerting         │
│  ┌────────────────────────────┐       ┌────────────────────────────────┐   │
│  │ Piano backup ──► Vault     │       │ EventBridge ──► SNS ──► Email   │   │
│  │              (Vault Lock)  │       │            (failures)   Webhook │   │
│  │ KMS CMK (primaria)        │       │                                 │   │
│  │ Ruoli IAM (backup+restore)│       │ Alert cancellazione chiave KMS  │   │
│  │ Restore Testing Plan      │       └────────────────────────────────┘   │
│  │              │             │                                             │
│  │              │ copia cross-region                                        │
│  │              ▼             │                                             │
│  │ Vault DR + KMS CMK (DR)   │                                             │
│  └────────────────────────────┘                                             │
└───────────────────────────────────────────────────────────────────────────┘
```

## Come selezionare le risorse da proteggere

Puoi assegnare le risorse al piano di backup in tre modi. **Ne basta uno.** Quando ne usi più di uno, AWS Backup li combina in **unione** (una risorsa è inclusa se soddisfa almeno un criterio).

| Input | Seleziona per | Note |
|-------|---------------|------|
| `selection_tags` | Tag della risorsa | **Metodo predefinito** (in linea con la strategia di tagging concordata) |
| `resource_types` | Tutte le risorse di un tipo di servizio | ARN wildcard, es. `["DynamoDB","S3"]` |
| `resource_arns` | ARN espliciti o wildcard | Selezione puntuale |
| `excluded_resource_arns` | Esclusioni (`not_resources`) | Per escludere risorse effimere |

**Selezione per tag (consigliata).** È sufficiente taggare le risorse: il team non deve modificare il Terraform. AWS Backup include qualsiasi risorsa di un tipo supportato da AWS Backup che porta i tag indicati — questo vale anche per servizi non presenti nella lista `resource_types` qui sotto (es. un Redshift correttamente taggato viene comunque protetto).

```hcl
selection_tags = {
  "backup-policy" = "enabled"
}
```

**Selezione per tipo di servizio.** Utile per proteggere *tutte* le risorse di un servizio nell'account/regione, a prescindere dai tag. Questo metodo costruisce gli ARN wildcard, quindi è limitato ai tipi di cui il modulo conosce il pattern ARN.

```hcl
resource_types         = ["DynamoDB", "S3", "RDS"]
excluded_resource_arns = ["arn:aws:dynamodb:eu-south-1:123456789012:table/tabella-effimera"]
```

Tipi supportati da `resource_types`: **S3, DynamoDB, EC2, EBS, RDS, Aurora, EFS**. AWS Backup ammette al massimo 30 ARN wildcard per selezione. Vedi `examples/by-service-type/`.

> Se passi a `resource_types` un tipo non gestito, il `plan` fallisce con un messaggio esplicito che elenca i tipi supportati (nessun fallimento silenzioso). Per aggiungere un nuovo tipo basta una riga nella mappa `resource_type_arns` del sotto-modulo `backup-plan` (vedi sezione successiva).

## Default per ambiente

La variabile `environment` (`prod` o `nonprod`) guida i valori di default. Ogni valore è comunque sovrascrivibile.

| Impostazione | `prod` | `nonprod` |
|--------------|--------|-----------|
| Backup attivo | sì | opt-in |
| Vault Lock | COMPLIANCE | GOVERNANCE |
| Copia cross-region | abilitata | disabilitata |
| Retention | 35 giorni | 14 giorni |
| Cold storage | opt-in | opt-in |
| Backup continuo (PITR) | abilitato | disabilitato |
| Retention minima del Lock | 35 giorni | 7 giorni |

## Estendere i backup: preset e piani su misura

Oltre al piano giornaliero di default puoi aggiungere altri piani. I **preset** sono wrapper pronti all'uso sopra il sotto-modulo `backup-plan`: si invocano come moduli aggiuntivi accanto al core.

Se la **stessa selezione di risorse** del piano di default ha bisogno di una o più schedule aggiuntive, senza creare un piano separato, usa `default_plan_additional_rules` direttamente sul modulo core. Se invece cambiano la selezione delle risorse o il piano deve avere un ciclo di vita indipendente, continua a usare un preset o il sotto-modulo `backup-plan`.

| Preset | Percorso | Caso d'uso |
|--------|----------|------------|
| Hourly Backup | `modules/presets/hourly-backup/` | Workload a basso RPO (≤ 1h) |
| Long Retention | `modules/presets/long-retention/` | Conservazione normativa a 10 anni |
| Archival | `modules/presets/archival/` | Archiviazione a basso costo (cold storage) |
| Weekly Full | `modules/presets/weekly-full/` | Full settimanale garantito |

Esempio: aggiungere un piano orario per le risorse critiche.

```hcl
module "hourly" {
  source = "git::https://github.com/pagopa/<nome-repo>.git//modules/backup/modules/presets/hourly-backup?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-tier" = "critical"
  }

  retention_days = 7
}
```

Per pianificazioni completamente personalizzate, invoca direttamente il sotto-modulo `modules/backup-plan/` (vedi `examples/with-extra-plans/`).

## Struttura del modulo

```
terraform-aws-backup/
├── *.tf                         ← core: vault, Vault Lock, KMS, IAM, piano di default, restore testing
├── modules/
│   ├── backup-plan/             ← "mattoncino" riusabile: piano + selezione risorse
│   └── presets/                 ← wrapper con default opinati sopra backup-plan
│       ├── hourly-backup/
│       ├── long-retention/
│       ├── archival/
│       └── weekly-full/
└── examples/
    ├── production/                 ← prod: Vault Lock COMPLIANCE, copia cross-region, restore testing
    ├── non-production/             ← nonprod: Vault Lock GOVERNANCE, nessuna copia
    ├── with-extra-plans/           ← preset + un piano su misura
    ├── continuous-pitr/            ← PITR limitato ai servizi supportati tramite tag dedicato
    ├── by-service-type/            ← selezione per tipo di servizio (ARN wildcard) invece dei tag
    └── nonprod-compliance-optin/   ← pre-prod che attiva il Vault Lock COMPLIANCE
```

La logica del piano vive in **un solo posto** (`backup-plan`): sia il piano di default sia i preset lo riusano.

## Risorse create

| Risorsa | Quantità | Scopo |
|---------|----------|-------|
| `aws_backup_vault` | 1 (+1 DR) | Archiviazione dei recovery point |
| `aws_backup_vault_lock_configuration` | 1 (+1 DR) | Immutabilità |
| `aws_backup_plan` | 1 | Pianificazione di default (via sotto-modulo `backup-plan`) |
| `aws_backup_selection` | 1 | Selezione risorse per tag (via sotto-modulo `backup-plan`) |
| `aws_iam_role` | 2 | Ruoli di servizio backup + restore |
| `aws_kms_key` | 1 (+1 DR) | Cifratura del vault |
| `aws_backup_restore_testing_plan` | 0-1 | Validazione del restore (opt-in) |
| `aws_backup_restore_testing_selection` | 0-N | Una per tipo di risorsa quando il restore testing è attivo |

## Input

L'elenco completo di variabili, con descrizioni e default, è in [variables.tf](./variables.tf). Le principali:

| Variabile | Tipo | Obbligatoria | Default | Descrizione |
|-----------|------|--------------|---------|-------------|
| `environment` | string | sì | — | `prod` o `nonprod`. Guida i default di Vault Lock, copia, retention. |
| `solution_prefix` | string | no | `backup-solution` | Prefisso per le risorse (vault, ruoli IAM, alias KMS, piani). |
| `selection_tags` | map(string) | no¹ | `{}` | Tag per selezionare le risorse (metodo predefinito). |
| `resource_types` | list(string) | no¹ | `[]` | Tipi di servizio da proteggere interamente. |
| `resource_arns` | list(string) | no¹ | `[]` | ARN espliciti/wildcard da includere. |
| `retention_days` | number | no | 35 prod / 14 nonprod | Giorni di conservazione dei recovery point. |
| `default_plan_additional_rules` | list(object) | no | `[]` | Regole schedulate aggiuntive sul piano di default, riusando selezione, vault e ruolo IAM del core. |
| `cross_region_copy` | string | no | `Default` | `Default` / `DoNotCopyToOtherRegions` / `CopyToSecondaryRegion`. |
| `dr_region` | string | no² | `null` | Regione DR (deve combaciare col provider `aws.dr`). |
| `vault_lock_mode` | string | no | COMPLIANCE prod / GOVERNANCE nonprod | Modalità del Vault Lock. |
| `enable_continuous_backup` | bool | no | true prod / false nonprod | Abilita PITR sui servizi supportati. |
| `enable_restore_testing` | bool | no | `false` | Crea il Restore Testing Plan. |
| `tags` | map(string) | no | `{}` | Tag aggiuntivi su tutte le risorse. |

¹ Va fornito almeno uno tra `selection_tags`, `resource_types`, `resource_arns`.
² Obbligatoria quando la copia cross-region risulta attiva.

## Output

| Nome | Descrizione |
|------|-------------|
| `vault_arn` | ARN del vault di backup primario |
| `vault_name` | Nome del vault di backup primario |
| `dr_vault_arn` | ARN del vault DR (null se disabilitato) |
| `backup_plan_id` | ID del piano di backup di default |
| `backup_plan_arn` | ARN del piano di backup di default |
| `continuous_plan_id` | ID del piano dedicato di backup continuo (null se `continuous_backup_selection_tags` non è impostato) |
| `backup_role_arn` | ARN del ruolo IAM di backup |
| `restore_role_arn` | ARN del ruolo IAM di restore |
| `kms_key_arn` | ARN della CMK del vault primario |
| `kms_key_id` | ID della CMK del vault primario |
| `dr_kms_key_arn` | ARN della CMK del vault DR (null se disabilitato) |
| `dr_kms_key_id` | ID della CMK del vault DR (null se disabilitato) |
| `restore_testing_plan_arn` | ARN del Restore Testing Plan (null se disabilitato) |

## Note operative

- **Vincolo del Vault Lock sulla retention.** Qualsiasi job che scrive nel vault (incluso un eventuale backup on-demand o un piano esterno) deve avere una `delete_after` compresa tra `vault_lock_min_retention_days` e `vault_lock_max_retention_days`. Un job fuori da questo intervallo viene rifiutato dal vault. I piani creati dal modulo rispettano sempre questo vincolo.
- **Cold storage.** Quando si imposta `cold_storage_after`, AWS Backup richiede `retention_days >= cold_storage_after + 90`. Il modulo verifica questa condizione a tempo di plan.
- **Vault Lock COMPLIANCE è irreversibile** in produzione dopo il periodo di cooling-off (`vault_lock_changeable_for_days`). Da confermare a livello di processo prima del rollout in prod.
- **Cancellazione delle CMK protetta.** Le chiavi KMS dei vault hanno `prevent_destroy = true`: un `terraform destroy` si fermerà su di esse finché il lifecycle non viene rimosso esplicitamente. È una protezione voluta contro la perdita di accesso ai backup cifrati.

## Validazione

- `terraform fmt` / `terraform validate`. Il modulo dichiara un alias di provider `aws.dr`, quindi `terraform validate` va eseguito da un chiamante che fornisce sia `aws` sia `aws.dr` (vedi una qualsiasi configurazione in `examples/`).
