#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s {zero|recorded}\n' "${0##*/}" >&2
}

fail() {
  printf 'wordpress replica post-renderer: %s\n' "$1" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

mode="$1"
case "$mode" in
  zero | recorded) ;;
  *)
    usage
    exit 2
    ;;
esac

command -v yq >/dev/null 2>&1 || fail "yq is required"

umask 077
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wordpress-replicas.XXXXXX")"
input_file="$work_dir/input.yaml"
output_file="$work_dir/output.yaml"
cleanup() {
  rm -f -- \
    "$work_dir/input.yaml" \
    "$work_dir/output.yaml" \
    "$work_dir"/document.*.yaml
  rmdir "$work_dir"
}
trap cleanup EXIT

cat >"$input_file"
yq ea '.' "$input_file" >/dev/null || fail "input is not valid YAML"

if ! deployment_names="$(
  yq ea --no-doc -r \
    'select(.kind == "Deployment") | .metadata.name' "$input_file" | LC_ALL=C sort
)"; then
  fail "unable to inspect rendered Deployments"
fi

douz_expected="$(printf '%s\n' \
  douz-blogs-wp-wordpress \
  douz-blogs-wp-wordpress-cron \
  douz-blogs-wp-wordpress-services | LC_ALL=C sort)"
devandops_expected="$(printf '%s\n' \
  devandops-wp-wordpress \
  devandops-wp-wordpress-cron \
  devandops-wp-wordpress-services | LC_ALL=C sort)"

case "$deployment_names" in
  "$douz_expected")
    main_deployment=douz-blogs-wp-wordpress
    cron_deployment=douz-blogs-wp-wordpress-cron
    services_deployment=douz-blogs-wp-wordpress-services
    ;;
  "$devandops_expected")
    main_deployment=devandops-wp-wordpress
    cron_deployment=devandops-wp-wordpress-cron
    services_deployment=devandops-wp-wordpress-services
    ;;
  *)
    fail "rendered Deployment set is missing an expected name or contains an unexpected name"
    ;;
esac

if [[ "$mode" == "zero" ]]; then
  main_replicas=0
  cron_replicas=0
  services_replicas=0
else
  main_replicas=2
  cron_replicas=1
  services_replicas=1
fi

awk -v work_dir="$work_dir" '
  BEGIN {
    document_index = -1
    document_file = ""
  }
  /^---([[:space:]]*(#.*)?)?$/ {
    document_index++
    document_file = sprintf("%s/document.%06d.yaml", work_dir, document_index)
  }
  {
    if (document_file == "") {
      document_index = 0
      document_file = sprintf("%s/document.%06d.yaml", work_dir, document_index)
    }
    print $0 > document_file
  }
' "$input_file"

: >"$output_file"
for document_file in "$work_dir"/document.*.yaml; do
  if ! resource_kind="$(yq e -r '.kind // ""' "$document_file")"; then
    fail "unable to inspect a rendered document"
  fi

  if [[ "$resource_kind" != "Deployment" ]]; then
    cat "$document_file" >>"$output_file"
    continue
  fi

  if ! resource_name="$(yq e -r '.metadata.name // ""' "$document_file")"; then
    fail "unable to inspect a rendered Deployment"
  fi

  case "$resource_name" in
    "$main_deployment") desired_replicas="$main_replicas" ;;
    "$cron_deployment") desired_replicas="$cron_replicas" ;;
    "$services_deployment") desired_replicas="$services_replicas" ;;
    *) fail "encountered an unexpected Deployment while rendering" ;;
  esac

  DESIRED_REPLICAS="$desired_replicas" \
    yq e '.spec.replicas = env(DESIRED_REPLICAS)' \
      "$document_file" >>"$output_file"
done

yq ea '.' "$output_file" >/dev/null || fail "rendered output is not valid YAML"
if ! rendered_deployment_names="$(
  yq ea --no-doc -r \
    'select(.kind == "Deployment") | .metadata.name' "$output_file" | LC_ALL=C sort
)"; then
  fail "unable to verify rendered Deployments"
fi
[[ "$rendered_deployment_names" == "$deployment_names" ]] ||
  fail "rendered Deployment set changed unexpectedly"

cat "$output_file"
