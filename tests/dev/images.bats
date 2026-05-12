#!/usr/bin/env bats
# Registry regression tests for remote devcontainer artifacts.

load 'test_helper'

OCI_MANIFEST_ACCEPT='application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'

manifest_url_for_oci_ref() {
  local ref="$1"

  [[ "$ref" == */*:* ]] || return 1

  local registry="${ref%%/*}"
  local repo_tag="${ref#*/}"
  local repo="${repo_tag%:*}"
  local tag="${repo_tag##*:}"

  [[ -n "$repo" && -n "$tag" && "$repo" != "$repo_tag" ]] || return 1
  printf 'https://%s/v2/%s/manifests/%s' "$registry" "$repo" "$tag"
}

manifest_status_code() {
  local url="$1"
  local token="$2"
  local headers="$3"
  local -a auth_header=()

  if [[ -n "$token" ]]; then
    auth_header=(-H "Authorization: Bearer ${token}")
  fi

  curl -sSIL \
    --connect-timeout 10 \
    --max-time 30 \
    -D "$headers" \
    -o /dev/null \
    -w '%{http_code}' \
    -H "Accept: ${OCI_MANIFEST_ACCEPT}" \
    "${auth_header[@]}" \
    "$url" || true
}

bearer_token_from_challenge() {
  local headers="$1"
  local challenge realm service scope

  challenge="$(grep -i '^www-authenticate:' "$headers" | head -1 | tr -d '\r')"
  realm="$(echo "$challenge" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')"
  service="$(echo "$challenge" | sed -n 's/.*service="\([^"]*\)".*/\1/p')"
  scope="$(echo "$challenge" | sed -n 's/.*scope="\([^"]*\)".*/\1/p')"

  [[ -n "$realm" && -n "$service" && -n "$scope" ]] || return 1

  curl -fsSL \
    --connect-timeout 10 \
    --max-time 30 \
    -G \
    --data-urlencode "service=${service}" \
    --data-urlencode "scope=${scope}" \
    "$realm" | jq -r '.token // empty'
}

manifest_exists() {
  local url="$1"
  local attempt headers status token

  for attempt in 1 2 3; do
    headers="$(mktemp)"
    status="$(manifest_status_code "$url" "" "$headers")"

    if [[ "$status" == "200" ]]; then
      rm -f "$headers"
      return 0
    fi

    if [[ "$status" == "401" ]]; then
      token="$(bearer_token_from_challenge "$headers" || true)"
      if [[ -n "$token" ]]; then
        status="$(manifest_status_code "$url" "$token" "$headers")"
        if [[ "$status" == "200" ]]; then
          rm -f "$headers"
          return 0
        fi
      fi
    fi

    rm -f "$headers"
    sleep 1
  done

  return 1
}

@test "all stack base images have published registry manifests" {
  command -v curl >/dev/null 2>&1 || skip "curl not installed"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  local stack_file image url
  local -a failures=()

  while IFS= read -r stack_file; do
    image="$(jq -r '.image // empty' "$stack_file")"
    [[ -n "$image" ]] || continue

    if ! url="$(manifest_url_for_oci_ref "$image")"; then
      failures+=("$(basename "$stack_file"): unsupported image reference: ${image}")
      continue
    fi

    if ! manifest_exists "$url"; then
      failures+=("$(basename "$stack_file"): missing manifest: ${image}")
    fi
  done < <(find "$TEMPLATES/stacks" -type f -name '*.json' | sort)

  if (( ${#failures[@]} > 0 )); then
    printf 'Image manifest validation failed:\n' >&2
    printf '  - %s\n' "${failures[@]}" >&2
    return 1
  fi
}

@test "all referenced devcontainer features have published registry manifests" {
  command -v curl >/dev/null 2>&1 || skip "curl not installed"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  local template_file feature url
  local -a failures=()

  while IFS= read -r template_file; do
    while IFS= read -r feature; do
      [[ -n "$feature" ]] || continue

      if ! url="$(manifest_url_for_oci_ref "$feature")"; then
        failures+=("$(basename "$template_file"): unsupported feature reference: ${feature}")
        continue
      fi

      if ! manifest_exists "$url"; then
        failures+=("$(basename "$template_file"): missing manifest: ${feature}")
      fi
    done < <(jq -r '(.features // {}) | keys[]' "$template_file")
  done < <(find "$TEMPLATES" -type f -name '*.json' | sort)

  if (( ${#failures[@]} > 0 )); then
    printf 'Feature manifest validation failed:\n' >&2
    printf '  - %s\n' "${failures[@]}" >&2
    return 1
  fi
}
