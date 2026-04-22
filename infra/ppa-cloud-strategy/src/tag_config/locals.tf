locals {
  cwd_split       = split("/", path.cwd)
  src_idx         = index(local.cwd_split, "src")
  relative_folder = join("/", slice(local.cwd_split, local.src_idx + 1, length(local.cwd_split)))
  optional_tags = {
    Prefix        = var.prefix
    EnvironmentId = var.env_short
    Location      = var.location
    LocationShort = var.location_short
  }
  tags = {
    CreatedBy   = "Terraform"
    Environment = title(var.environment)
    Owner       = "Cloud Strategy Team"
    Source      = "https://github.com/pagopa/eng-cloud-strategy-hub/tree/main/src/${local.relative_folder}"
    # isolates the module working folder, removing the absolute path leading to the cwd and the leading slash
    Folder     = local.relative_folder
    CostCenter = "Technology"
    Domain     = var.domain
  }
  tags_with_optional = merge(local.tags, { for key, value in local.optional_tags : key => value if value != null })
}
