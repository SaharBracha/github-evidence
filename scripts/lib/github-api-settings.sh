#!/usr/bin/env bash
# Shared GitHub REST API helpers for the settings collectors.
#
# Every request goes through gh_api_get / gh_api_get_paginated, which return a
# small JSON envelope: {"status": <http status>, "ok": <bool>, "body": <json|string>}.
# Collectors turn that envelope into a section record via gh_section_from_result,
# which never treats a 401/403/404 as an empty configuration - it is always
# reported as "unavailable" with the HTTP status and a message.
#
# Requires: curl, jq. Expects GITHUB_TOKEN, GH_OWNER, GH_REPO in the environment.

GH_API_BASE_URL="${GITHUB_API_URL:-https://api.github.com}"
GH_API_VERSION="2022-11-28"

# Recursively strip keys that could carry credential/secret material out of a
# JSON value. This is a defensive net: none of the endpoints we call are
# expected to return secret values, but we never want to accidentally print
# one if GitHub's response shape changes.
gh_redact_json() {
  # Exact key-name match only (case-insensitive) - deliberately narrower than
  # a substring match so that safe plural/container field names GitHub itself
  # uses (e.g. "secrets" listing metadata, "actions_secrets") are not swept up
  # alongside genuinely sensitive singular fields (e.g. "secret", "token").
  jq 'def redact:
        if type == "object" then
          with_entries(
            if (.key | ascii_downcase) as $k
               | ($k | test("^(secret|token|password|private_key|client_secret|authorization|access_token|api_key|refresh_token)$")) then
              .value = "***REDACTED***"
            else
              .value |= redact
            end
          )
        elif type == "array" then
          map(redact)
        else
          .
        end;
      redact'
}

# GET a single page. Prints the response envelope on stdout.
gh_api_get() {
  local path="$1"
  local accept_header="${2:-application/vnd.github+json}"
  local url
  if [[ "$path" == http*://* ]]; then
    url="$path"
  else
    url="${GH_API_BASE_URL}${path}"
  fi

  local response_file status_code
  response_file="$(mktemp)"
  status_code=$(curl -sS -o "$response_file" -w '%{http_code}' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: ${accept_header}" \
    -H "X-GitHub-Api-Version: ${GH_API_VERSION}" \
    "$url" 2>/dev/null) || status_code="000"

  local body
  body="$(cat "$response_file" 2>/dev/null || true)"
  rm -f "$response_file"

  if [[ -z "$body" ]]; then
    jq -n --argjson status "$status_code" \
      '{status: $status, ok: ($status >= 200 and $status < 300), body: null}'
    return 0
  fi

  if printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    jq -n --argjson status "$status_code" --argjson body "$(printf '%s' "$body" | jq -c .)" \
      '{status: $status, ok: ($status >= 200 and $status < 300), body: $body}'
  else
    jq -n --argjson status "$status_code" --arg body "$body" \
      '{status: $status, ok: ($status >= 200 and $status < 300), body: $body}'
  fi
}

# GET all pages of a list endpoint, accumulating items across pages. Stops
# early (marking the result partial) if a later page fails after the first
# page succeeded, so already-collected data is not discarded.
#
# Handles both GitHub list conventions:
#   - a bare JSON array (e.g. collaborators, teams, hooks, branches, rulesets)
#   - a {"total_count": N, "<name>": [...]} wrapper (e.g. environments,
#     Actions variables/secrets, deployment branch policies)
# For wrapped responses, pagination continues until the accumulated item
# count reaches total_count rather than relying on page size, since some of
# these endpoints cap per_page below the 100 we request.
gh_api_get_paginated() {
  local path="$1"
  local accept_header="${2:-application/vnd.github+json}"
  local per_page=100
  local page=1
  local separator="?"
  [[ "$path" == *"?"* ]] && separator="&"

  local all_items="[]"
  local wrapper_key=""
  local wrapper_template="{}"
  local use_total_count="false"

  while true; do
    local result status ok body items count
    result="$(gh_api_get "${path}${separator}per_page=${per_page}&page=${page}" "$accept_header")"
    status="$(printf '%s' "$result" | jq -r '.status')"
    ok="$(printf '%s' "$result" | jq -r '.ok')"

    if [[ "$ok" != "true" ]]; then
      if [[ "$page" -eq 1 ]]; then
        printf '%s' "$result"
        return 0
      fi
      if [[ -n "$wrapper_key" ]]; then
        jq -n --argjson status "$status" --arg key "$wrapper_key" --argjson tmpl "$wrapper_template" --argjson items "$all_items" \
          '{status: $status, ok: false, partial: true, body: ($tmpl + {($key): $items, total_count: ($items | length)})}'
      else
        jq -n --argjson status "$status" --argjson items "$all_items" \
          '{status: $status, ok: false, partial: true, body: $items}'
      fi
      return 0
    fi

    body="$(printf '%s' "$result" | jq -c '.body')"

    if [[ "$page" -eq 1 ]]; then
      if [[ "$(printf '%s' "$body" | jq -r 'type')" == "array" ]]; then
        wrapper_key=""
      else
        wrapper_key="$(printf '%s' "$body" | jq -r '
          if type == "object" then
            ([to_entries[] | select(.value | type == "array") | .key] | .[0]) // ""
          else "" end
        ')"
        if [[ -z "$wrapper_key" ]]; then
          # Not a list endpoint at all (single object) - return as-is.
          printf '%s' "$result"
          return 0
        fi
        wrapper_template="$(printf '%s' "$body" | jq -c --arg k "$wrapper_key" 'del(.[$k])')"
        if printf '%s' "$body" | jq -e 'has("total_count")' >/dev/null 2>&1; then
          use_total_count="true"
        fi
      fi
    fi

    if [[ -n "$wrapper_key" ]]; then
      items="$(printf '%s' "$body" | jq -c --arg k "$wrapper_key" '.[$k]')"
    else
      items="$body"
    fi

    count="$(printf '%s' "$items" | jq 'length')"
    all_items="$(jq -c -n --argjson a "$all_items" --argjson b "$items" '$a + $b')"

    if [[ "$use_total_count" == "true" ]]; then
      local total_count accumulated
      total_count="$(printf '%s' "$body" | jq -r '.total_count')"
      accumulated="$(printf '%s' "$all_items" | jq 'length')"
      if [[ "$count" -eq 0 || "$accumulated" -ge "$total_count" ]]; then
        break
      fi
    else
      if [[ "$count" -lt "$per_page" ]]; then
        break
      fi
    fi
    page=$((page + 1))
  done

  if [[ -n "$wrapper_key" ]]; then
    jq -n --argjson status 200 --arg key "$wrapper_key" --argjson tmpl "$wrapper_template" --argjson items "$all_items" \
      '{status: $status, ok: true, body: ($tmpl + {($key): $items, total_count: ($items | length)})}'
  else
    jq -n --argjson status 200 --argjson items "$all_items" '{status: $status, ok: true, body: $items}'
  fi
}

# Extract a short, safe diagnostic message from a failed envelope.
gh_api_error_message() {
  local result="$1"
  local body_type
  body_type="$(printf '%s' "$result" | jq -r '.body | type')"
  if [[ "$body_type" == "object" ]]; then
    printf '%s' "$result" | jq -r '.body.message // "Request did not succeed."'
  elif [[ "$body_type" == "string" ]]; then
    printf '%s' "$result" | jq -r '.body // "Request did not succeed."' | head -c 300
  else
    echo "Request did not succeed."
  fi
}

# Normalize a gh_api_get/gh_api_get_paginated envelope into a section record:
#   {status: "collected"|"unavailable"|"error", http_status, data?, message?}
# 401/403/404/410 are reported as "unavailable" (token lacks access, or the
# resource does not exist) rather than treated as empty data. Anything else
# unsuccessful is "error".
gh_section_from_result() {
  local result="$1"
  local status ok partial
  status="$(printf '%s' "$result" | jq -r '.status')"
  ok="$(printf '%s' "$result" | jq -r '.ok')"
  partial="$(printf '%s' "$result" | jq -r '.partial // false')"

  if [[ "$partial" == "true" ]]; then
    local data
    data="$(printf '%s' "$result" | jq -c '.body' | gh_redact_json)"
    jq -n --argjson http_status "$status" --argjson data "$data" \
      '{status: "collected", partial: true, http_status: $http_status, data: $data,
        message: "Pagination stopped early after a non-success response; data may be incomplete."}'
    return 0
  fi

  if [[ "$ok" == "true" ]]; then
    local data
    data="$(printf '%s' "$result" | jq -c '.body' | gh_redact_json)"
    jq -n --argjson http_status "$status" --argjson data "$data" \
      '{status: "collected", http_status: $http_status, data: $data}'
    return 0
  fi

  local message
  message="$(gh_api_error_message "$result")"
  case "$status" in
    401|403|404|410)
      jq -n --argjson http_status "$status" --arg message "$message" \
        '{status: "unavailable", http_status: $http_status, message: $message}'
      ;;
    *)
      jq -n --argjson http_status "$status" --arg message "$message" \
        '{status: "error", http_status: $http_status, message: $message}'
      ;;
  esac
}

# Convenience: run gh_api_get then immediately normalize into a section record.
gh_section_get() {
  gh_section_from_result "$(gh_api_get "$1" "${2:-application/vnd.github+json}")"
}

# Convenience: run gh_api_get_paginated then immediately normalize into a section record.
gh_section_get_paginated() {
  gh_section_from_result "$(gh_api_get_paginated "$1" "${2:-application/vnd.github+json}")"
}
