# Digital Ocean token
variable "digitalocean_token" {
  description = "Digital Ocean API Token"
}

variable "region" {
  description = "DigitalOcean region for all resources"
  type        = string
  default     = "nyc3"
}

variable "project_name" {
  description = "Project prefix/name used for resource naming"
  type        = string
  default     = "wp-sites"
}

variable "k8s_version" {
  description = "DOKS Kubernetes version slug (check DO for valid versions)"
  type        = string
  default     = "1.34.1-do.0"
}

variable "db_droplet_size" {
  description = "Droplet size for MariaDB (e.g. s-2vcpu-4gb)"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "redis_droplet_size" {
  description = "Droplet size for Redis (e.g. s-1vcpu-2gb or s-1vcpu-1gb if available)"
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "node_droplet_size" {
  description = "Droplet size for Kubernetes worker nodes"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "node_count" {
  description = "Initial number of Kubernetes worker nodes"
  type        = number
  default     = 3
}

variable "db_volume_size_gb" {
  description = "Size of the MariaDB data volume in GB"
  type        = number
  default     = 15
}

variable "vpc_cidr" {
  description = "CIDR range for the project VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "admin_cidr" {
  description = "CIDR block for admin access e.g. your home/office IP"
  type        = string
  default     = "0.0.0.0/0"
}

variable "droplet_image" {
  description = "OS image for droplets (e.g. rockylinux-9-x64, ubuntu-22-04-x64)"
  type        = string
  default     = "rockylinux-9-x64"
}

variable "ssh_key_name" {
  description = "Name of the SSH key in DigitalOcean to attach to droplets"
  type        = string
  default     = "dbarahona_ssh_key"
}
