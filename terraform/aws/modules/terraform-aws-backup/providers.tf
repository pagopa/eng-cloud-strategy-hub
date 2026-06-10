###############################################################################
# Provider Configuration
#
# The module requires two provider configurations:
#   - aws        (default) — primary region where the workload lives
#   - aws.dr     — DR region for cross-region copy
#
# The consuming team must pass both providers when calling the module.
# If cross-region copy is disabled, the DR provider is unused but must
# still be declared (Terraform requirement for provider-aliased resources).
#
# The provider requirements (including the aws.dr configuration alias) are
# declared in versions.tf to keep a single required_providers block.
###############################################################################
