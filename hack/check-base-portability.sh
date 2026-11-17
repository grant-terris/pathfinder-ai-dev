#!/usr/bin/env bash
# Fails if a Kustomize base contains cloud-provider-specific settings (PLT-9).
# Cloud-specific values belong only in deploy/overlays/<cluster>/.
#
# Usage: hack/check-base-portability.sh [BASE_DIR]   (default: deploy/base)
#
# Vendored upstream add-on manifests (files named upstream.yaml, added in M3) are
# skipped: they're unmodified upstream releases and legitimately mention clouds,
# for example CloudNativePG's azureCredentials backup fields.
set -euo pipefail

base_dir="${1:-deploy/base}"

if [[ ! -d "$base_dir" ]]; then
  echo "check-base-portability: directory not found: $base_dir" >&2
  exit 2
fi

# Cloud-specific markers: provider names, provider annotations, CSI drivers, registries.
pattern='azure|amazonaws\.com|service\.beta\.kubernetes\.io/aws|\bebs\.csi|\beks\b|cloud\.google\.com|\bgke\b|pd\.csi\.storage\.gke|\.azurecr\.io|\.ecr\.|\bgcr\.io|pkg\.dev'

if matches=$(grep -RInEi --include='*.yaml' --include='*.yml' --exclude='upstream.yaml' "$pattern" "$base_dir"); then
  echo "check-base-portability: FAILED: cloud-specific settings found in $base_dir" >&2
  echo "Move them to a patch in deploy/overlays/<cluster>/ (PLT-9):" >&2
  echo "$matches" >&2
  exit 1
fi

echo "check-base-portability: OK ($base_dir has no cloud-specific settings)"
