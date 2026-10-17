# This root is deliberately separate from the application stack so the
# account-level budget can remain after the app resources are destroyed.
# The budget covers the whole AWS account, not just this project.
resource "aws_budgets_budget" "monthly_account_cost" {
  count = trimspace(var.budget_alert_email) == "" ? 0 : 1

  name         = "portfolio-monthly-account-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Exclude credits so notifications reflect underlying cost rather than
  # being hidden by promotional-credit offsets.
  cost_types {
    include_credit = false
  }

  dynamic "notification" {
    for_each = toset([50, 80, 100])

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [trimspace(var.budget_alert_email)]
    }
  }
}

output "monthly_budget_enabled" {
  description = "Whether the account-wide budget and email notifications are enabled."
  value       = trimspace(var.budget_alert_email) != ""
}

output "monthly_budget_limit_usd" {
  description = "Configured account-wide monthly cost threshold in USD."
  value       = var.monthly_budget_limit_usd
}
