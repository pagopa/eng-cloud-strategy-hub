# Terraform Operator Tooling

This context names the repository-owned language for provider wrappers, execution context, and offline validation of Terraform operations.

## Language

**Terraform wrapper**:
A provider-specific command surface that coordinates Terraform with provider context and repository conventions.
_Avoid_: Terraform module, pipeline

**Environment argument**:
The wrapper input that selects a provider-specific environment or project configuration.
_Avoid_: Workspace, account

**Noenv**:
The literal wrapper argument that suppresses environment-specific backend and cloud-auth resolution.
_Avoid_: Local mode, default environment

**State creator**:
The operator bootstrap path that prepares the AWS S3 state-bucket resources used by Terraform.
_Avoid_: Terraform wrapper, deployment

**Offline simulation**:
A wrapper or state-creator check that uses fake CLIs and synthetic fixtures instead of live cloud state.
_Avoid_: Live validation, deployment test
