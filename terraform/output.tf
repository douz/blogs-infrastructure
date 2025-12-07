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
