# Set terraform cloud backend
terraform {
  cloud {
    organization = "dbarahona"

    workspaces {
      name = "wp-blogs"
    }
  }
}

# Kubernetes Cluster
resource "digitalocean_kubernetes_cluster" "wp-blogs" {
  name    = "wp-blogs"
  region  = "nyc1"
  version = "1.22.8-do.1"

  node_pool {
    name       = "wp-blogs-nodes"
    size       = "s-1vcpu-2gb"
    node_count = 2
  }
}
