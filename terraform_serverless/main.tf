terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.1.0" //オプション。設定しないと常に最新版のプロバイダーを使用する
    }
  }
}

provider "google" { //上記の指定したプロバイダーを構成する
  credentials = file(var.credentials_file)

  project = var.project
  region  = var.region
  zone    = var.zone
}

// Create a secret containing the personal access token and grant permissions to the Service Agent
# シークレットマネージャーを設定
resource "google_secret_manager_secret" "github_token_secret" {
  project   = var.project
  secret_id = "github_pat"

  replication {
    auto {}
  }
}

# 設定したシークレットマネージャーにgithub tokenを設定
resource "google_secret_manager_secret_version" "github_token_secret_version" {
  secret      = google_secret_manager_secret.github_token_secret.id
  secret_data = var.github_pat
}

data "google_iam_policy" "serviceagent_secretAccessor" {
  binding {
    role = "roles/secretmanager.secretAccessor"
    members = [
      "serviceAccount:${var.service_account}",
      "serviceAccount:${var.service_account_cloudbuild}"
    ]
  }
}

# 設定したシークレットマネージャーにアクセス権を設定
resource "google_secret_manager_secret_iam_policy" "policy" {
  project     = google_secret_manager_secret.github_token_secret.project
  secret_id   = google_secret_manager_secret.github_token_secret.secret_id
  policy_data = data.google_iam_policy.serviceagent_secretAccessor.policy_data
}

// Create the GitHub connection
# hostとの接続
resource "google_cloudbuildv2_connection" "my_connection" {
  project  = var.project
  location = "us-central1"
  name     = "${var.app_name}-cloudbuild-connection"

  github_config {
    app_installation_id = var.github_cloub_build_id
    authorizer_credential {
      oauth_token_secret_version = google_secret_manager_secret_version.github_token_secret_version.id
    }
  }
  depends_on = [google_secret_manager_secret_iam_policy.policy]
}
# レポジトリとの接続
resource "google_cloudbuildv2_repository" "my_repository" {
  project           = var.project
  location          = "us-central1"
  name              = "${var.app_name}-cloudbuild-repo"
  parent_connection = google_cloudbuildv2_connection.my_connection.name
  remote_uri        = var.github_repository_uri
}

# トリガーを設定する
resource "google_cloudbuild_trigger" "filename-trigger" {
  location = "us-central1"

  repository_event_config {
    repository = google_cloudbuildv2_repository.my_repository.id
    push {
      branch = "develop"
    }
  }

  substitutions = {
    _PROJECT    = var.project
    _REGION     = var.region
    _LOCATION   = var.location
    _REPOSITORY = google_artifact_registry_repository.my-repo.repository_id
    _IMAGE      = "mc_frontend"
  }

  filename = "cloudbuild.yaml"
}

# cloudrunを構築する

# artifact repositoryの設定
resource "google_artifact_registry_repository" "my-repo" {
  location      = "asia-northeast1"
  repository_id = "${var.app_name}-repository"
  description   = "docker repository"
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
}

# # cloudrunの設定
# resource "google_cloud_run_v2_service" "default" {
#   name     = "cloudrun-service"
#   location = var.location
#   ingress  = "INGRESS_TRAFFIC_ALL"

#   template {
#     containers {
#       image = "us-docker.pkg.dev/cloudrun/container/hello"
#     }
#   }
# }
