# Production Cluster GitOps Configuration

This directory contains the GitOps configuration for the production Kubernetes cluster managed by Flux v2.

## Directory Structure

```
clusters/prod/
├── flux-system/          # Flux bootstrap files (auto-generated)
├── infra/                # Infrastructure components
│   ├── helm-repos/       # Helm repository definitions
│   ├── cert-manager/     # Certificate management
│   ├── external-dns/     # Cloudflare DNS integration
│   ├── issuers/          # Let's Encrypt issuers
│   └── gateway/          # Gateway API with Cilium
└── kustomization.yaml    # Root kustomization
```

## Domains Managed

- `douglasbarahona.me`
- `devandops.show`
- `brushbeauty.shop`

## Prerequisites

1. **Kubernetes cluster** running on DigitalOcean
2. **Cilium CNI** with Gateway API support enabled
3. **GitHub personal access token** with repo permissions
4. **Cloudflare API tokens** with DNS:Edit and Zone:Read permissions
5. **Age encryption key** for SOPS secret management

## Bootstrap Instructions

### 1. Install Flux CLI

```bash
# macOS
brew install fluxcd/tap/flux

# Linux
curl -s https://fluxcd.io/install.sh | sudo bash
```

### 2. Set up SOPS encryption

```bash
# Install age
brew install age  # macOS
# OR
apt install age   # Ubuntu/Debian

# Generate age key
age-keygen -o age.key

# Extract public key and update .sops.yaml
grep "public key:" age.key

# Store age.key securely and add to .gitignore
echo "age.key" >> .gitignore
```

### 3. Create Cloudflare API tokens

Create two API tokens at https://dash.cloudflare.com/profile/api-tokens:

**Token 1: external-dns**
- Permissions: Zone > DNS > Edit, Zone > Zone > Read
- Zone Resources: Include > All zones (or specific zones)

**Token 2: cert-manager (DNS-01 challenges)**
- Permissions: Zone > DNS > Edit, Zone > Zone > Read
- Zone Resources: Include > All zones (or specific zones)

### 4. Encrypt secrets with SOPS

```bash
# Update the secrets with your actual Cloudflare API tokens
# Edit these files and replace REPLACE_WITH_CLOUDFLARE_API_TOKEN

# Encrypt external-dns secret
sops --encrypt --in-place \
  clusters/prod/infra/external-dns/secret-cloudflare-api-token-external-dns.yaml

# Encrypt cert-manager secret
sops --encrypt --in-place \
  clusters/prod/infra/issuers/secret-cloudflare-api-token-dns01.yaml
```

### 5. Configure Cloudflare Transform Rules

For each domain, create a Transform Rule:

1. Go to: **Rules > Transform Rules > Modify Request Header**
2. Create rule: **"Add Origin Verify Header"**
3. When incoming requests match:
   ```
   (http.host eq "douglasbarahona.me" or http.host ends_with ".douglasbarahona.me") or
   (http.host eq "devandops.show" or http.host ends_with ".devandops.show") or
   (http.host eq "brushbeauty.shop" or http.host ends_with ".brushbeauty.shop")
   ```
4. Then: Set static
   - Header name: `X-Origin-Verify`
   - Value: Generate with: `openssl rand -hex 32`
5. Update `cilium-http-route-filter-origin-verify.yaml` with the same token

### 6. Bootstrap Flux

```bash
# Export GitHub token
export GITHUB_TOKEN=<your-token>

# Bootstrap Flux
flux bootstrap github \
  --owner=douz \
  --repository=blogs-infrastructure \
  --branch=main \
  --path=clusters/prod \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller

# Configure SOPS decryption
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.key

# Update flux-system kustomization to use SOPS
flux create kustomization flux-system \
  --source=flux-system \
  --path=clusters/prod \
  --prune=true \
  --interval=10m \
  --decryption-provider=sops \
  --decryption-secret=sops-age
```

### 7. Verify deployment

```bash
# Check Flux status
flux check

# Watch reconciliation
flux get kustomizations --watch

# Check all HelmReleases
flux get helmreleases -A

# Verify cert-manager
kubectl get clusterissuer
kubectl get certificate -A

# Verify Gateway
kubectl get gateway -n ingress
kubectl get certificate -n ingress

# Check DNS records
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

## Maintenance

### Update Helm releases

```bash
# Check for updates
flux get helmreleases -A

# Suspend reconciliation (optional)
flux suspend helmrelease cert-manager -n flux-system

# Update chart version in the HelmRelease YAML
# Then resume
flux resume helmrelease cert-manager -n flux-system
```

### Rotate secrets

```bash
# Edit encrypted secret
sops clusters/prod/infra/external-dns/secret-cloudflare-api-token-external-dns.yaml

# Commit and push
git add clusters/prod/infra/external-dns/secret-cloudflare-api-token-external-dns.yaml
git commit -m "chore: rotate external-dns Cloudflare token"
git push

# Force reconciliation
flux reconcile kustomization external-dns
```

### Debug issues

```bash
# Check Flux logs
flux logs --all-namespaces --follow

# Describe HelmRelease
kubectl describe helmrelease cert-manager -n flux-system

# Check events
kubectl get events -n flux-system --sort-by='.lastTimestamp'

# Suspend and resume
flux suspend kustomization <name>
flux resume kustomization <name>
```

## Security Notes

- ✅ All secrets are encrypted with SOPS
- ✅ Cloudflare proxy enabled (orange cloud)
- ✅ Origin verification via X-Origin-Verify header
- ✅ TLS certificates auto-renewed via Let's Encrypt
- ✅ DNS-01 challenges for wildcard certificates
- ⚠️ Never commit unencrypted secrets to Git
- ⚠️ Store age.key securely (not in repo)

## Troubleshooting

### Certificates not issuing

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Describe certificate
kubectl describe certificate -n ingress

# Check challenges
kubectl get challenges -A
```

### DNS records not created

```bash
# Check external-dns logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Verify Cloudflare token permissions
# Check domain filters in HelmRelease
```

### Gateway not working

```bash
# Check Gateway status
kubectl describe gateway public-gateway -n ingress

# Verify Cilium is running with Gateway API
cilium status

# Check HTTPRoutes
kubectl get httproute -A
```

## Next Steps

After the infrastructure is deployed:

1. Deploy WordPress applications
2. Create HTTPRoutes for each site
3. Set up monitoring (Prometheus, Grafana)
4. Configure backups
5. Add additional security policies
