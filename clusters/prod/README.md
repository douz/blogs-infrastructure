# Production Cluster GitOps Configuration

This directory contains the staged Argo CD GitOps foundation for the production
Kubernetes cluster. The manifests are reviewable repository state only: Argo CD
is not live until the separate bootstrap and service-adoption procedures are
approved and completed.

## Management model

Kustomize manages the pinned upstream Argo CD installation and standalone
Kubernetes resources such as the Argo ingress, certificate, and ClusterIssuer.
Argo CD continues to render the existing platform charts with Helm; the charts
are not converted into handwritten Kubernetes manifests.

The Phase 1 Helm scope is deliberately limited to:

- Sealed Secrets 2.15.0 in kube-system
- cert-manager v1.13.2 in cert-manager
- external-dns 9.0.3 in external-dns
- ingress-nginx 4.12.1 in ingress-nginx

The WordPress releases and namespaces are outside Argo CD. They retain their
current lifecycle and must not be added to an Application, ApplicationSet,
AppProject destination, or managed Kustomization.

## Directory structure

    clusters/prod/
    ├── bootstrap/argocd/       # Pinned non-HA Argo CD installation
    ├── control-plane/          # AppProject, Applications, and ApplicationSet
    ├── platform/               # Values and standalone platform manifests
    ├── flux-system/            # Preserved legacy Flux bootstrap
    └── infra/                  # Preserved legacy Flux infrastructure sources

The legacy Flux paths remain tracked during rollout. They are removed only
through a separate cleanup pull request after Argo CD and each adopted service
have remained healthy for at least seven days.

## Initial reconciliation posture

Every Application starts in manual-sync mode. Automated sync, pruning,
self-healing, Force, Replace, and application-wide or global server-side apply
are intentionally absent. ApplicationSet deletion preserves deployed resources.

`CustomResourceDefinition/applicationsets.argoproj.io` is the sole
server-side-apply exception because its OpenAPI schema exceeds Kubernetes'
client-side last-applied annotation limit. Initial bootstrap applies that CRD
separately with `kubectl apply --server-side --force-conflicts`; all remaining
bootstrap resources continue to use ordinary client-side apply. During later
Argo self-management, only that CRD carries
`argocd.argoproj.io/sync-options: ServerSideApply=true`. Do not add this sync
option to an Application, ApplicationSet, AppProject, another resource, or a
global policy.

Live adoption is sequential:

1. Bootstrap and verify Argo CD.
2. Adopt Sealed Secrets.
3. Adopt cert-manager and its existing HTTP-01 ClusterIssuer.
4. Adopt external-dns and its existing encrypted Cloudflare credential.
5. Adopt ingress-nginx without replacing its Service.
6. Observe the completed rollout for seven healthy days.
7. Remove obsolete Flux configuration through a separate reviewed change.

No repository merge performs those live steps by itself.

## Secrets

Git contains only SealedSecret ciphertext and nonsecret metadata. Never commit a
plaintext Kubernetes Secret, decoded value, sealing private key, password, or
repository private key.

To add or rotate a secret:

1. Use the production Sealed Secrets controller and strict name/namespace scope.
2. Pipe the client-side generated Secret directly into kubeseal.
3. Write only the resulting SealedSecret manifest to the repository.
4. Inspect encrypted key names and run the repository validation and secret
   scan before committing.

Do not create an intermediate plaintext manifest in the repository.

## Argo endpoint

argocd.douglasbarahona.me is configured for ingress-nginx TLS termination and
is intended to be protected by Cloudflare Zero Trust. Cloudflare DNS, proxying,
and Access policy resources remain externally managed and are not created by
these manifests.

## Validation

Run the local validation gate from the repository root:

    scripts/validate-gitops.sh

The script uses private temporary Helm homes and renders, checks Helm 3/4
parity, validates schemas, rejects duplicate resource identities, enforces the
WordPress and sync-policy boundaries, requires exactly one server-side-apply
annotation on the ApplicationSet CRD, verifies ciphertext-only secret handling,
and confirms the legacy Flux sources remain tracked.
