# Personal blogs infrastructure

## Working with Terraform

This repository uses Terraform version `1.9.8` and the `digitalocean/digitalocean` provider version `>2.34.1`

## Global Services

### Install Sealed Secrets(kubeseal)

Visit the [bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#usage) official Github repository to learn how to use it

```bash
helm --kubeconfig terraform/kubeconfig.yaml repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm --kubeconfig terraform/kubeconfig.yaml install sealed-secrets -n kube-system --set-string fullnameOverride=sealed-secrets-controller sealed-secrets/sealed-secrets
```

### Install ingress-nginx

```bash
helm --kubeconfig terraform/kubeconfig.yaml install -n ingress-nginx --create-namespace -f global-services/nginx-ingress-values.yaml --set controller.ingressClassResource.default=true ingress-nginx ingress-nginx/ingress-nginx
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
kubectl --kubeconfig terraform/kubeconfig.yaml apply -f global-services/cloudflare-sealedsecret.yaml
helm --kubeconfig terraform/kubeconfig.yaml install external-dns bitnami/external-dns -f global-services/externaldns-values.yaml -n external-dns
```

### Install MariaDB database for WordPress

```bash
kubectl --kubeconfig terraform/kubeconfig.yaml create namespace mariadb
kubectl --kubeconfig terraform/kubeconfig.yaml apply -f global-services/mariadb-sealedsecret.yaml
helm --kubeconfig terraform/kubeconfig.yaml install mariadb bitnami/mariadb -f global-services/mariadb-values.yaml -n mariadb --set global.storageClass=do-block-storage
```

### Install Redis

```bash
kubectl --kubeconfig terraform/kubeconfig.yaml create namespace redis-ns
kubectl --kubeconfig terraform/kubeconfig.yaml apply -f global-services/redis-sealedsecret.yaml
helm --kubeconfig terraform/kubeconfig.yaml install redis bitnami/redis -f global-services/redis-values.yaml -n redis-ns
```
