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
  version = "1.33.6-do.0"

  node_pool {
    name       = "wp-blogs-nodes"
    size       = "s-1vcpu-2gb"
    node_count = 3
  }
}

# Additional node pool for database workloads only
resource "digitalocean_kubernetes_node_pool" "db_nodes" {
  cluster_id = digitalocean_kubernetes_cluster.wp-blogs.id
  name       = "db-nodes"
  size       = "s-2vcpu-4gb"
  node_count = 1
  taint {
    key    = "application"
    value  = "db"
    effect = "NoSchedule"
  }
}
