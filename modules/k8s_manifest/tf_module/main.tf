terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    kubernetes-alpha = {
      source  = "hashicorp/kubernetes-alpha"
      version = ">= 0.1.0"
    }
  }
}

provider "kubernetes" {
  host                   = var.host
  token                  = var.token
  cluster_ca_certificate = var.cluster_ca_certificate
  client_certificate     = var.client_certificate
  client_key             = var.client_key
}

resource "kubernetes_manifest" "manifest" {
  provider = kubernetes-alpha
  manifest = yamldecode(file(var.file_path))
  timeouts {
    update = "5m"
    create = "5m"
    delete = "5m"
  }
}
