locals {
  # Single source of truth for supported service types: the wildcard ARN used
  # to select ALL resources of that type in the account/region (subject to
  # excluded_resource_arns). To support a new type, add one entry here — the
  # validation below derives the allowed set from these keys automatically.
  resource_type_arns = {
    "S3"       = "arn:aws:s3:::*"
    "DynamoDB" = "arn:aws:dynamodb:*:*:table/*"
    "EC2"      = "arn:aws:ec2:*:*:instance/*"
    "EBS"      = "arn:aws:ec2:*:*:volume/*"
    "RDS"      = "arn:aws:rds:*:*:db:*"
    "Aurora"   = "arn:aws:rds:*:*:cluster:*"
    "EFS"      = "arn:aws:elasticfilesystem:*:*:file-system/*"
  }

  supported_resource_types = keys(local.resource_type_arns)

  # Any requested type not present in the map. Surfaced by the precondition in
  # main.tf so an unsupported type fails with a clear message instead of a raw
  # "key does not exist" lookup error.
  invalid_resource_types = [
    for t in var.resource_types : t if !contains(local.supported_resource_types, t)
  ]

  # Resources derived from the requested service types, merged with any explicit
  # ARNs. lookup() keeps the expression safe when an invalid type is passed, so
  # the precondition can report it cleanly.
  type_arns = [for t in var.resource_types : lookup(local.resource_type_arns, t, "") if contains(local.supported_resource_types, t)]
  resources = distinct(concat(local.type_arns, var.resource_arns))

  # A selection needs at least one selector. If no resources/types are given,
  # fall back to tag-based selection (the default, decision §8).
  use_resource_selection = length(local.resources) > 0
}
