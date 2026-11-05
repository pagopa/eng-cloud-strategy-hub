###############################################################################
# Restore Testing Plan (opt-in)
###############################################################################

resource "aws_backup_restore_testing_plan" "this" {
  count = var.enable_restore_testing ? 1 : 0

  name                = "${replace(var.solution_prefix, "-", "_")}_restore_test"
  schedule_expression = var.restore_testing_schedule
  start_window_hours  = var.restore_testing_start_window / 60

  recovery_point_selection {
    algorithm             = "LATEST_WITHIN_WINDOW"
    include_vaults        = [aws_backup_vault.primary.arn]
    recovery_point_types  = ["CONTINUOUS", "SNAPSHOT"]
    selection_window_days = 7
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition = length(var.excluded_resource_arns) == 0 && length(var.resource_types) == 0 && (
        (length(var.selection_tags) == 1 && length(var.resource_arns) == 0) ||
        (length(var.selection_tags) == 0 && length(var.resource_arns) > 0 && length(var.resource_arns) <= 30 && alltrue([for arn in var.resource_arns : !can(regex("[*?]", arn))]))
      )
      error_message = "Restore testing supports one exact tag or up to 30 explicit ARNs. Multi-tag OR, exclusions, mixed selectors, type-wide wildcards, and implicit all-resource selection cannot be safely represented."
    }
  }
}

###############################################################################
# Restore Testing Selections
#
# A Restore Testing Plan does nothing without at least one selection. One
# selection is created per protected resource type, scoped to the same tags
# used by the backup plan, and uses the module's restore IAM role.
###############################################################################

resource "aws_backup_restore_testing_selection" "this" {
  for_each = var.enable_restore_testing ? toset(var.restore_testing_resource_types) : toset([])

  name                      = "${replace(var.solution_prefix, "-", "_")}_${lower(each.value)}"
  restore_testing_plan_name = aws_backup_restore_testing_plan.this[0].name
  protected_resource_type   = each.value
  iam_role_arn              = aws_iam_role.restore.arn

  # Hours the restored resource is retained so optional validation can run.
  validation_window_hours = var.restore_testing_max_duration

  protected_resource_arns = length(var.selection_tags) > 0 ? null : var.resource_arns

  dynamic "protected_resource_conditions" {
    for_each = length(var.selection_tags) > 0 ? [1] : []
    content {
      dynamic "string_equals" {
        for_each = var.selection_tags
        content {
          key   = "aws:ResourceTag/${string_equals.key}"
          value = string_equals.value
        }
      }
    }
  }
}
