# Personal blogs infrastructure

## Working with Terraform

This repository uses Terraform version `1.6.5` and the `digitalocean/digitalocean` provider version `>2.19.0`

## Global Services

### Install ingress-nginx

```bash
helm --kubeconfig terraform/kubeconfig.yaml install -n ingress-nginx --create-namespace --set controller.ingressClassResource.default=true ingress-nginx ingress-nginx/ingress-nginx
```

### Install cert-manager

```bash
kubectl --kubeconfig terraform/kubeconfig.yaml create namespace cert-manager
helm --kubeconfig terraform/kubeconfig.yaml install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.13.2 --set installCRDs=true
kubectl --kubeconfig terraform/kubeconfig.yaml apply -f global-services/cert-manager-cluster-issuer.yaml
```

### Install Cloudflare external-dns

```bash
kubectl --kubeconfig terraform/kubeconfig.yaml create namespace external-dns
kubectl --kubeconfig terraform/kubeconfig.yaml apply -f global-services/cloudflare-secret.yaml
helm --kubeconfig terraform/kubeconfig.yaml install external-dns bitnami/external-dns -f global-services/externaldns-values.yaml -n external-dns
```

### Install MariaDB database for WordPress

```bash
kubectl --kubeconfig terraform/kubeconfig.yaml create namespace mariadb
kubectl --kubeconfig terraform/kubeconfig.yaml apply -f global-services/mariadb-secret.yaml
helm --kubeconfig terraform/kubeconfig.yaml install mariadb bitnami/mariadb -f global-services/mariadb-values.yaml -n mariadb --set global.storageClass=do-block-storage
```

### Install Redis

```bash
kubectl --kubeconfig terraform/kubeconfig.yaml create namespace redis-ns
kubectl --kubeconfig terraform/kubeconfig.yaml apply -f global-services/redis-secret.yaml
helm --kubeconfig terraform/kubeconfig.yaml install redis bitnami/redis -f global-services/redis-values.yaml -n redis-ns
```
