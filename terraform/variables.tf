# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "project" {
  description = "Project to deploy STS Agents."
  type        = string
}

variable "region" {
  description = "Region to deploy STS Agents."
  type        = string
}

variable "network" {
  description = "Google Cloud VPC network agent GCE instances will use."
  type        = string
  default     = "default"
}

variable "machine_type" {
  description = "STS Agent machine type"
  type        = string
  default     = "n2-standard-2"
}

variable "sts_instance_template_name" {
  description = <<-EOT
  Name of the Compute Engine instance template create and used to create
  compute engine instances that will run the STS agent.
  EOT
  type        = string
  default     = "sts-agent"
}

variable "hydration_gce_instance_sa" {
  description = <<-EOT
  Service account id to be created and used by the hydration GCE instance.
  EOT
  type        = string
  default     = "hydration-gce-instance-sa"
}

variable "hydration_workflow_name" {
  description = <<-EOT
  Name of the Cloud Workflow that will be created and used to perform a
  hydration.
  EOT
  type        = string
  default     = "hydrate"
}

variable "hydration-workflow-sa" {
  description = <<-EOT
  Service account id to be created and used by the hydration workflow.
  EOT
  type        = string
  default     = "hydration-workflow-sa"
}

variable "sa_secret_project_id" {
  description = <<-EOT
  Secret manager project_id where the STS agent service account private key is
  stored. Typically the same as var.project.
  EOT
  type        = string
}

variable "sts_agent_sa_secret_id" {
  description = <<-EOT
  Secret manager secret-id that contains the service account json private key
  to be used by the STS Agent.

  Grant the hydration-gce-instance-sa service account the
  roles/secretmanager.secretAccessor on the secret-id and upon instance startup
  the json private key will extracted and passed to the STS Agent.

  See: https://cloud.google.com/storage-transfer/docs/file-system-permissions#transfer_agents
  for what permissions are required on this service account.
  EOT
  type        = string
}

variable "sts_agent_sa_id" {
  description = <<-EOT
  The STS Agent service account id.
  EOT
  type        = string
}
