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

# Node pool for brush-wp workloads
resource "digitalocean_kubernetes_node_pool" "brush_wp_nodes" {
  cluster_id = digitalocean_kubernetes_cluster.wp-blogs.id
  name       = "brush-wp"
  size       = "s-2vcpu-4gb"
  node_count = 2
  taint {
    key    = "application"
    value  = "brush-wp"
    effect = "NoSchedule"
  }
}

##### Refactor

### VPC ###
resource "digitalocean_vpc" "wp-sites-vpc" {
  name        = "${var.project_name}-vpc"
  region      = var.region
  ip_range    = var.vpc_cidr
  description = "VPC for ${var.project_name} Kubernetes and database infrastructure"
}

### Kubernetes Cluster ###
resource "digitalocean_kubernetes_cluster" "wp_sites_cluster" {
  name    = "${var.project_name}-cluster"
  region  = var.region
  version = var.k8s_version

  # Attach to project VPC
  vpc_uuid = digitalocean_vpc.wp-sites-vpc.id

  node_pool {
    name       = "default-pool"
    size       = var.node_droplet_size
    node_count = var.node_count

    # Tags for firewall targeting & identification
    tags = [
      var.project_name,
      "env:prod",
      "role:k8s-node",
    ]
  }

  tags = [
    var.project_name,
    "env:prod",
    "type:doks",
  ]
}

### Droplets ###

## Data source to fetch SSH key by name
data "digitalocean_ssh_key" "admin" {
  name = var.ssh_key_name
}

## MariaDB
resource "digitalocean_droplet" "wp_sites_db" {
  name   = "${var.project_name}-db-1"
  region = var.region
  size   = var.db_droplet_size
  image  = var.droplet_image

  # Attach SSH key
  ssh_keys = [data.digitalocean_ssh_key.admin.id]

  # Attach to VPC
  vpc_uuid = digitalocean_vpc.wp-sites-vpc.id

  # Keep defaults for public networking; you can later switch to private-only if desired.
  ipv6       = false
  backups    = false
  monitoring = true

  tags = [
    var.project_name,
    "env:prod",
    "role:db",
  ]
}

# Block storage volume for MariaDB data
resource "digitalocean_volume" "wp_sites_db_data" {
  name                    = "${var.project_name}-db-data"
  region                  = var.region
  size                    = var.db_volume_size_gb
  description             = "Persistent volume for MariaDB data"
  initial_filesystem_type = "ext4"
}

resource "digitalocean_volume_attachment" "db_data_attach" {
  droplet_id = digitalocean_droplet.wp_sites_db.id
  volume_id  = digitalocean_volume.wp_sites_db_data.id
}

## Redis
resource "digitalocean_droplet" "redis" {
  name   = "${var.project_name}-redis-1"
  region = var.region
  size   = var.redis_droplet_size
  image  = var.droplet_image

  # Attach SSH key
  ssh_keys = [data.digitalocean_ssh_key.admin.id]

  vpc_uuid = digitalocean_vpc.wp-sites-vpc.id

  ipv6       = false
  backups    = false
  monitoring = true

  tags = [
    var.project_name,
    "env:prod",
    "role:redis",
  ]
}

### Firewalls ###

## Firewall for Kubernetes nodes
resource "digitalocean_firewall" "k8s_nodes" {
  name = "${var.project_name}-k8s-nodes-fw"

  # Attach via tag used by node pool
  tags = ["role:k8s-node"]

  # Wait for cluster to be created so tags exist
  depends_on = [digitalocean_kubernetes_cluster.wp_sites_cluster]

  # Inbound: SSH & K8s API from admin CIDR (adjust as needed)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [var.admin_cidr]
  }

  # Allow all traffic from VPC CIDR (for internal cluster communication)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_cidr]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_cidr]
  }

  # Outbound: allow all
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Firewall for DB + Redis
resource "digitalocean_firewall" "db_redis" {
  name = "${var.project_name}-db-redis-fw"

  tags = [
    "role:db",
    "role:redis",
  ]

  # Wait for droplets to be created so tags exist
  depends_on = [
    digitalocean_droplet.wp_sites_db,
    digitalocean_droplet.redis,
  ]

  # Allow MariaDB from within VPC (K8s nodes, etc.)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "3306"
    source_addresses = [var.vpc_cidr]
  }

  # Allow Redis from within VPC
  inbound_rule {
    protocol         = "tcp"
    port_range       = "6379"
    source_addresses = [var.vpc_cidr]
  }

  # SSH only from admin CIDR
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [var.admin_cidr]
  }

  # Outbound: allow all
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
