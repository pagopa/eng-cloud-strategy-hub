# Context Map

The hub contains three knowledge domains with distinct audiences, vocabularies, and execution boundaries.

## Contexts

- [Copilot customization](./docs/domain/copilot-customization/CONTEXT.md) - repository-owned instructions, customization assets, and governance terminology.
- [Reusable automation](./docs/domain/reusable-automation/CONTEXT.md) - composite actions, caller workflows, and release automation terminology.
- [Terraform operator tooling](./docs/domain/terraform-operator-tooling/CONTEXT.md) - provider wrappers, execution context, and offline simulation terminology.

## Relationships

- **Reusable automation -> Copilot customization**: the code-analysis
	workflow and local simulator exercise the Copilot bootstrap and validation
	entrypoints.
- **Reusable automation -> Terraform operator tooling**: the Terraform test
	workflow and local simulator invoke offline simulations for the provider
	wrappers and AWS state creator.
- **Copilot customization / Terraform operator tooling**: no direct
	domain-level relationship is evidenced. Both follow repository-wide policy,
	while their component relationships are recorded in
	[docs/architecture.md](./docs/architecture.md).

The component and external-system relationships are maintained in [docs/architecture.md](./docs/architecture.md); this map records only relationships between knowledge domains.
