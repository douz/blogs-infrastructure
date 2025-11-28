# Output kubeconfig file
resource "local_file" "kubeconfig_file" {
  content  = digitalocean_kubernetes_cluster.wp-blogs.kube_config.0.raw_config
  filename = "kubeconfig.yaml"
}

#Output kubeconfig variable
output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.wp-blogs.kube_config.0.raw_config
  sensitive = true
}

output "cluster_endpoint" {
  description = "Endpoint of the DOKS Kubernetes API server"
  value       = digitalocean_kubernetes_cluster.wp_sites_cluster.endpoint
}

output "cluster_name" {
  description = "Name of the DOKS cluster"
  value       = digitalocean_kubernetes_cluster.wp_sites_cluster.name
}

output "vpc_id" {
  description = "UUID of the DigitalOcean VPC"
  value       = digitalocean_vpc.wp-sites-vpc.id
}

output "db_private_ip" {
  description = "Private IPv4 address of the MariaDB droplet"
  value       = digitalocean_droplet.wp_sites_db.ipv4_address_private
}

output "redis_private_ip" {
  description = "Private IPv4 address of the Redis droplet"
  value       = digitalocean_droplet.redis.ipv4_address_private
}

output "db_droplet_id" {
  description = "Droplet ID of the MariaDB server"
  value       = digitalocean_droplet.wp_sites_db.id
}

output "redis_droplet_id" {
  description = "Droplet ID of the Redis server"
  value       = digitalocean_droplet.redis.id
}
