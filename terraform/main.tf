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

provider "google" {
  project = var.project
  region  = var.region
}
data "google_compute_image" "cos_image" {
  family  = "cos-stable"
  project = "cos-cloud"
}
locals {
  PD_DEVICE_NAME      = "hydrate-pd"
  sts_agent_sa_member = "serviceAccount:${var.sts_agent_sa_id}@${var.sa_secret_project_id}.iam.gserviceaccount.com"

  template_map = {
    PROJECT_ID     = var.project
    SECRET_PROJECT = var.sa_secret_project_id
    SECRET_ID      = var.sts_agent_sa_secret_id

    # Constants used in cloud-init and workflow control plane
    PD_DISK_NAME = local.PD_DEVICE_NAME
    MOUNT_PATH   = "/mnt/disks/${local.PD_DEVICE_NAME}"
  }
  cloud_config = templatefile("${path.module}/templates/cloud-config.yaml", local.template_map)
}

data "google_project" "project" {}

resource "google_project_service" "services" {
  project = var.project
  for_each = toset([
    "compute.googleapis.com",
    "storage-api.googleapis.com",
    "storagetransfer.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# Create transferservice.googleapis.com service agent SA
resource "google_project_service_identity" "storagetransfer" {
  provider = google-beta

  project = var.project
  service = "storagetransfer.googleapis.com"

  depends_on = [
    google_project_service.services["storagetransfer.googleapis.com"],
    google_project_service.services["cloudresourcemanager.googleapis.com"],
  ]
}

# Obtain the transferservice service agent SA resource
# since the google_project_service_identity resource isn't populating the
# email attribute
data "google_storage_transfer_project_service_account" "default" {
  project = var.project

  depends_on = [
    google_project_service.services["storagetransfer.googleapis.com"]
  ]
}
resource "google_project_iam_member" "storagetransfer_grant" {
  project = var.project
  role    = "roles/storagetransfer.serviceAgent"
  member  = data.google_storage_transfer_project_service_account.default.member
}

resource "google_project_iam_member" "transfer_agent_grant" {
  project = var.project
  role    = "roles/storagetransfer.transferAgent"
  member  = local.sts_agent_sa_member

  depends_on = [google_project_service.services["iam.googleapis.com"]]
}

# Compute engine SA
# Grants on this SA are done outside of the deployment.
resource "google_service_account" "hydration_gce_instance_sa" {
  project      = var.project
  account_id   = var.hydration_gce_instance_sa
  display_name = "Hydration GCE Instance Service Account"
}

# Hydration Workflow SA
# The hyrdration workflow runs under this service account.
resource "google_service_account" "hydration_workflow_sa" {
  project      = var.project
  account_id   = var.hydration-workflow-sa
  display_name = "Hydration Workflow Service Account"
}

# Allow workflow to deploy the STS Agent instance template
resource "google_project_iam_member" "workflow_compute_admin" {
  project = var.project
  role    = "roles/compute.instanceAdmin"
  member  = google_service_account.hydration_workflow_sa.member
}

# Allow workflow to administer transfer jobs
resource "google_project_iam_member" "workflow_sts_admin" {
  project = var.project
  role    = "roles/storagetransfer.admin"
  member  = google_service_account.hydration_workflow_sa.member
}

# Workflow SA needs roles/serviceusage.serviceUsageConsumer to DELETE
# created STS transfer jobs
resource "google_project_iam_member" "workflow_usage_consumer" {
  project = var.project
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = google_service_account.hydration_workflow_sa.member
}

# Allow workflow to create logging entires roles/logging.logWriter
resource "google_project_iam_member" "workflow_logging_writer" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = google_service_account.hydration_workflow_sa.member
}

# Allow the workflow to attach the hydration_gce_instance_sa to
# STS agent instance
resource "google_service_account_iam_member" "workflow_sa_user" {
  service_account_id = google_service_account.hydration_gce_instance_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.hydration_workflow_sa.member
}

# STS Agent compute engine template
resource "google_compute_instance_template" "sts_agent_template" {
  project      = var.project
  name         = var.sts_instance_template_name
  machine_type = var.machine_type

  can_ip_forward          = false
  metadata_startup_script = null

  labels = {
    "container-vm" = data.google_compute_image.cos_image.name
  }

  metadata = merge(
    { "user-data" = local.cloud_config },
  )

  disk {
    source_image = data.google_compute_image.cos_image.self_link
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = var.network
  }

  service_account {
    email  = google_service_account.hydration_gce_instance_sa.email
    scopes = ["cloud-platform"] # TODO(rzurcher): move to var - min scope
  }

  scheduling {
    preemptible         = false
    on_host_maintenance = "MIGRATE"
    automatic_restart   = true
  }
  depends_on = [
    google_project_service.services["compute.googleapis.com"]
  ]
}

# Hydration workflow
resource "google_workflows_workflow" "hydrate" {
  name                = var.hydration_workflow_name
  region              = var.region
  description         = <<-EOT
Hydrate a PD from GCS
Args (json encode)
  bucket: Source bucket name
  bucketPath: Path to copy from. Empty string for entire bucket
  zone: Zone of the PD
  pdName: Name of PD to hydrate
  pdPath: Path to hydrate to. '/' for root.
EOT
  service_account     = google_service_account.hydration_workflow_sa.name
  call_log_level      = "LOG_ALL_CALLS"
  source_contents     = file("${path.module}/templates/hydrate.workflows.yaml")
  deletion_protection = false
}
