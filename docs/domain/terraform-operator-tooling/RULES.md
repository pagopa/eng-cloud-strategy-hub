# Terraform Operator Tooling Rules

## TERRAFORM-001 Wrapper environment selection

- Rule ID: TERRAFORM-001
- Owner: Terraform Operator Tooling
- Severity: high
- Enforcement owner: `scripts/azure/terraform.sh` and provider-specific wrappers
- Evidence: `scripts/azure/terraform.sh`, `scripts/aws/terraform.sh`, `tests/scripts/terraform_wrappers/`
- Remediation: Supply the required environment or project argument, or use the literal `noenv` mode when environment resolution is intentionally skipped.
- Rule: Terraform wrapper invocations must provide the required environment or project context; `noenv` is the explicit path for skipping environment-specific backend and cloud-auth resolution.

## TERRAFORM-002 Destructive-action guard

- Rule ID: TERRAFORM-002
- Owner: Terraform Operator Tooling
- Severity: blocking
- Enforcement owner: `scripts/azure/terraform.sh` and `scripts/aws/aws-terraform-s3-state-creator.sh`
- Evidence: `scripts/azure/terraform.sh`, `scripts/aws/aws-terraform-s3-state-creator.sh`, `tests/scripts/terraform_wrappers/`
- Remediation: Use the wrapper's dry-run, doctor, or confirmation path and supply explicit execution flags only after reviewing the target.
- Rule: Operator tooling must keep destructive or live cloud actions behind the repository's explicit dry-run, confirmation, or execution flag controls.
