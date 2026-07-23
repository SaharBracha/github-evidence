#!/usr/bin/env bash

github_api_get() {
  local url="$1"
  local body_file
  body_file=$(mktemp)
  local http_code

  http_code=$(curl -sS -o "$body_file" -w "%{http_code}" \
    -H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN is required}" \
    -H "Accept: application/vnd.github+json" \
    "$url")

  if [[ "$http_code" != "200" ]]; then
    echo "::error::GET ${url} returned HTTP ${http_code}" >&2
    cat "$body_file" >&2
    rm -f "$body_file"
    exit 1
  fi

  cat "$body_file"
  rm -f "$body_file"
}

github_api_get_page() {
  local url="$1"
  local headers_file="$2"
  local body_file="$3"
  local http_code

  http_code=$(curl -sS -D "$headers_file" -o "$body_file" -w "%{http_code}" \
    -H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN is required}" \
    -H "Accept: application/vnd.github+json" \
    "$url")

  if [[ "$http_code" != "200" ]]; then
    echo "::error::GET ${url} returned HTTP ${http_code}" >&2
    cat "$body_file" >&2
    rm -f "$headers_file" "$body_file"
    exit 1
  fi
}

github_api_get_json_array_paginated() {
  local url="$1"
  local result="[]"

  while :; do
    local headers_file
    local body_file
    headers_file=$(mktemp)
    body_file=$(mktemp)

    github_api_get_page "$url" "$headers_file" "$body_file"

    result=$(jq -n --argjson a "$result" --argjson b "$(jq '.' "$body_file")" '$a + $b')

    local next_url
    next_url=$(
      grep -i '^link:' "$headers_file" \
        | tr ',' '\n' \
        | sed -n 's/.*<\([^>]*\)>; rel="next".*/\1/p' \
        | sed -n '1p' \
        || true
    )

    rm -f "$headers_file" "$body_file"

    if [[ -z "$next_url" ]]; then
      break
    fi

    url="$next_url"
  done

  echo "$result"
}
