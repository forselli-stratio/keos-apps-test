#!/usr/bin/env bash

set -eou pipefail

# mirror kustomize-controller build options
kustomize_flags=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"

# skip Kubernetes Secrets due to SOPS fields failing validation
kubeconform_flags=("-skip=Secret")
kubeconform_config=("-strict" "-ignore-missing-schemas" "-schema-location" "default" "-schema-location" "/tmp/flux-crd-schemas" "-verbose")

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "${ROOT_DIR}"

echo "INFO - Downloading Flux OpenAPI schemas"
mkdir -p /tmp/flux-crd-schemas/master-standalone-strict
curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict

find . -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file; do
  echo "INFO - Validating $file"
  yq e 'true' "$file" >/dev/null
done

echo "INFO - Validating kustomize overlays"
find . -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file; do
  echo "INFO - Validating kustomization ${file/%$kustomize_config/}"

  # Render kustomization, replacing placeholders with defaults for validation
  temp_file=$(mktemp)
  kustomize build "${file/%$kustomize_config/}" "${kustomize_flags[@]}" >"$temp_file"

  # Replace placeholders with defaults
  sed -i 's/${HELM_REGISTRY_TYPE}/default/g' "$temp_file"
  sed -i 's/${HELM_REGISTRY_PROVIDER}/generic/g' "$temp_file"
  sed -i 's#${HELM_REGISTRY_URL}#http://qa.int.stratio.com#g' "$temp_file"
  sed -i 's#${HELM_REGISTRY_REPOSITORY_PREFIX}##g' "$temp_file"

  # Validate the processed YAML
  kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}" <"$temp_file"

  if [[ ${PIPESTATUS[0]} != 0 ]]; then
    exit 1
  fi
done
