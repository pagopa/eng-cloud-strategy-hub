###############################################################################
# Backup Plan
###############################################################################

resource "aws_backup_plan" "this" {
  name = var.plan_name

  dynamic "rule" {
    for_each = var.rules
    content {
      rule_name                = rule.value.rule_name
      target_vault_name        = rule.value.target_vault_name
      schedule                 = rule.value.schedule
      start_window             = rule.value.start_window
      completion_window        = rule.value.completion_window
      enable_continuous_backup = rule.value.enable_continuous_backup
      recovery_point_tags      = rule.value.recovery_point_tags

      lifecycle {
        cold_storage_after = rule.value.cold_storage_after > 0 ? rule.value.cold_storage_after : null
        delete_after       = rule.value.delete_after
      }

      dynamic "copy_action" {
        for_each = rule.value.copy_actions
        content {
          destination_vault_arn = copy_action.value.destination_vault_arn

          lifecycle {
            cold_storage_after = copy_action.value.cold_storage_after > 0 ? copy_action.value.cold_storage_after : null
            delete_after       = copy_action.value.delete_after
          }
        }
      }
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(distinct([for rule in var.rules : rule.rule_name])) == length(var.rules)
      error_message = "Backup rule names must be unique."
    }
    precondition {
      condition = alltrue([
        for rule in var.rules : rule.delete_after >= 1 && floor(rule.delete_after) == rule.delete_after &&
        rule.cold_storage_after >= 0 && floor(rule.cold_storage_after) == rule.cold_storage_after &&
        (rule.cold_storage_after == 0 || rule.delete_after >= rule.cold_storage_after + 90)
      ])
      error_message = "Rules require positive whole-day retention and at least 90 days in cold storage when transition is enabled."
    }
    precondition {
      condition = alltrue([
        for rule in var.rules : !rule.enable_continuous_backup || (rule.delete_after <= 35 && rule.cold_storage_after == 0)
      ])
      error_message = "Continuous backup retention cannot exceed 35 days and cannot transition to cold storage."
    }
    precondition {
      condition = alltrue(flatten([
        for rule in var.rules : [
          for copy in rule.copy_actions : copy.delete_after >= 1 && floor(copy.delete_after) == copy.delete_after &&
          copy.cold_storage_after >= 0 && floor(copy.cold_storage_after) == copy.cold_storage_after &&
          (copy.cold_storage_after == 0 || copy.delete_after >= copy.cold_storage_after + 90)
        ]
      ]))
      error_message = "Copies require positive whole-day retention and at least 90 days after a cold-storage transition."
    }
  }
}

###############################################################################
# Resource Selection
#
# Resources are selected by tags (default, decision §8) and/or by explicit
# resource types / ARNs. When both are provided, AWS Backup treats them as a
# union (a resource matching either is included). excluded_resource_arns maps
# to not_resources, useful to drop ephemeral resources from a type-wide select.
###############################################################################

resource "aws_backup_selection" "this" {
  name         = coalesce(var.selection_name, "${var.plan_name}-selection")
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = var.iam_role_arn

  resources     = local.resources
  not_resources = var.excluded_resource_arns

  dynamic "selection_tag" {
    for_each = var.selection_tags
    content {
      type  = "STRINGEQUALS"
      key   = selection_tag.key
      value = selection_tag.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.invalid_resource_types) == 0
      error_message = "Unsupported resource_types: ${join(", ", local.invalid_resource_types)}. Supported types are: ${join(", ", local.supported_resource_types)}."
    }

    precondition {
      condition     = length(var.selection_tags) > 0 || local.use_resource_selection
      error_message = "Provide at least one selector: selection_tags, resource_types, or resource_arns."
    }
  }
}
