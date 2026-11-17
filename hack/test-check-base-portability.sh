#!/usr/bin/env bash
# Self-test for hack/check-base-portability.sh: it must pass a clean base and
# fail one that contains a cloud-specific setting.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$script_dir/check-base-portability.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "test-check-base-portability: FAILED: $*" >&2; exit 1; }

# 1. A clean base passes.
mkdir -p "$tmp/clean"
printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: x\n' > "$tmp/clean/ns.yaml"
"$check" "$tmp/clean" >/dev/null || fail "clean base was rejected"

# 2. Each cloud-specific marker is caught.
cases=(
  'service.beta.kubernetes.io/azure-load-balancer-internal: "true"'
  'provisioner: disk.csi.azure.com'
  'image: myregistry.azurecr.io/pathfinder/orchestrator:1.0'
  'service.beta.kubernetes.io/aws-load-balancer-internal: "true"'
  'provisioner: ebs.csi.aws.com'
  'cloud.google.com/load-balancer-type: Internal'
)
for i in "${!cases[@]}"; do
  d="$tmp/dirty$i"
  mkdir -p "$d"
  printf 'metadata:\n  annotations:\n    %s\n' "${cases[$i]}" > "$d/x.yaml"
  if "$check" "$d" >/dev/null 2>&1; then
    fail "did not catch: ${cases[$i]}"
  fi
done

# 3. Vendored upstream manifests are skipped.
mkdir -p "$tmp/vendored"
printf 'azureCredentials: {}\n' > "$tmp/vendored/upstream.yaml"
"$check" "$tmp/vendored" >/dev/null || fail "vendored upstream.yaml was not skipped"

echo "test-check-base-portability: OK (${#cases[@]} cloud markers caught, clean and vendored bases pass)"
