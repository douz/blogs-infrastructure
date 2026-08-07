#!/usr/bin/env bash
#
# Validate the production Argo CD GitOps foundation without contacting the
# Kubernetes API or changing persistent Helm configuration.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly KUBECTL_BIN="${KUBECTL_BIN:-/Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/bin/kubectl-1.36.3}"
readonly HELM3_BIN="${HELM3_BIN:-/usr/local/bin/helm}"
readonly HELM4_BIN="${HELM4_BIN:-/Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/bin/helm-4.2.1}"
readonly KUBECONFORM_BIN="${KUBECONFORM_BIN:-/Users/dbarahona/Sites/ai/tars/projects/blogs-infrastructure/credentials/bin/kubeconform-0.7.0}"
readonly YQ_BIN="${YQ_BIN:-/usr/local/bin/yq}"
readonly JQ_BIN="${JQ_BIN:-/usr/local/bin/jq}"
readonly GREP_BIN="${GREP_BIN:-/usr/bin/grep}"

render_dir=""

usage() {
  cat <<'EOF'
Usage: scripts/validate-gitops.sh

Validates the production Argo CD bootstrap, stateless service definitions,
render parity, schemas, secret boundaries, and WordPress exclusion.

Tool paths may be overridden explicitly with:
  KUBECTL_BIN, HELM3_BIN, HELM4_BIN, KUBECONFORM_BIN, YQ_BIN, JQ_BIN, GREP_BIN
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local exit_code=$?

  if [[ -n "${render_dir}" ]]; then
    case "${render_dir}" in
      "${TMPDIR:-/tmp}"/blogs-gitops-validation.*)
        rm -r "${render_dir}"
        ;;
      *)
        printf 'Refusing to remove unexpected temporary path: %s\n' "${render_dir}" >&2
        exit 1
        ;;
    esac
  fi

  return "${exit_code}"
}

require_executable() {
  local path="$1"
  local label="$2"

  [[ -x "${path}" ]] || die "${label} is not executable at ${path}"
}

check_tools() {
  require_executable "${KUBECTL_BIN}" kubectl
  require_executable "${HELM3_BIN}" "Helm 3"
  require_executable "${HELM4_BIN}" "Helm 4"
  require_executable "${KUBECONFORM_BIN}" kubeconform
  require_executable "${YQ_BIN}" yq
  require_executable "${JQ_BIN}" jq
  require_executable "${GREP_BIN}" grep

  "${KUBECTL_BIN}" version --client -o json |
    "${JQ_BIN}" -e '.clientVersion.gitVersion == "v1.36.3" and .kustomizeVersion == "v5.8.1"' >/dev/null
  "${HELM3_BIN}" version --short | "${GREP_BIN}" -E -q '^v3\.13\.2\+'
  "${HELM4_BIN}" version --short | "${GREP_BIN}" -E -q '^v4\.2\.1\+'
  "${KUBECONFORM_BIN}" -v | "${GREP_BIN}" -E -q '^v0\.7\.0$'
  "${YQ_BIN}" --version | "${GREP_BIN}" -E -q ' version v4\.'
  "${JQ_BIN}" --version | "${GREP_BIN}" -E -q '^jq-'
}

helm_with_home() {
  local binary="$1"
  local home="$2"
  shift 2

  HELM_CONFIG_HOME="${home}" \
    HELM_CACHE_HOME="${home}" \
    HELM_DATA_HOME="${home}" \
    "${binary}" "$@"
}

configure_helm_repositories() {
  local binary="$1"
  local home="$2"

  helm_with_home "${binary}" "${home}" repo add sealed-secrets https://bitnami.github.io/sealed-secrets
  helm_with_home "${binary}" "${home}" repo add jetstack https://charts.jetstack.io
  helm_with_home "${binary}" "${home}" repo add bitnami https://charts.bitnami.com/bitnami
  helm_with_home "${binary}" "${home}" repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
}

render_kustomizations() {
  "${KUBECTL_BIN}" kustomize clusters/prod/bootstrap/argocd >"${render_dir}/bootstrap.yaml"
  "${KUBECTL_BIN}" kustomize clusters/prod/control-plane >"${render_dir}/control-plane.yaml"
  "${KUBECTL_BIN}" kustomize clusters/prod/platform/argocd >"${render_dir}/argocd.yaml"
  "${KUBECTL_BIN}" kustomize clusters/prod/platform/certificate-config >"${render_dir}/certificate-config.yaml"
  "${KUBECTL_BIN}" kustomize clusters/prod/platform/external-dns >"${render_dir}/external-dns-config.yaml"
}

render_helm_charts() {
  local binary="$1"
  local home="$2"
  local suffix="$3"

  helm_with_home "${binary}" "${home}" template sealed-secrets sealed-secrets/sealed-secrets \
    --version 2.15.0 \
    --namespace kube-system \
    --values clusters/prod/platform/sealed-secrets/values.yaml \
    >"${render_dir}/sealed-secrets-${suffix}.yaml"
  helm_with_home "${binary}" "${home}" template cert-manager jetstack/cert-manager \
    --version v1.13.2 \
    --namespace cert-manager \
    --values clusters/prod/platform/cert-manager/values.yaml \
    >"${render_dir}/cert-manager-${suffix}.yaml"
  helm_with_home "${binary}" "${home}" template external-dns bitnami/external-dns \
    --version 9.0.3 \
    --namespace external-dns \
    --values clusters/prod/platform/external-dns/values.yaml \
    >"${render_dir}/external-dns-${suffix}.yaml"
  helm_with_home "${binary}" "${home}" template ingress-nginx ingress-nginx/ingress-nginx \
    --version 4.12.1 \
    --namespace ingress-nginx \
    --values clusters/prod/platform/ingress-nginx/values.yaml \
    >"${render_dir}/ingress-nginx-${suffix}.yaml"
}

normalize_yaml() {
  local source_file="$1"
  local output_file="$2"

  "${YQ_BIN}" eval-all -o=json -I=0 \
    'select(.apiVersion != null and .kind != null and .metadata.name != null)' \
    "${source_file}" |
    "${JQ_BIN}" -S -c . |
    "${JQ_BIN}" -s 'sort_by([.apiVersion, .kind, (.metadata.namespace // ""), .metadata.name])' \
      >"${output_file}"
}

compare_helm_engines() {
  local chart

  for chart in sealed-secrets cert-manager external-dns ingress-nginx; do
    normalize_yaml "${render_dir}/${chart}-helm3.yaml" "${render_dir}/${chart}-helm3.json"
    normalize_yaml "${render_dir}/${chart}-helm4.yaml" "${render_dir}/${chart}-helm4.json"
    diff -u "${render_dir}/${chart}-helm3.json" "${render_dir}/${chart}-helm4.json"
  done
}

validate_schemas() {
  local manifest

  for manifest in \
    "${render_dir}/bootstrap.yaml" \
    "${render_dir}/control-plane.yaml" \
    "${render_dir}/argocd.yaml" \
    "${render_dir}/certificate-config.yaml" \
    "${render_dir}/external-dns-config.yaml" \
    "${render_dir}/sealed-secrets-helm3.yaml" \
    "${render_dir}/cert-manager-helm3.yaml" \
    "${render_dir}/external-dns-helm3.yaml" \
    "${render_dir}/ingress-nginx-helm3.yaml"; do
    "${KUBECONFORM_BIN}" -strict -summary -ignore-missing-schemas "${manifest}"
  done
}

validate_unique_identities() {
  local identities_file="${render_dir}/managed-identities.tsv"
  local duplicates_file="${render_dir}/duplicate-identities.tsv"
  local -a managed_renders=(
    "${render_dir}/control-plane.yaml"
    "${render_dir}/argocd.yaml"
    "${render_dir}/certificate-config.yaml"
    "${render_dir}/external-dns-config.yaml"
    "${render_dir}/sealed-secrets-helm3.yaml"
    "${render_dir}/cert-manager-helm3.yaml"
    "${render_dir}/external-dns-helm3.yaml"
    "${render_dir}/ingress-nginx-helm3.yaml"
  )

  "${YQ_BIN}" eval-all -r -N \
    'select(.apiVersion != null and .kind != null and .metadata.name != null) |
      [.apiVersion, .kind, (.metadata.namespace // ""), .metadata.name] | @tsv' \
    "${managed_renders[@]}" |
    sort >"${identities_file}"
  uniq -d "${identities_file}" >"${duplicates_file}"
  [[ ! -s "${duplicates_file}" ]] || die "Duplicate managed resource identities detected"
}

validate_applicationset() {
  local actual_file="${render_dir}/applicationset-elements.txt"
  local expected_file="${render_dir}/applicationset-elements.expected"

  "${YQ_BIN}" -r '.spec.generators[].list.elements[].name' \
    clusters/prod/control-plane/platform-applicationset.yaml |
    sort >"${actual_file}"
  printf '%s\n' cert-manager external-dns ingress-nginx sealed-secrets >"${expected_file}"
  diff -u "${expected_file}" "${actual_file}"
  "${YQ_BIN}" -e '.spec.syncPolicy.preserveResourcesOnDeletion == true' \
    clusters/prod/control-plane/platform-applicationset.yaml >/dev/null
  "${YQ_BIN}" -e '.spec.template.spec.syncPolicy.automated == null' \
    clusters/prod/control-plane/platform-applicationset.yaml >/dev/null
}

validate_repo_server_safety() {
  local cmd_params_file="clusters/prod/bootstrap/argocd/config-patches/argocd-cmd-params-cm.yaml"
  local workload_resources_file="clusters/prod/bootstrap/argocd/config-patches/workload-resources.yaml"
  local repo_server_memory_limit

  "${YQ_BIN}" -e '.data."reposerver.parallelism.limit" == "1"' \
    "${cmd_params_file}" >/dev/null ||
    die "Argo CD repo-server parallelism must be limited to one manifest generation"

  repo_server_memory_limit=$(
    "${YQ_BIN}" eval-all -r '
      select(.kind == "Deployment" and .metadata.name == "argocd-repo-server") |
      .spec.template.spec.containers[] |
      select(.name == "argocd-repo-server") |
      .resources.limits.memory
    ' "${workload_resources_file}"
  )
  [[ "${repo_server_memory_limit}" == "768Mi" ]] ||
    die "Argo CD repo-server memory limit must be 768Mi"

  "${YQ_BIN}" eval-all -e '
    select(.kind == "Deployment" and .metadata.name == "argocd-repo-server") |
    .spec.strategy.type == "RollingUpdate" and
    .spec.strategy.rollingUpdate.maxSurge == 0 and
    .spec.strategy.rollingUpdate.maxUnavailable == 1
  ' "${workload_resources_file}" >/dev/null ||
    die "Argo CD repo-server rollout must avoid surge and allow one unavailable replica"
}

validate_scope_boundaries() {
  local -a managed_paths=(
    clusters/prod/bootstrap
    clusters/prod/control-plane
    clusters/prod/platform
  )

  if "${GREP_BIN}" -R -n -E \
    'wordpress|devandops-prod|douz-blogs-wp|devandops-wp' \
    "${managed_paths[@]}"; then
    die "WordPress ownership appeared in an Argo-managed path"
  fi

  if "${GREP_BIN}" -R -n -E \
    'automated:|prune:[[:space:]]*true|selfHeal:[[:space:]]*true|Force=true|Replace=true' \
    "${managed_paths[@]}"; then
    die "Unsafe automatic or destructive sync configuration detected"
  fi
}

validate_server_side_apply_exception() {
  local exception_file="clusters/prod/bootstrap/argocd/config-patches/applicationset-crd-ssa.yaml"
  local applicationset_crd_count
  local exception_document_count
  local source_ssa_count
  local rendered_targets
  local -a managed_paths=(
    clusters/prod/bootstrap
    clusters/prod/control-plane
    clusters/prod/platform
  )

  [[ -f "${exception_file}" ]] || die "Required ApplicationSet CRD SSA exception is missing"

  exception_document_count=$(
    "${YQ_BIN}" -r -N '"document"' "${exception_file}" |
      /usr/bin/awk 'END { print NR }'
  )
  [[ "${exception_document_count}" == "1" ]] ||
    die "ApplicationSet CRD SSA patch must contain exactly one YAML document; found ${exception_document_count}"

  "${YQ_BIN}" -e '
    .apiVersion == "apiextensions.k8s.io/v1" and
    .kind == "CustomResourceDefinition" and
    .metadata.name == "applicationsets.argoproj.io" and
    .metadata.annotations."argocd.argoproj.io/sync-options" == "ServerSideApply=true" and
    ((keys | sort | join(",")) == "apiVersion,kind,metadata") and
    ((.metadata | keys | sort | join(",")) == "annotations,name") and
    ((.metadata.annotations | keys | join(",")) == "argocd.argoproj.io/sync-options")
  ' "${exception_file}" >/dev/null || die "ApplicationSet CRD SSA patch has unexpected content"

  source_ssa_count=$(
    {
      "${GREP_BIN}" -R -h -o -F 'ServerSideApply=true' "${managed_paths[@]}" || true
    } | /usr/bin/awk 'END { print NR }'
  )
  [[ "${source_ssa_count}" == "1" ]] ||
    die "Expected exactly one source SSA exception; found ${source_ssa_count}"

  applicationset_crd_count=$(
    "${YQ_BIN}" eval-all -r -N '
      select(
        .kind == "CustomResourceDefinition" and
        .metadata.name == "applicationsets.argoproj.io"
      ) |
      .metadata.name
    ' "${render_dir}/bootstrap.yaml" | /usr/bin/awk 'END { print NR }'
  )
  [[ "${applicationset_crd_count}" == "1" ]] ||
    die "Expected exactly one rendered ApplicationSet CRD; found ${applicationset_crd_count}"

  rendered_targets=$(
    "${YQ_BIN}" eval-all -r -N '
      select(.metadata.annotations."argocd.argoproj.io/sync-options" == "ServerSideApply=true") |
      [.apiVersion, .kind, (.metadata.namespace // ""), .metadata.name] | @tsv
    ' "${render_dir}/bootstrap.yaml"
  )
  [[ "${rendered_targets}" == $'apiextensions.k8s.io/v1\tCustomResourceDefinition\t\tapplicationsets.argoproj.io' ]] ||
    die "SSA exception rendered on an unexpected resource: ${rendered_targets:-none}"
}

validate_repository_access() {
  local application
  local -a direct_applications=(
    clusters/prod/bootstrap/argocd/root-application.yaml
    clusters/prod/control-plane/argocd-application.yaml
    clusters/prod/control-plane/certificate-config-application.yaml
    clusters/prod/control-plane/external-dns-config-application.yaml
  )
  local -a managed_paths=(
    clusters/prod/bootstrap
    clusters/prod/control-plane
    clusters/prod/platform
  )

  for application in "${direct_applications[@]}"; do
    "${YQ_BIN}" -e \
      '.spec.source.repoURL == "https://github.com/douz/blogs-infrastructure.git"' \
      "${application}" >/dev/null
  done

  "${YQ_BIN}" -e \
    '.spec.sourceRepos[] | select(. == "https://github.com/douz/blogs-infrastructure.git")' \
    clusters/prod/control-plane/project.yaml >/dev/null
  "${YQ_BIN}" -e \
    '.spec.template.spec.sources[] | select(.repoURL == "https://github.com/douz/blogs-infrastructure.git")' \
    clusters/prod/control-plane/platform-applicationset.yaml >/dev/null

  if "${GREP_BIN}" -R -n -E \
    'git@github\.com:douz/blogs-infrastructure\.git|repo-blogs-infrastructure|repository-sealedsecret|argocd\.argoproj\.io/secret-type' \
    "${managed_paths[@]}"; then
    die "SSH repository access or an unnecessary repository credential appeared in managed paths"
  fi
}

validate_secret_boundaries() {
  local rendered_secret_violations
  local rendered_secret_patch_targets
  local sealed_secret_violations
  local account_sealed_secret="clusters/prod/bootstrap/argocd/local-accounts-sealedsecret.yaml"
  local account_secret_patch="clusters/prod/bootstrap/argocd/config-patches/argocd-secret-patch.yaml"

  [[ -f "${account_secret_patch}" ]] ||
    die "Required argocd-secret Secret patch is missing"

  "${YQ_BIN}" -e '
    .apiVersion == "v1" and
    .kind == "Secret" and
    .metadata.name == "argocd-secret" and
    .metadata.annotations."sealedsecrets.bitnami.com/patch" == "true" and
    ((keys | sort | join(",")) == "apiVersion,kind,metadata") and
    ((.metadata | keys | sort | join(",")) == "annotations,name") and
    ((.metadata.annotations | keys | join(",")) == "sealedsecrets.bitnami.com/patch")
  ' "${account_secret_patch}" >/dev/null ||
    die "argocd-secret Secret patch has unexpected content"

  "${YQ_BIN}" -e '
    .apiVersion == "bitnami.com/v1alpha1" and
    .kind == "SealedSecret" and
    .metadata.name == "argocd-secret" and
    .metadata.namespace == "argocd" and
    .metadata.annotations."sealedsecrets.bitnami.com/patch" == null and
    .spec.template.metadata.annotations."sealedsecrets.bitnami.com/patch" == "true"
  ' "${account_sealed_secret}" >/dev/null ||
    die "argocd-secret SealedSecret must place patch annotation on generated Secret template"

  rendered_secret_patch_targets=$(
    "${YQ_BIN}" eval-all -r -N '
      select(.metadata.annotations."sealedsecrets.bitnami.com/patch" == "true") |
      [.apiVersion, .kind, (.metadata.namespace // ""), .metadata.name] | @tsv
    ' "${render_dir}/bootstrap.yaml"
  )
  [[ "${rendered_secret_patch_targets}" == $'v1\tSecret\targocd\targocd-secret' ]] ||
    die "Patch annotation rendered on an unexpected Secret target: ${rendered_secret_patch_targets:-none}"

  rendered_secret_violations=$(
    "${YQ_BIN}" eval-all -r -N \
      'select(.kind == "Secret") |
       select(((.data // {}) | length) > 0 or ((.stringData // {}) | length) > 0) |
       (.metadata.namespace // "") + "/" + .metadata.name' \
      "${render_dir}"/*.yaml
  )
  [[ -z "${rendered_secret_violations}" ]] ||
    die "Rendered Secret contains plaintext data fields: ${rendered_secret_violations}"

  sealed_secret_violations=$(
    "${YQ_BIN}" eval-all -r -N \
      'select(.kind == "SealedSecret") |
       select(
         has("data") or has("stringData") or
         .spec.template.data != null or .spec.template.stringData != null
       ) |
       (.metadata.namespace // "") + "/" + .metadata.name' \
      clusters/prod/bootstrap/argocd/*.yaml \
      clusters/prod/platform/external-dns/*.yaml
  )
  [[ -z "${sealed_secret_violations}" ]] ||
    die "SealedSecret contains plaintext data or stringData fields"
}

validate_preserved_sources() {
  local source_hash
  local copied_hash
  local legacy_file

  source_hash=$(shasum -a 256 global-services/cloudflare-sealedsecret.yaml | awk '{print $1}')
  copied_hash=$(shasum -a 256 clusters/prod/platform/external-dns/cloudflare-sealedsecret.yaml | awk '{print $1}')
  [[ "${source_hash}" == "${copied_hash}" ]] || die "external-dns SealedSecret copy differs from its source"

  while IFS= read -r legacy_file; do
    git ls-files --error-unmatch "${legacy_file}" >/dev/null
  done < <(git ls-tree -r --name-only origin/main -- clusters/prod/flux-system clusters/prod/infra)

  if git diff --name-only --diff-filter=D origin/main -- clusters/prod/flux-system clusters/prod/infra |
    "${GREP_BIN}" -q '.'; then
    die "A legacy Flux or infra file was deleted"
  fi
}

main() {
  if [[ ${#} -gt 0 ]]; then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage >&2
        die "Unexpected argument: $1"
        ;;
    esac
  fi

  check_tools
  cd "${REPO_ROOT}"

  validate_repo_server_safety

  render_dir=$(mktemp -d "${TMPDIR:-/tmp}/blogs-gitops-validation.XXXXXX")
  mkdir -p "${render_dir}/helm3" "${render_dir}/helm4"

  configure_helm_repositories "${HELM3_BIN}" "${render_dir}/helm3"
  configure_helm_repositories "${HELM4_BIN}" "${render_dir}/helm4"
  render_kustomizations
  render_helm_charts "${HELM3_BIN}" "${render_dir}/helm3" helm3
  render_helm_charts "${HELM4_BIN}" "${render_dir}/helm4" helm4

  compare_helm_engines
  validate_schemas
  validate_unique_identities
  validate_applicationset
  validate_scope_boundaries
  validate_server_side_apply_exception
  validate_repository_access
  validate_secret_boundaries
  validate_preserved_sources

  printf 'GitOps validation passed.\n'
}

trap cleanup EXIT
main "$@"
