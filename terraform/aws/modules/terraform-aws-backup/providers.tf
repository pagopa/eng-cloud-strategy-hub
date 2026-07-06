###############################################################################
# Provider Configuration
#
# The consuming team passes only the default aws provider (primary region).
# This module configures the internal aws.dr alias from inputs so callers do
# not need to declare a second provider block just to satisfy the DR path.
#
# When cross-region copy is disabled, aws.dr intentionally falls back to the
# primary region and stays unused because all DR resources have count = 0.
###############################################################################
provider "aws" {
  region = local.enable_cross_region_copy ? var.dr_region : var.aws_region
  alias  = "dr"
}