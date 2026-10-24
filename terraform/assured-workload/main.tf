# -----------------------------------------------------------------------------
# FedRAMP High Assured Workloads folder + Vertex AI project + guardrails
# Author: Kenneth P. Barnes - github.com/kennyb7322/vertex-ai-fedramp-command-center
#
# Creates:
#   - Assured Workloads workload (Data Boundary for FedRAMP High) -> consumer folder
#   - Project inside the folder, linked to billing, with Vertex AI enabled
#   - Folder org policies: model allow-list, Google Search grounding off,
#     service account key creation off
# Assured Workloads itself applies the FedRAMP High data-residency and
# service-usage restrictions to the folder. Review the plan with the client's
# cloud governance team before apply; FedRAMP High is a Premium package.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

provider "google" {
  billing_project       = var.admin_project_id
  user_project_override = true
}

resource "google_assured_workloads_workload" "fedramp_high" {
  organization                 = var.org_id
  location                     = "us"
  display_name                 = var.workload_name
  compliance_regime            = "FEDRAMP_HIGH"
  billing_account              = "billingAccounts/${var.billing_account_id}"
  provisioned_resources_parent = var.parent_folder != "" ? "folders/${var.parent_folder}" : null

  resource_settings {
    resource_type = "CONSUMER_FOLDER"
    display_name  = var.workload_name
  }

  labels = var.labels
}

locals {
  folder_id = one([
    for r in google_assured_workloads_workload.fedramp_high.resources :
    r.resource_id if r.resource_type == "CONSUMER_FOLDER"
  ])
}

resource "google_project" "vertex" {
  name            = var.project_id
  project_id      = var.project_id
  folder_id       = local.folder_id
  billing_account = var.billing_account_id
  labels          = var.labels
  deletion_policy = "PREVENT"
}

resource "google_project_service" "apis" {
  for_each           = toset(["aiplatform.googleapis.com", "iam.googleapis.com", "sts.googleapis.com", "iamcredentials.googleapis.com", "cloudkms.googleapis.com", "logging.googleapis.com"])
  project            = google_project.vertex.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_org_policy_policy" "allowed_models" {
  name   = "folders/${local.folder_id}/policies/vertexai.allowedModels"
  parent = "folders/${local.folder_id}"
  spec {
    rules {
      values {
        allowed_values = [for m in var.allowed_models : "publishers/google/models/${m}:predict"]
      }
    }
  }
}

resource "google_org_policy_policy" "boolean_guardrails" {
  for_each = toset(["vertexai.disableGenAIGoogleSearchGrounding", "iam.disableServiceAccountKeyCreation"])
  name     = "folders/${local.folder_id}/policies/${each.value}"
  parent   = "folders/${local.folder_id}"
  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

output "assured_workloads_folder_id" {
  value = local.folder_id
}

output "project_number" {
  value = google_project.vertex.number
}
