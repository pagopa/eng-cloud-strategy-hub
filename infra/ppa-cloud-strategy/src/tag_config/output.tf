output "tags" {
  value       = local.tags_with_optional
  description = "Tags to be applied to resources"
}

output "tags_grafana_yes" {
  value       = merge(local.tags_with_optional, { "grafana" = "yes" })
  description = "Tags with 'grafana'='yes' to be applied to resources"
}
