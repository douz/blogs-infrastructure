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
  version = "1.36.3-do.0"

  cluster_autoscaler_configuration {
    scale_down_utilization_threshold = 0.65
    scale_down_unneeded_time         = "10m0s"
  }

  node_pool {
    name       = "wp-blogs-nodes"
    size       = "s-1vcpu-2gb"
    auto_scale = true
    min_nodes  = 4
    max_nodes  = 5
  }
}
