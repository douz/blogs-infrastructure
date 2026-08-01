# MariaDB Operator migration and backups

This directory contains the reviewed manifests for migrating the blogs database
from the legacy Bitnami MariaDB release to MariaDB Community Operator and for
running daily logical and physical backups in Cloudflare R2.

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
3. Apply the namespace-bound database and R2 SealedSecrets generated for the
   `databases` namespace.
4. Apply `migration/external-mariadb.yaml` and
   `migration/initial-backup.yaml`, then prove the backup through the Backup
   condition, its Kubernetes Job, and a recent non-empty R2 object.
5. Apply `mariadb.yaml` only after the initial backup is verified. It
   bootstraps the new database from `legacy-mariadb-initial`.
6. During the approved maintenance window, quiesce all WordPress Deployments,
   run and verify `migration/final-backup.yaml`, restore it with
   `migration/final-restore.yaml`, update both WordPress releases to the new
   database host, then restore their recorded replicas.
7. Apply the scheduled logical and physical backup resources while they remain
   suspended. Enable them only after one on-demand backup of each type has
   completed and its R2 object has been verified.

The files in `migration/` are one-time operational resources. Never apply them
casually or include them in an automatic Kustomization.

## WordPress post-renderer

`wordpress-replicas-post-renderer.sh` accepts `zero` or `recorded`. It refuses
to emit output unless the input contains exactly one known WordPress release's
main, cron, and services Deployments. `zero` sets all three replicas to zero;
`recorded` restores them to `2`, `1`, and `1` respectively. Non-Deployment
resources are passed through unchanged semantically.

## Backup and recovery boundaries

Both daily schedules retain backups for `168h`; the R2 bucket lifecycle also
expires objects below `logical/` and `physical/` after seven days. R2 provides
server-side encryption, while all S3 traffic uses TLS.

Logical backups support full-instance recovery or selective database recovery
through `Backup` and `Restore` resources. Physical backups are intended for
bootstrapping a new MariaDB instance; do not restore one over a running
instance. Backup failure detection is manual: inspect the custom-resource
conditions, the associated Job, and the resulting non-empty R2 object.

The legacy Bitnami Helm release, Secret, Services, StatefulSet, PVC, PV, and
DigitalOcean volume must be preserved without a retention deadline. After the
migration is accepted, only its StatefulSet replica count may be reduced to
zero under a separately approved operation.
