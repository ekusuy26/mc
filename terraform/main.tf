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

resource "google_artifact_registry_repository" "my-repo" {
  location      = "asia-northeast1"
  repository_id = "${var.app_name}-repository"
  description   = "docker repository"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }
}

# VPCを構築
resource "google_compute_network" "vpc_network" {
  name                    = "${var.app_name}-network"
  auto_create_subnetworks = false
  mtu                     = 1460
}

# 作成したVPCにサブネットを構築
resource "google_compute_subnetwork" "default" {
  name          = "${var.app_name}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.vpc_network.id
  # region        = var.region
}

# サーバーを構築
resource "google_compute_instance" "vm_instance" {
  name         = "${var.app_name}-instance"
  machine_type = "e2-micro"
  tags         = ["ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      # image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.default.id
    access_config {
    }
    # The presence of the access_config block, even without any arguments, gives the VM an external IP address, making it accessible over the internet.
    # VMに外部IPアドレスが設定され、インターネット経由でアクセスできる
  }
}

# ロードバランサー構築
# インスタンスグループの作成
resource "google_compute_instance_group" "webserver" {
  name = "${var.app_name}-webserver"

  instances = [
    "${google_compute_instance.vm_instance.self_link}",
  ]

  named_port {
    name = "http"
    port = "80"
  }
}
# ヘルスチェック
resource "google_compute_http_health_check" "webserver" {
  name         = "${var.app_name}-webserver-health-check"
  request_path = "/health_check"

  timeout_sec         = 5
  check_interval_sec  = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
}
# ロードバランサー構築

resource "google_compute_firewall" "ssh" {
  name = "allow-ssh"
  allow {
    ports    = ["22", "80"]
    protocol = "tcp"
  }
  direction     = "INGRESS"
  network       = google_compute_network.vpc_network.id
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  # source_ranges = [
  #   "130.211.0.0/22",  # Google LB
  #   "35.191.0.0/16",   # Google LB
  # ]
  target_tags = ["ssh"]
}

// Create a secret containing the personal access token and grant permissions to the Service Agent
resource "google_secret_manager_secret" "github_token_secret" {
  project   = var.project
  secret_id = "github_pat"

  replication {
    auto {}
  }
}

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

  filename = "cloudbuild.yaml"
}

// A variable for extracting the external IP address of the VM
output "Web-server-URL" {
  value = join("", ["http://", google_compute_instance.vm_instance.network_interface.0.access_config.0.nat_ip])
}
