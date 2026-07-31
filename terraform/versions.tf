terraform {
  required_version = "~> 1.15.8"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.95.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
  }
}
