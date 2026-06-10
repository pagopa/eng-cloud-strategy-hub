# Esempi — terraform-aws-backup

Esempi d'uso eseguibili. Ciascuno è una configurazione root che consuma il modulo tramite tag semver (`?ref=vX.Y.Z`) dal repository pubblicato.

| Esempio | Scenario | Decisioni illustrate |
|---------|----------|----------------------|
| [`production/`](./production/) | Account di produzione: Vault Lock COMPLIANCE, copia cross-region verso Francoforte, restore testing, preset long-retention, alerting via email | §4 §5 §6 §7 §10 §11 |
| [`non-production/`](./non-production/) | Account dev/UAT: Vault Lock GOVERNANCE, nessuna copia cross-region, alerting opzionale | §4 §7 §11 |
| [`with-extra-plans/`](./with-extra-plans/) | Piano di default esteso con preset (long-retention, hourly) e un piano su misura due volte al giorno | §5 |
| [`continuous-pitr/`](./continuous-pitr/) | Backup continuo (PITR) limitato ai servizi supportati tramite tag dedicato, per evitare job FAILED su EFS/EKS/Redshift | §1 §5 |
| [`by-service-type/`](./by-service-type/) | Selezione delle risorse per tipo di servizio (ARN wildcard) invece dei tag, con esclusione delle risorse effimere | §1 §5 §8 |
| [`nonprod-compliance-optin/`](./nonprod-compliance-optin/) | Account pre-prod che attiva il Vault Lock COMPLIANCE | §7 |

## Eseguire un esempio

```bash
cd examples/<nome>
terraform init
terraform plan
```

> Gli esempi referenziano `git::https://github.com/pagopa/<nome-repo>.git//...`.
> Sostituisci `<nome-repo>` (e il `ref`) con la posizione del modulo pubblicato,
> oppure punta `source` a un percorso locale per i test.
