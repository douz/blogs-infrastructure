# MariaDB Operator and backups

This directory contains the reviewed manifests for running the blogs database
with MariaDB Community Operator and daily logical and physical backups in
Cloudflare R2.

The operator charts are pinned to `26.6.0`. Install the CRDs separately before
the controller, because `operator-values.yaml` deliberately sets
`crds.enabled: false`:

```bash
helm upgrade --install mariadb-operator-crds mariadb-operator/mariadb-operator-crds \
  --version 26.6.0 --namespace mariadb-operator --wait
helm upgrade --install mariadb-operator mariadb-operator/mariadb-operator \
  --version 26.6.0 --namespace mariadb-operator \
  --values operator-values.yaml --wait
```

## Apply order

1. Apply `namespaces.yaml`.
2. Install the CRD and controller charts as separate Helm releases.
3. Apply `mariadb-credentials-sealedsecret.yaml` and
   `r2-credentials-sealedsecret.yaml`.
4. Apply `mariadb.yaml` and wait for the MariaDB resource and pod to become
   Ready.
5. Apply `logical-backup.yaml` and `physical-backup.yaml`, then verify each
   Backup condition, Kubernetes Job, and recent non-empty R2 object.

Both WordPress releases use `mariadb.databases.svc.cluster.local`. The
`wordpress-dbhost-values.yaml` file records that shared database host for Helm
operations.

## Backup and recovery boundaries

Both daily schedules retain backups for `168h`; the R2 bucket lifecycle also
expires objects below `logical/` and `physical/` after seven days. R2 provides
server-side encryption, while all S3 traffic uses TLS.

Logical backups support full-instance recovery or selective database recovery
through `Backup` and `Restore` resources. Physical backups are intended for
bootstrapping a new MariaDB instance; do not restore one over a running
instance. Backup failure detection is manual: inspect the custom-resource
conditions, the associated Job, and the resulting non-empty R2 object.
