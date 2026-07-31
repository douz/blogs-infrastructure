# Terraform, DigitalOcean Provider, and DOKS Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Production mutations must be performed serially by the primary T.A.R.S. agent; subagents remain read-only and advisory.

**Goal:** Pin Terraform `1.15.8` and `digitalocean/digitalocean` `2.95.0`, then upgrade the production DOKS cluster through exact supported hops to `1.36.3-do.0` without deleting or replacing the MariaDB DigitalOcean volume.

**Architecture:** Modernize the local and HCP Terraform runtimes first, update and validate the provider lock independently, and then handle every Kubernetes version as its own committed configuration revision and saved Terraform plan. Each live hop is blocked unless DigitalOcean offers the exact target and the plan contains only an in-place DOKS update plus an allowed ephemeral `local_file` action.

**Tech Stack:** Terraform CLI and HCP Terraform, `digitalocean/digitalocean`, DigitalOcean Kubernetes, `doctl`, `kubectl`, Git, GitHub CLI, Gitleaks.

## Global Constraints

- Owner: Douglas Barahona; DigitalOcean account email: `douglas.barahona@me.com`; team: `My Team`.
- Environment: production only; region: `nyc1`.
- Source repository: `/Users/dbarahona/Sites/blogs-infrastructure`, origin `git@github.com:douz/blogs-infrastructure.git`.
- Task branch: `feature/upgrade-terraform-provider-doks`; base: `origin/main` at `6b7f9bfe6dcc2d13a8609c55d65aa32249219646`.
- Commit identity: `Douglas Barahona <douglas.barahona@me.com>`.
- HCP Terraform organization/workspace: `dbarahona/wp-blogs`; workspace ID `ws-hVdckeh26QEoq6fU`; remote execution; auto-apply disabled.
- Terraform target: exact `1.15.8` locally and in HCP Terraform; repository constraint `~> 1.15.8`.
- Provider target: constraint `~> 2.95.0`; lock `digitalocean/digitalocean` `2.95.0`.
- DOKS cluster: `wp-blogs`; ID `600aa401-e809-4179-97c6-dc9444fbaa07`; surge upgrades must remain enabled.
- Required DOKS sequence: `1.33.6-do.0` → `1.33.12-do.3` → `1.34.10-do.0` → `1.35.7-do.0` → `1.36.3-do.0`.
- Every target after `1.33.12-do.3` is conditional on `doctl kubernetes cluster get-upgrades` returning that exact version. Stop on any mismatch.
- MariaDB PVC UID: `59a68844-4137-4c30-85e0-5e543a8c62d0`; PV: `pvc-59a68844-4137-4c30-85e0-5e543a8c62d0`; PV UID: `38ab7dbe-1afc-4c4d-9fdc-86a429a3a5fc`.
- MariaDB CSI volume ID: `2b56552e-90a7-11ee-b219-0a58ac145355`; name: `pvc-59a68844-4137-4c30-85e0-5e543a8c62d0`; size: `8 GiB`; region: `nyc1`.
- No plan may delete, replace, detach, resize, or otherwise mutate the MariaDB PVC, PV, VolumeAttachment, or DigitalOcean volume.
- No DOKS apply may run without a freshly inspected saved plan, exact plan approval, and explicit acknowledgement that the named Kubernetes version transition cannot be downgraded.
- Saved plan directory: `/private/tmp/blogs-infrastructure-tfplans-20260730`, mode `0700`; never add it or plan contents to Git.
- GitOps files, workload upgrades, backup implementation, automatic DOKS minor upgrades, unrelated refactors, and PR merge are out of scope.

---

### Task 1: Install and Select Terraform CLI 1.15.8

**Files:**
- Create: `/Users/dbarahona/.terraform.versions/terraform_1.15.8`
- Modify: `/usr/local/bin/terraform` symlink
- Preserve: `/Users/dbarahona/.terraform.versions/terraform_1.1.9`

**Interfaces:**
- Consumes: HashiCorp's official Darwin AMD64 Terraform `1.15.8` archive and checksum list.
- Produces: `terraform version` reporting `Terraform v1.15.8` while retaining the prior binary for exact rollback.

- [ ] **Step 1: Present and obtain approval for the local-runtime mutation contract**

The contract must name the two filesystem targets above, the current symlink target, the official download URLs, checksum validation, the retained `1.1.9` recovery binary, and this exact conditional restore:

```bash
ln -sfn /Users/dbarahona/.terraform.versions/terraform_1.1.9 /usr/local/bin/terraform
terraform version
```

- [ ] **Step 2: Reverify architecture, current runtime, target paths, and identity**

Run:

```bash
uname -m
file /Users/dbarahona/.terraform.versions/terraform_1.1.9
ls -ld /Users/dbarahona/.terraform.versions /usr/local/bin
ls -l /usr/local/bin/terraform
terraform version
```

Expected: `x86_64`, an x86_64 Mach-O binary, and the symlink targeting `terraform_1.1.9`.

- [ ] **Step 3: Create a private download directory**

Run:

```bash
test ! -e /private/tmp/blogs-terraform-1.15.8-20260730
mkdir -m 700 /private/tmp/blogs-terraform-1.15.8-20260730
```

Expected: the first command succeeds and the directory is created with mode `0700`.

- [ ] **Step 4: Download Terraform and the official checksum list**

Run:

```bash
curl -fsSLo /private/tmp/blogs-terraform-1.15.8-20260730/terraform_1.15.8_darwin_amd64.zip https://releases.hashicorp.com/terraform/1.15.8/terraform_1.15.8_darwin_amd64.zip
curl -fsSLo /private/tmp/blogs-terraform-1.15.8-20260730/terraform_1.15.8_SHA256SUMS https://releases.hashicorp.com/terraform/1.15.8/terraform_1.15.8_SHA256SUMS
```

Expected: both files exist and are non-empty.

- [ ] **Step 5: Verify the archive checksum before extracting**

Run:

```bash
cd /private/tmp/blogs-terraform-1.15.8-20260730
awk '$2 == "terraform_1.15.8_darwin_amd64.zip" {print}' terraform_1.15.8_SHA256SUMS | shasum -a 256 -c -
```

Expected: `terraform_1.15.8_darwin_amd64.zip: OK`. Stop without installing on any other result.

- [ ] **Step 6: Extract and verify the downloaded binary**

Run:

```bash
unzip -q /private/tmp/blogs-terraform-1.15.8-20260730/terraform_1.15.8_darwin_amd64.zip -d /private/tmp/blogs-terraform-1.15.8-20260730/extracted
/private/tmp/blogs-terraform-1.15.8-20260730/extracted/terraform version
```

Expected: `Terraform v1.15.8`.

- [ ] **Step 7: Install the side-by-side binary and atomically select it**

Run:

```bash
test ! -e /Users/dbarahona/.terraform.versions/terraform_1.15.8
install -m 0755 /private/tmp/blogs-terraform-1.15.8-20260730/extracted/terraform /Users/dbarahona/.terraform.versions/terraform_1.15.8
ln -sfn /Users/dbarahona/.terraform.versions/terraform_1.15.8 /usr/local/bin/terraform
```

Expected: no output and exit status `0`.

- [ ] **Step 8: Verify the selected runtime and retained recovery binary**

Run:

```bash
ls -l /usr/local/bin/terraform
terraform version
/Users/dbarahona/.terraform.versions/terraform_1.1.9 version
```

Expected: the symlink targets `terraform_1.15.8`, the selected runtime reports `1.15.8`, and the retained runtime reports `1.1.9`.

### Task 2: Pin Terraform and the DigitalOcean Provider

**Files:**
- Modify: `terraform/versions.tf`
- Modify: `terraform/.terraform.lock.hcl`
- Modify: `README.md`

**Interfaces:**
- Consumes: the selected Terraform `1.15.8` CLI and existing HCP Terraform backend configuration.
- Produces: a deterministic Terraform `1.15.x` configuration and provider lock at `digitalocean/digitalocean` `2.95.0`.

- [ ] **Step 1: Present and obtain approval for the repository configuration mutation contract**

The contract must list the three files above, `5112730eab6cac51ebc377849336505d802a6c8f` as the Git recovery point, `terraform init -upgrade -input=false` as the lockfile mutation, and commit message `chore: update Terraform and DigitalOcean provider`.

- [ ] **Step 2: Reverify repository target, clean branch, origin, and identity**

Run:

```bash
cd /Users/dbarahona/Sites/blogs-infrastructure
git status --porcelain=v1 --branch
git remote -v
git rev-parse HEAD
git config --get user.name
git config --get user.email
terraform version
```

Expected: the task branch is clean, origin is `git@github.com:douz/blogs-infrastructure.git`, identity is personal, and Terraform is `1.15.8`.

- [ ] **Step 3: Update the Terraform and provider constraints**

Apply this exact content to `terraform/versions.tf`:

```hcl
terraform {
  required_version = "~> 1.15.8"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.95.0"
    }
  }
}
```

- [ ] **Step 4: Align the README version statement**

Replace README line 5 with:

```markdown
This repository uses Terraform version `1.15.8` and the `digitalocean/digitalocean` provider version `2.95.0`.
```

- [ ] **Step 5: Regenerate the provider lock using the selected runtime**

Run:

```bash
terraform -chdir=terraform init -upgrade -input=false
```

Expected: successful HCP Terraform initialization and installation of `digitalocean/digitalocean v2.95.0`; no plan or apply is started.

- [ ] **Step 6: Verify formatting, configuration, and provider selection**

Run:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform providers
sed -n '1,120p' terraform/.terraform.lock.hcl
```

Expected: formatting and validation pass; provider output and lockfile show `digitalocean/digitalocean` `2.95.0` with constraint `~> 2.95.0`.

- [ ] **Step 7: Inspect, secret-scan, and commit the repository change**

Run:

```bash
git diff --check
git diff -- terraform/versions.tf terraform/.terraform.lock.hcl README.md
git add terraform/versions.tf terraform/.terraform.lock.hcl README.md
git diff --cached --check
git diff --cached
gitleaks git --staged --redact --no-banner --exit-code 1 .
git remote -v
git config --get user.name
git config --get user.email
git commit -m "chore: update Terraform and DigitalOcean provider"
```

Expected: no secret findings and a commit containing only the three named files.

### Task 3: Pin the HCP Terraform Runtime and Prove the Provider Upgrade Is a No-op

**Files:**
- Create temporarily: `/private/tmp/blogs-infrastructure-tfplans-20260730/provider-runtime.tfplan`
- Modify remotely: HCP Terraform workspace `ws-hVdckeh26QEoq6fU` version setting

**Interfaces:**
- Consumes: repository Terraform/provider pins and the existing HCP Terraform credential.
- Produces: remote runs using exact Terraform `1.15.8` and a saved plan proving the provider/runtime update changes no infrastructure.

- [ ] **Step 1: Present and obtain approval for the HCP workspace and saved-plan mutation contract**

The contract must include:

- HCP workspace `dbarahona/wp-blogs`, ID `ws-hVdckeh26QEoq6fU`.
- PATCH from `~>1.7.0` to exact `1.15.8`.
- Creation of one remote speculative run and the private saved plan.
- Previous setting `~>1.7.0` as the validated rollback value.
- Conditional PATCH restore only if the new runtime cannot initialize or validate and no unrelated workspace drift exists.
- No Terraform apply.

- [ ] **Step 2: Freshly verify the workspace, Git revision, backend, account, and cluster**

Run:

```bash
cd /Users/dbarahona/Sites/blogs-infrastructure
git status --porcelain=v1 --branch
git rev-parse HEAD
terraform version
doctl auth list --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade}'
```

Read the HCP workspace safely:

```bash
TARS_TFC_TOKEN="$(jq -r '.credentials["app.terraform.io"].token // empty' /Users/dbarahona/.terraform.d/credentials.tfrc.json)"
test -n "$TARS_TFC_TOKEN"
curl -fsSL -H "Authorization: Bearer $TARS_TFC_TOKEN" -H "Content-Type: application/vnd.api+json" https://app.terraform.io/api/v2/workspaces/ws-hVdckeh26QEoq6fU | jq '{id:.data.id,name:.data.attributes.name,execution_mode:.data.attributes["execution-mode"],terraform_version:.data.attributes["terraform-version"],auto_apply:.data.attributes["auto-apply"],locked:.data.attributes.locked}'
```

Expected: personal DigitalOcean account/team, cluster `wp-blogs` in `nyc1` at `1.33.6-do.0`, workspace remote and unlocked with auto-apply false and version `~>1.7.0`.

- [ ] **Step 3: Create the private plan directory**

Run:

```bash
test ! -e /private/tmp/blogs-infrastructure-tfplans-20260730
mkdir -m 700 /private/tmp/blogs-infrastructure-tfplans-20260730
```

Expected: exact directory created with mode `0700`.

- [ ] **Step 4: Patch the HCP workspace to exact Terraform 1.15.8**

Run:

```bash
TARS_TFC_TOKEN="$(jq -r '.credentials["app.terraform.io"].token // empty' /Users/dbarahona/.terraform.d/credentials.tfrc.json)"
curl -fsSL -X PATCH -H "Authorization: Bearer $TARS_TFC_TOKEN" -H "Content-Type: application/vnd.api+json" --data '{"data":{"type":"workspaces","id":"ws-hVdckeh26QEoq6fU","attributes":{"terraform-version":"1.15.8"}}}' https://app.terraform.io/api/v2/workspaces/ws-hVdckeh26QEoq6fU | jq '{id:.data.id,terraform_version:.data.attributes["terraform-version"],updated_at:.data.attributes["updated-at"]}'
```

Expected: workspace ID unchanged and `terraform_version` equal to `1.15.8`.

- [ ] **Step 5: Verify the remote setting through a fresh GET**

Run:

```bash
TARS_TFC_TOKEN="$(jq -r '.credentials["app.terraform.io"].token // empty' /Users/dbarahona/.terraform.d/credentials.tfrc.json)"
curl -fsSL -H "Authorization: Bearer $TARS_TFC_TOKEN" -H "Content-Type: application/vnd.api+json" https://app.terraform.io/api/v2/workspaces/ws-hVdckeh26QEoq6fU | jq '{id:.data.id,terraform_version:.data.attributes["terraform-version"],execution_mode:.data.attributes["execution-mode"],auto_apply:.data.attributes["auto-apply"],locked:.data.attributes.locked}'
```

Expected: exact version `1.15.8`, remote execution, auto-apply false, and unlocked.

- [ ] **Step 6: Generate the provider/runtime saved plan**

Run:

```bash
terraform -chdir=terraform plan -input=false -out=/private/tmp/blogs-infrastructure-tfplans-20260730/provider-runtime.tfplan
```

Expected: the HCP run uses Terraform `1.15.8` and provider `2.95.0`; plan summary reports no infrastructure changes.

- [ ] **Step 7: Inspect only secret-safe plan metadata**

Run:

```bash
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/provider-runtime.tfplan | jq '{terraform_version,resource_actions:[.resource_changes[] | {address,type,actions:.change.actions}]}'
```

Expected: `terraform_version` is `1.15.8` and every action is `["no-op"]`.

- [ ] **Step 8: Remove only the inspected no-op plan**

Run:

```bash
rm -f /private/tmp/blogs-infrastructure-tfplans-20260730/provider-runtime.tfplan
test ! -e /private/tmp/blogs-infrastructure-tfplans-20260730/provider-runtime.tfplan
```

Expected: the exact secret-bearing plan file no longer exists.

### Task 4: Upgrade DOKS to 1.33.12-do.3

**Files:**
- Modify: `terraform/main.tf`
- Create temporarily: `/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan`

**Interfaces:**
- Consumes: cluster `1.33.6-do.0`, exact offered upgrade `1.33.12-do.3`, provider `2.95.0`, Terraform `1.15.8`.
- Produces: cluster and nodes at `1.33.12-do.3` with MariaDB CSI volume `2b56552e-90a7-11ee-b219-0a58ac145355` preserved.

- [ ] **Step 1: Run the complete read-only production and storage preflight**

Run:

```bash
doctl auth list --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,storage_class:.spec.storageClassName,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,storage_class:.spec.storageClassName,csi_driver:.spec.csi.driver,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,attacher:.spec.attacher,node_name:.spec.nodeName,attached:.status.attached}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes,pods,statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: exact personal account/team, cluster running at `1.33.6-do.0`, surge enabled, `1.33.12-do.3` offered, volume/PVC/PV identifiers exactly match Global Constraints, attachment true, workloads Ready, and both endpoints return successful HTTP status codes.

- [ ] **Step 2: Present and obtain approval for the configuration mutation and saved-plan contract**

The contract must name the exact file change `1.33.6-do.0` → `1.33.12-do.3`, commit, private plan file, HCP run, success checks, and unchanged storage invariant. It must state that plan creation does not authorize apply.

- [ ] **Step 3: Pin and commit DOKS 1.33.12-do.3**

Change only this line in `terraform/main.tf`:

```hcl
  version = "1.33.12-do.3"
```

Run:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
git diff --check
git diff -- terraform/main.tf
git add terraform/main.tf
git diff --cached
gitleaks git --staged --redact --no-banner --exit-code 1 .
git remote -v
git config --get user.name
git config --get user.email
git commit -m "chore: pin DOKS 1.33.12-do.3"
```

Expected: one-line version change committed with the personal identity.

- [ ] **Step 4: Generate and inspect the saved plan**

Run:

```bash
terraform -chdir=terraform plan -input=false -out=/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan | jq '{terraform_version,resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan | jq '.resource_changes[] | select(.address == "digitalocean_kubernetes_cluster.wp-blogs") | {actions:.change.actions,before_version:.change.before.version,after_version:.change.after.version,replace_paths:.change.replace_paths}'
```

Expected: cluster action `["update"]`, before `1.33.6-do.0`, after `1.33.12-do.3`, empty replacement paths, no storage address, and at most an expected ephemeral replacement of `local_file.kubeconfig_file`.

- [ ] **Step 5: Obtain exact saved-plan approval and non-downgrade acknowledgement**

Present the inspected actions, account, cluster, region, source/target versions, storage identities, lack of cluster/storage replacement, and this exact consequence:

```text
Applying this plan upgrades production DOKS cluster 600aa401-e809-4179-97c6-dc9444fbaa07 from 1.33.6-do.0 to 1.33.12-do.3. DOKS versions cannot be downgraded.
```

Do not continue without explicit approval and acknowledgement.

- [ ] **Step 6: Reverify the plan context immediately before apply**

Run:

```bash
cd /Users/dbarahona/Sites/blogs-infrastructure
git status --porcelain=v1 --branch
git rev-parse HEAD
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade}'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,storage_class:.spec.storageClassName,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,csi_driver:.spec.csi.driver,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
TARS_TFC_TOKEN="$(jq -r '.credentials["app.terraform.io"].token // empty' /Users/dbarahona/.terraform.d/credentials.tfrc.json)"
curl -fsSL -H "Authorization: Bearer $TARS_TFC_TOKEN" -H "Content-Type: application/vnd.api+json" https://app.terraform.io/api/v2/workspaces/ws-hVdckeh26QEoq6fU | jq '{id:.data.id,terraform_version:.data.attributes["terraform-version"],locked:.data.attributes.locked}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan | jq '{resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
```

Expected: no drift from the approved account, cluster `1.33.6-do.0`, offered target, storage identities, HCP runtime `1.15.8`, or plan actions.

- [ ] **Step 7: Apply only the approved saved plan**

Run:

```bash
terraform -chdir=terraform apply /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan
```

Expected: HCP Terraform reports the approved in-place update. Do not add variables, targets, replacement, refresh, or planning options.

- [ ] **Step 8: Observe and verify the completed hop**

Poll with separate read-only calls, communicating progress between calls:

```bash
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
```

After state returns to running, run:

```bash
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes -o json | jq '[.items[] | {name:.metadata.name,ready:([.status.conditions[]|select(.type=="Ready")][0].status),kubelet_version:.status.nodeInfo.kubeletVersion}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,storage_class:.spec.storageClassName,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,csi_driver:.spec.csi.driver,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs rollout status statefulset/mariadb -n mariadb --timeout=10m
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: cluster and all nodes at `1.33.12-do.3`, all storage identifiers unchanged, attachment true, MariaDB Ready, deployments available, and endpoints healthy. On partial or ambiguous results, preserve evidence and stop; do not retry.

- [ ] **Step 9: Remove only the successfully applied saved plan**

Run:

```bash
rm -f /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan
test ! -e /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.33.12-do.3.tfplan
```

### Task 5: Upgrade DOKS to 1.34.10-do.0

**Files:**
- Modify: `terraform/main.tf`
- Create temporarily: `/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan`

**Interfaces:**
- Consumes: verified healthy cluster `1.33.12-do.3` and an exact DigitalOcean offer for `1.34.10-do.0`.
- Produces: healthy cluster `1.34.10-do.0` with unchanged MariaDB storage identities.

- [ ] **Step 1: Verify the exact next hop and all production invariants**

Run:

```bash
doctl auth list --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,storage_class:.spec.storageClassName,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,csi_driver:.spec.csi.driver,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes,pods,statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: current cluster `1.33.12-do.3`, exact target `1.34.10-do.0` returned, unchanged storage identities, healthy workloads, and healthy endpoints. Stop and revise the plan if any invariant differs.

- [ ] **Step 2: Obtain approval for the exact configuration and plan-creation contract**

Name source `1.33.12-do.3`, target `1.34.10-do.0`, file/commit, HCP run, exact plan path, storage invariant, verification, and failure stop. Plan creation does not authorize apply.

- [ ] **Step 3: Pin, validate, scan, and commit DOKS 1.34.10-do.0**

Set:

```hcl
  version = "1.34.10-do.0"
```

Run:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
git diff --check
git diff -- terraform/main.tf
git add terraform/main.tf
git diff --cached
gitleaks git --staged --redact --no-banner --exit-code 1 .
git commit -m "chore: pin DOKS 1.34.10-do.0"
terraform -chdir=terraform plan -input=false -out=/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan | jq '{terraform_version,resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan | jq '.resource_changes[] | select(.address == "digitalocean_kubernetes_cluster.wp-blogs") | {actions:.change.actions,before_version:.change.before.version,after_version:.change.after.version,replace_paths:.change.replace_paths}'
```

Expected: only in-place cluster update `1.33.12-do.3` → `1.34.10-do.0` and allowed ephemeral `local_file`; no storage actions.

- [ ] **Step 4: Obtain saved-plan approval and exact non-downgrade acknowledgement**

Require acknowledgement:

```text
Applying this plan upgrades production DOKS cluster 600aa401-e809-4179-97c6-dc9444fbaa07 from 1.33.12-do.3 to 1.34.10-do.0. DOKS versions cannot be downgraded.
```

- [ ] **Step 5: Reverify, apply, observe, and validate**

Immediately before apply, run:

```bash
git status --porcelain=v1 --branch
git rev-parse HEAD
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade}'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,volume_handle:.spec.csi.volumeHandle}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan | jq '{resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
```

Expected: every fresh identity, version, storage, and plan value matches the approved plan. Stop on drift.

Run the mutation separately:

```bash
terraform -chdir=terraform apply /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan
```

Observe cluster state with separate calls:

```bash
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
```

After running state returns, verify:

```bash
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes -o json | jq '[.items[] | {name:.metadata.name,ready:([.status.conditions[]|select(.type=="Ready")][0].status),kubelet_version:.status.nodeInfo.kubeletVersion}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs rollout status statefulset/mariadb -n mariadb --timeout=10m
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: cluster and nodes at `1.34.10-do.0`, unchanged volume ID, PV/PVC UIDs, size, region, and binding; MariaDB and endpoints healthy. Stop on ambiguity without retry.

- [ ] **Step 6: Remove only the successfully applied saved plan**

Run:

```bash
rm -f /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan
test ! -e /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.34.10-do.0.tfplan
```

### Task 6: Upgrade DOKS to 1.35.7-do.0

**Files:**
- Modify: `terraform/main.tf`
- Create temporarily: `/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan`

**Interfaces:**
- Consumes: verified healthy cluster `1.34.10-do.0` and an exact DigitalOcean offer for `1.35.7-do.0`.
- Produces: healthy cluster `1.35.7-do.0` with unchanged MariaDB storage identities.

- [ ] **Step 1: Verify the exact next hop and all production invariants**

Run:

```bash
doctl auth list --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,storage_class:.spec.storageClassName,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,csi_driver:.spec.csi.driver,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes,pods,statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: current cluster `1.34.10-do.0`, exact target `1.35.7-do.0`, unchanged storage identities, healthy workloads, and healthy endpoints. Stop and revise if any invariant differs.

- [ ] **Step 2: Obtain approval for configuration and plan creation**

Name source `1.34.10-do.0`, target `1.35.7-do.0`, exact mutation, storage invariant, and plan path. Do not include apply authorization.

- [ ] **Step 3: Pin, validate, scan, commit, and plan**

Set:

```hcl
  version = "1.35.7-do.0"
```

Run:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
git diff --check
git diff -- terraform/main.tf
git add terraform/main.tf
git diff --cached
gitleaks git --staged --redact --no-banner --exit-code 1 .
git commit -m "chore: pin DOKS 1.35.7-do.0"
terraform -chdir=terraform plan -input=false -out=/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan | jq '{terraform_version,resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan | jq '.resource_changes[] | select(.address == "digitalocean_kubernetes_cluster.wp-blogs") | {actions:.change.actions,before_version:.change.before.version,after_version:.change.after.version,replace_paths:.change.replace_paths}'
```

Expected: only in-place cluster update `1.34.10-do.0` → `1.35.7-do.0` and allowed ephemeral `local_file`; no storage actions.

- [ ] **Step 4: Obtain saved-plan approval and exact non-downgrade acknowledgement**

Require acknowledgement:

```text
Applying this plan upgrades production DOKS cluster 600aa401-e809-4179-97c6-dc9444fbaa07 from 1.34.10-do.0 to 1.35.7-do.0. DOKS versions cannot be downgraded.
```

- [ ] **Step 5: Reverify, apply, observe, and validate**

Immediately before apply, run:

```bash
git status --porcelain=v1 --branch
git rev-parse HEAD
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade}'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,volume_handle:.spec.csi.volumeHandle}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan | jq '{resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
```

Expected: every fresh identity, version, storage, and plan value matches the approved plan. Stop on drift.

Run the mutation separately:

```bash
terraform -chdir=terraform apply /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan
```

Observe with separate calls:

```bash
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
```

After running state returns, run:

```bash
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes -o json | jq '[.items[] | {name:.metadata.name,ready:([.status.conditions[]|select(.type=="Ready")][0].status),kubelet_version:.status.nodeInfo.kubeletVersion}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs rollout status statefulset/mariadb -n mariadb --timeout=10m
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: target version and nodes healthy, exact volume/PV/PVC identities unchanged, MariaDB Ready, and both endpoints healthy.

- [ ] **Step 6: Remove only the successfully applied saved plan**

Run:

```bash
rm -f /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan
test ! -e /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.35.7-do.0.tfplan
```

### Task 7: Upgrade DOKS to 1.36.3-do.0

**Files:**
- Modify: `terraform/main.tf`
- Create temporarily: `/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan`

**Interfaces:**
- Consumes: verified healthy cluster `1.35.7-do.0` and an exact DigitalOcean offer for `1.36.3-do.0`.
- Produces: healthy cluster at the verified latest stable `1.36.3-do.0` with unchanged MariaDB storage identities.

- [ ] **Step 1: Verify the final target is still latest and is offered**

Run:

```bash
doctl kubernetes options versions --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
```

Run:

```bash
doctl auth list --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,storage_class:.spec.storageClassName,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,csi_driver:.spec.csi.driver,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes,pods,statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: `1.36.3-do.0` remains the globally latest stable target and is explicitly offered to this cluster. Stop if either invariant differs.

- [ ] **Step 2: Obtain approval for configuration and plan creation**

Name source `1.35.7-do.0`, target `1.36.3-do.0`, exact file/commit/run/plan mutations, the unchanged volume invariant, and the final validation.

- [ ] **Step 3: Pin, validate, scan, commit, and plan**

Set:

```hcl
  version = "1.36.3-do.0"
```

Run:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
git diff --check
git diff -- terraform/main.tf
git add terraform/main.tf
git diff --cached
gitleaks git --staged --redact --no-banner --exit-code 1 .
git commit -m "chore: pin DOKS 1.36.3-do.0"
terraform -chdir=terraform plan -input=false -out=/private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan | jq '{terraform_version,resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan | jq '.resource_changes[] | select(.address == "digitalocean_kubernetes_cluster.wp-blogs") | {actions:.change.actions,before_version:.change.before.version,after_version:.change.after.version,replace_paths:.change.replace_paths}'
```

Expected: only in-place cluster update `1.35.7-do.0` → `1.36.3-do.0` and allowed ephemeral `local_file`; no storage actions.

- [ ] **Step 4: Obtain saved-plan approval and exact non-downgrade acknowledgement**

Require acknowledgement:

```text
Applying this plan upgrades production DOKS cluster 600aa401-e809-4179-97c6-dc9444fbaa07 from 1.35.7-do.0 to 1.36.3-do.0. DOKS versions cannot be downgraded.
```

- [ ] **Step 5: Reverify, apply, observe, and validate**

Immediately before apply, run:

```bash
git status --porcelain=v1 --branch
git rev-parse HEAD
doctl account get --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {email,uuid,status,email_verified,team}'
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade}'
doctl kubernetes cluster get-upgrades 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq '[.[] | {slug,kubernetes_version,supported}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,volume_handle:.spec.csi.volumeHandle}'
terraform -chdir=terraform show -json /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan | jq '{resource_actions:[.resource_changes[] | {address,type,actions:.change.actions,replace_paths:.change.replace_paths}]}'
```

Expected: every fresh identity, version, storage, and plan value matches the approved plan. Stop on drift.

Run the mutation separately:

```bash
terraform -chdir=terraform apply /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan
```

Observe with separate calls:

```bash
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
```

After running state returns, run:

```bash
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes -o json | jq '[.items[] | {name:.metadata.name,ready:([.status.conditions[]|select(.type=="Ready")][0].status),kubelet_version:.status.nodeInfo.kubeletVersion}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs rollout status statefulset/mariadb -n mariadb --timeout=10m
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: cluster and nodes at `1.36.3-do.0`; volume/PV/PVC IDs, UIDs, size, region, and binding unchanged; attachment true; MariaDB Ready; applications healthy.

- [ ] **Step 6: Remove only the successfully applied saved plan**

Run:

```bash
rm -f /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan
test ! -e /private/tmp/blogs-infrastructure-tfplans-20260730/doks-1.36.3-do.0.tfplan
```

### Task 8: Final Drift Check and Pull Request Delivery

**Files:**
- Read: all branch changes
- Remove when empty: `/private/tmp/blogs-infrastructure-tfplans-20260730`
- Modify remotely: GitHub branch and pull-request records

**Interfaces:**
- Consumes: healthy production cluster at `1.36.3-do.0` and complete local task-branch history.
- Produces: a pushed feature branch and an unmerged pull request with final validation evidence.

- [ ] **Step 1: Present and obtain approval for the final no-op plan mutation**

The contract must authorize one final HCP Terraform plan only, name the exact repository revision and production workspace, require no changes as the success condition, and state that no apply is authorized.

- [ ] **Step 2: Verify final infrastructure and configuration convergence**

Run:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan -input=false -detailed-exitcode
```

Expected: formatting/validation pass and plan exits `0` with no changes. Exit `2` means drift and blocks delivery; exit `1` means error and blocks delivery.

- [ ] **Step 3: Run final production health and storage checks**

Run:

```bash
doctl kubernetes cluster get 600aa401-e809-4179-97c6-dc9444fbaa07 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region,version,status,surge_upgrade,node_pools:[.node_pools[]|{id,name,size,count,nodes:[.nodes[]|{id,name,status}]}]}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get nodes -o json | jq '[.items[] | {name:.metadata.name,ready:([.status.conditions[]|select(.type=="Ready")][0].status),kubelet_version:.status.nodeInfo.kubeletVersion}]'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pvc data-mariadb-0 -n mariadb -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,capacity:.status.capacity.storage,volume_name:.spec.volumeName}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get pv pvc-59a68844-4137-4c30-85e0-5e543a8c62d0 -o json | jq '{name:.metadata.name,uid:.metadata.uid,phase:.status.phase,reclaim_policy:.spec.persistentVolumeReclaimPolicy,volume_handle:.spec.csi.volumeHandle}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get volumeattachments -o json | jq '[.items[] | select(.spec.source.persistentVolumeName == "pvc-59a68844-4137-4c30-85e0-5e543a8c62d0") | {name:.metadata.name,node_name:.spec.nodeName,attached:.status.attached}]'
doctl compute volume get 2b56552e-90a7-11ee-b219-0a58ac145355 --context tars-wp-blogs --config /Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/doctl/config.yaml --output json | jq 'if type == "array" then .[0] else . end | {id,name,region:.region.slug,size_gigabytes,droplet_ids,created_at}'
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs rollout status statefulset/mariadb -n mariadb --timeout=10m
kubectl --kubeconfig=/Users/dbarahona/.kube/configs/do-wp-blogs get statefulsets,deployments -A -o wide
curl -fsS --max-time 20 -o /dev/null -w 'devandops.show %{http_code}\n' https://devandops.show/
curl -fsS --max-time 20 -o /dev/null -w 'douglasbarahona.me %{http_code}\n' https://douglasbarahona.me/
```

Expected: cluster and nodes at `1.36.3-do.0`, unchanged storage identities, Ready MariaDB/workloads, and healthy endpoints.

- [ ] **Step 4: Verify branch scope and scan all changes**

Run:

```bash
git status --porcelain=v1 --branch
git log --oneline --decorate origin/main..HEAD
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
gitleaks git --redact --no-banner --exit-code 1 --log-opts="origin/main..HEAD" .
git remote -v
git config --get user.name
git config --get user.email
```

Expected: only approved design/plan documentation, Terraform/provider/lock/README changes, and sequential DOKS pins; no secrets or unrelated files.

- [ ] **Step 5: Verify no saved plans remain and remove the empty private directory**

Run:

```bash
find /private/tmp/blogs-infrastructure-tfplans-20260730 -mindepth 1 -maxdepth 1 -print
rmdir /private/tmp/blogs-infrastructure-tfplans-20260730
test ! -e /private/tmp/blogs-infrastructure-tfplans-20260730
```

Expected: `find` prints nothing, `rmdir` succeeds, and the directory no longer exists. Stop if any plan remains; do not recursively delete an unexpected artifact.

- [ ] **Step 6: Present and obtain approval for GitHub delivery mutations**

The contract must name:

- Push `feature/upgrade-terraform-provider-doks` to `origin`.
- Create one pull request into `main`.
- No force-push and no merge.
- Local branch commits as the recovery source.
- GitHub's persistent branch/PR records as expected remote side effects.

- [ ] **Step 7: Freshly verify GitHub identity and remote branch state**

Run:

```bash
gh api user --jq '{login:.login,name:.name,email:.email}'
git ls-remote origin refs/heads/main refs/heads/feature/upgrade-terraform-provider-doks
git status --porcelain=v1 --branch
```

Expected: GitHub user `douz`, `origin/main` still based on the expected lineage, no unexpected remote task branch, and clean local branch.

- [ ] **Step 8: Push normally and open the pull request**

Run:

```bash
git push -u origin feature/upgrade-terraform-provider-doks
gh pr create --repo douz/blogs-infrastructure --base main --head feature/upgrade-terraform-provider-doks --title "Upgrade Terraform, DigitalOcean provider, and DOKS" --body "## Summary
- pin Terraform 1.15.8 locally, in configuration, and in HCP Terraform
- update digitalocean/digitalocean to 2.95.0
- upgrade DOKS through supported hops to 1.36.3-do.0
- verify the MariaDB DigitalOcean volume remains unchanged

## Validation
- terraform fmt and validate
- final Terraform plan reports no changes
- Gitleaks reports no findings
- cluster and nodes report 1.36.3-do.0
- MariaDB PVC, PV, CSI volume, and attachment identities are unchanged
- MariaDB and WordPress workloads are Ready
- production endpoints are healthy

This PR has not been merged."
```

Expected: normal push succeeds and GitHub returns a pull-request URL.

- [ ] **Step 9: Report pull-request checks without merging**

Run:

```bash
gh pr view --repo douz/blogs-infrastructure --json number,url,state,headRefName,baseRefName,mergeStateStatus,statusCheckRollup
gh pr checks --repo douz/blogs-infrastructure
```

Expected: open PR from the task branch to `main`. Report checks and stop without merging.
