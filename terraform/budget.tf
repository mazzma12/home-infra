# A tripwire for the day this tenancy stops being free — most likely an upgrade to
# Pay As You Go, which is Oracle's own answer to the chronic A1.Flex capacity problem
# but drops the "cannot be charged" guarantee Always Free gives.
#
# Two things this is NOT: spend is recomputed periodically, so an alert lags real usage
# by up to about a day, and a budget only notifies — it never caps or stops spending.

resource "oci_budget_budget" "free_tier" {
  # Budgets are only permitted in the root compartment, and var.compartment_id is
  # already the tenancy OCID.
  compartment_id = var.compartment_id
  amount         = var.budget_amount
  reset_period   = "MONTHLY"

  # Target the tenancy root so this covers all spend, not one child compartment.
  target_type = "COMPARTMENT"
  targets     = [var.compartment_id]

  display_name = "free-tier-tripwire"
  description  = "Alerts if the Always Free tenancy ever starts costing money."
}

resource "oci_budget_alert_rule" "at_budget" {
  budget_id = oci_budget_budget.free_tier.id

  # PERCENTAGE/100 rather than ABSOLUTE/1 so the rule still means "budget fully spent"
  # if budget_amount is ever raised. ACTUAL rather than FORECAST, since forecasting
  # against a budget this small is noise.
  threshold      = 100
  threshold_type = "PERCENTAGE"
  type           = "ACTUAL"

  display_name = "free-tier-tripwire-actual"
  recipients   = var.budget_alert_recipient
  message      = "OCI actual spend has reached the monthly budget of ${var.budget_amount} USD. The tenancy is no longer free."
}
