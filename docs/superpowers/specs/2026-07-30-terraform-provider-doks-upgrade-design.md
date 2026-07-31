# Terraform, DigitalOcean Provider, and DOKS Upgrade Design

## Context

The `douz/blogs-infrastructure` repository manages the production DigitalOcean
Kubernetes cluster used for Douglas Barahona's personal sites. Terraform runs
remotely in the HCP Terraform organization `dbarahona`, workspace `wp-blogs`,
after Douglas starts a CLI-driven run locally.

The verified starting state on 2026-07-30 is:

- Repository base: `origin/main` at `6b7f9bfe6dcc2d13a8609c55d65aa32249219646`
- Local Terraform CLI: `1.1.9`
- HCP Terraform workspace constraint: `~>1.7.0`
- Repository documentation target: Terraform `1.9.8`
- DigitalOcean provider constraint and lock: `~> 2.47.0`, locked to `2.47.0`
- Production cluster: `wp-blogs` (`600aa401-e809-4179-97c6-dc9444fbaa07`)
- Region and account: `nyc1`, DigitalOcean team `My Team`
- Current DOKS version: `1.33.6-do.0`
- Latest stable DOKS version offered globally: `1.36.3-do.0`
- Only upgrade currently offered to this cluster: `1.33.12-do.3`
- Surge upgrades: enabled
- MariaDB claim: `mariadb/data-mariadb-0`
- MariaDB volume: `pvc-59a68844-4137-4c30-85e0-5e543a8c62d0`

Terraform `1.15.8` is the latest stable Terraform release and
`digitalocean/digitalocean` `2.95.0` is the latest stable provider release at
the time of this design.

## Goals

1. Pin the local CLI, repository requirement, and HCP Terraform workspace to
   Terraform `1.15.8`.
2. Pin the DigitalOcean provider constraint to `~> 2.95.0` and lock provider
   version `2.95.0`.
3. Upgrade the production DOKS cluster through exact, DigitalOcean-supported
   version hops until it reaches `1.36.3-do.0`, provided that version remains
   the latest stable target during execution.
4. Preserve the MariaDB DigitalOcean block volume and verify its identity,
   binding, attachment, and workload health around every live upgrade.
5. Deliver the final configuration through a feature branch and pull request
   without automatically merging it.

## Non-goals

- Creating a backup system or changing the current no-backup posture
- Changing PVCs, PVs, StorageClasses, DigitalOcean volumes, or MariaDB storage
- Updating Kubernetes workloads, Helm releases, or experimental GitOps files
- Enabling automatic DOKS minor-version upgrades
- Refactoring unrelated Terraform resources
- Merging the final pull request

## Selected Approach

Use explicit pins and sequential saved-plan applies. Do not set the DOKS
version to `latest` and do not assume the complete upgrade path in advance.

The first exact DOKS hop is:

```text
1.33.6-do.0 -> 1.33.12-do.3
```

After a hop succeeds, query the cluster-specific DigitalOcean upgrades endpoint
again. Select the exact next supported version on the path to `1.36.3-do.0`,
write that pin into `terraform/main.tf`, and repeat the saved-plan workflow.
Never skip an unavailable hop. Stop if the offered path, latest stable target,
account, cluster, region, or storage identity differs from this design.

This approach is preferred over:

- `version = "latest"`, which is a moving target and prevents exact saved-plan
  review.
- Automatic DOKS upgrades, which handle patches but do not advance Kubernetes
  minor versions.

## Repository and Runtime Changes

Work on `feature/upgrade-terraform-provider-doks`, created from the current
`origin/main`.

The implementation changes are limited to:

- `terraform/versions.tf`: add `required_version = "~> 1.15.8"` and change the
  provider constraint to `~> 2.95.0`.
- `terraform/.terraform.lock.hcl`: regenerate with Terraform `1.15.8` and lock
  `digitalocean/digitalocean` `2.95.0`.
- `terraform/main.tf`: change only the DOKS `version` value for each exact,
  supported upgrade hop.
- `README.md`: align documented Terraform and provider versions with the pinned
  configuration.

Install Terraform `1.15.8` alongside the existing local `1.1.9` binary, verify
the official checksum, and then repoint `/usr/local/bin/terraform` to the new
binary. The existing binary remains the local rollback artifact.

Change the HCP Terraform workspace version setting from `~>1.7.0` to exact
`1.15.8`. Preserve the prior value so the workspace setting can be restored if
the new runtime cannot initialize or validate the unchanged configuration.

## Terraform Execution Flow

Provider/runtime modernization and each DOKS version hop are separate review
units.

For the provider/runtime unit:

1. Reverify the repository, revision, CLI version, HCP Terraform workspace,
   backend, lockfile, DigitalOcean account, and cluster identity.
2. Update the Terraform and provider pins and regenerate the lockfile.
3. Run formatting and static validation.
4. Create a private saved Terraform plan.
5. Inspect its resource actions without exposing sensitive values.
6. Proceed only if the plan contains no infrastructure changes.

For every DOKS hop:

1. Reverify the exact cluster, account, region, current version, supported
   upgrades, node health, MariaDB PVC/PV/volume identity, and application
   health.
2. Change only the exact DOKS version pin.
3. Run `terraform plan -out=<private-plan-file>`.
4. Inspect the saved plan's JSON action summary.
5. Require a new approval that names the exact source and target versions and
   acknowledges that Kubernetes version upgrades cannot be downgraded.
6. Run `terraform apply <private-plan-file>` without adding planning options.
7. Observe the DigitalOcean upgrade until the cluster is running.
8. Verify nodes, workloads, endpoints, and the unchanged MariaDB storage
   identity before considering the hop successful.

Saved plans remain outside Git in a private temporary directory and are deleted
after their approved apply or when superseded. A regenerated plan must be
reinspected; changed actions require new approval.

## Volume Preservation Invariant

The MariaDB PVC, PV, and DigitalOcean volume are not managed by this Terraform
configuration and must not appear as Terraform actions.

Before each apply, capture these read-only facts:

- PVC name, UID, phase, capacity, StorageClass, and bound PV
- PV name, UID, reclaim policy, CSI driver, and CSI volume handle
- DigitalOcean volume ID, name, region, size, status, and attachment state
- Kubernetes `VolumeAttachment` relationship

The apply is blocked unless the saved plan shows only an in-place
`digitalocean_kubernetes_cluster.wp-blogs` version update, plus any expected
ephemeral `local_file` action, and contains no delete, create-replacement, or
storage action.

After each apply, the PVC must be `Bound`, the PV and CSI volume handle must be
unchanged, the DigitalOcean volume must still exist in `nyc1`, its attachment
must converge successfully, and MariaDB must become Ready before continuing.

DigitalOcean documents that surge upgrades replace worker nodes and reattach
DigitalOcean Volumes Block Storage to the replacement nodes. Local worker-node
disk data is not preserved, but it is not used for the MariaDB database.

## Failure Handling and Recovery

Repository edits are recoverable from the verified task-branch base and commit
history. The Terraform `1.1.9` binary remains installed so the local symlink can
be restored. The previous HCP Terraform workspace constraint `~>1.7.0` is the
rollback value for runtime-setting failures that occur before a DOKS apply.

A DOKS version upgrade cannot be downgraded. If an apply is partial or its
result is unknown:

- Do not retry and do not advance to another version.
- Preserve the saved plan and read-only evidence.
- Observe DigitalOcean cluster and Kubernetes state.
- Do not delete, recreate, detach, or modify the PVC, PV, VolumeAttachment, or
  DigitalOcean volume.
- Stop for a new recovery decision if the volume does not reattach or MariaDB
  does not recover.

No DOKS hop is authorized by this design approval alone. Every hop requires
fresh saved-plan approval and an explicit one-time acknowledgement of the exact
non-downgradable version transition.

## Validation and Delivery

Static validation includes:

- `terraform fmt -check`
- `terraform init` with the approved upgrade options
- `terraform validate`
- Provider lockfile inspection
- Secret-safe saved-plan action inspection
- Gitleaks scan of the complete staged change

Live validation after every hop includes:

- DigitalOcean cluster state and version
- All nodes Ready on the target version
- MariaDB PVC/PV/volume identity unchanged
- MariaDB StatefulSet and pod Ready
- WordPress deployments Ready
- Documented site health endpoints successful

After the final hop, update the branch to the final exact DOKS version, run all
validation again, commit, push normally, open a pull request, and report its
checks. Do not merge the pull request without separate user authorization.

## Authoritative References

- HashiCorp Terraform install and current release:
  <https://developer.hashicorp.com/terraform/install>
- DigitalOcean provider release `v2.95.0`:
  <https://github.com/digitalocean/terraform-provider-digitalocean/releases/tag/v2.95.0>
- DigitalOcean DOKS upgrade process:
  <https://docs.digitalocean.com/products/kubernetes/how-to/upgrade-cluster/>
- DigitalOcean persistent volume behavior:
  <https://docs.digitalocean.com/products/kubernetes/how-to/add-volumes/>
