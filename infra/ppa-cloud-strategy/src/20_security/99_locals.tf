locals {
  project_nodomain = "${var.prefix}-${var.env_short}-${var.location_short}"

  secret_scopes = ["core"]
}
