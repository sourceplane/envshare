terraform {
  required_version = ">= 1.15.0"

  # State lives on the platform (SB1): the runner exports TF_HTTP_* per job, so
  # this block stays empty — no S3 bucket, no AWS role, no workspaces.
  backend "http" {}

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.30"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

# --- Providers ---

# Authenticates via the CLOUDFLARE_API_TOKEN env var (provider-native): the
# token is an orun-managed secret resolved into the job env at run time, so it
# never transits Terraform variables.
provider "cloudflare" {}

# --- Variables (standard Orun parameters) ---

variable "cloudflare_account_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Cloudflare account ID (from CLOUDFLARE_ACCOUNT_ID env var)"
}

variable "orgName" {
  type    = string
  default = "sourceplane"
}

variable "owner" {
  type    = string
  default = "sourceplane"
}

variable "repo" {
  type    = string
  default = "envshare"
}

variable "namespace" {
  type    = string
  default = "sourceplane"
}

variable "namespacePrefix" {
  type    = string
  default = ""
}

variable "lane" {
  type    = string
  default = "verify"
}

variable "environment" {
  type    = string
  default = "stage"
}

variable "component" {
  type    = string
  default = "cloudflare-d1"
}

variable "stackName" {
  type    = string
  default = "cloudflare-d1"
}

variable "terraformDir" {
  type    = string
  default = "terraform"
}

variable "terraformVersion" {
  type    = string
  default = "1.15.3"
}

# --- The site's database ---
#
# One D1 database per deployed environment (stage, prod), bound by apps/web as
# DB. Its schema is not Terraform's: packages/db's migrations create the
# site's tables, applied by the db-migrate component after this apply and
# before the Worker deploys.

locals {
  # Built on var.repo (the product's repository slug) so the name is unique per
  # product. D1 database names are unique per account, and two products may
  # share an account. The Worker binds this database by ID through the wiring
  # secret, so the name is free to change.
  database_name = "${var.namespacePrefix}${var.repo}-${var.environment}"
}

resource "cloudflare_d1_database" "platform" {
  account_id = var.cloudflare_account_id
  name       = local.database_name
}

# --- Wiring manifest (BF5, via orun secrets) ---
#
# The consumable outputs are published by the composition's wire-secrets step
# as the WIRING_CLOUDFLARE_D1 secret on the project/{{env}} rung; worker
# deploys read it back as WIRING_CLOUDFLARE_D1_<ENV> secretEnv and render the
# committed @@wiring(...)@@ tokens from it (BF6). The `db-migrate` component
# reads the same document (WIRING_CLOUDFLARE_D1) to find the database it
# migrates.

output "wiring" {
  description = "Wiring document for downstream deploy-time binding resolution (pushed to orun secrets)"
  value = jsonencode({
    d1_database_id   = cloudflare_d1_database.platform.id
    d1_database_name = cloudflare_d1_database.platform.name
  })
}

# --- Outputs (non-secret) ---

output "d1_database_id" {
  description = "Cloudflare D1 database ID (the Workers binding's database_id)"
  value       = cloudflare_d1_database.platform.id
}

output "d1_database_name" {
  description = "Cloudflare D1 database name (human-readable identifier)"
  value       = cloudflare_d1_database.platform.name
}
