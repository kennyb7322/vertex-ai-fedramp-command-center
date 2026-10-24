variable "org_id" {
  description = "Numeric organization id"
  type        = string
}

variable "billing_account_id" {
  description = "Billing account id (XXXXXX-XXXXXX-XXXXXX) used for the Assured Workloads folder and project"
  type        = string
}

variable "admin_project_id" {
  description = "Existing project used for quota and billing of the Assured Workloads API calls"
  type        = string
}

variable "parent_folder" {
  description = "Optional folder id that will contain the Assured Workloads folder (empty = organization root)"
  type        = string
  default     = ""
}

variable "workload_name" {
  description = "Display name of the Assured Workloads workload and folder"
  type        = string
  default     = "vertex-ai-fedramp-high"
}

variable "project_id" {
  description = "Project id for the Vertex AI workload"
  type        = string
}

variable "allowed_models" {
  description = "Gemini model ids allowed by the vertexai.allowedModels org policy; confirm availability in the boundary"
  type        = list(string)
  default     = ["gemini-2.5-pro", "gemini-2.5-flash"]
}

variable "labels" {
  description = "Labels applied to the workload and project"
  type        = map(string)
  default = {
    compliance = "fedramp-high"
    workload   = "vertex-ai"
  }
}
