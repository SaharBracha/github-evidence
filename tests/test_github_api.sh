#!/usr/bin/env bash
# Unit tests for scripts/github-api.sh: redaction, section normalization, and
# pagination (bare-array, total_count-wrapped, and partial-failure) behavior.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"
# shellcheck source=../scripts/lib/github-api-settings.sh
source "${REPO_ROOT}/scripts/lib/github-api-settings.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GITHUB_TOKEN="test-token"

test_redact_strips_nested_secret_like_keys() {
  local input redacted
  input='{"config":{"url":"https://example.com","secret":"abc123"},"token":"xyz","key":"ssh-rsa AAAA","encrypted_value":"ZW5j","nested":[{"password":"p1"},{"safe":"keep-me"}]}'
  redacted="$(printf '%s' "$input" | gh_redact_json)"
  assert_equal "***REDACTED***" "$(printf '%s' "$redacted" | jq -r '.config.secret')" "config.secret should be redacted" || return 1
  assert_equal "***REDACTED***" "$(printf '%s' "$redacted" | jq -r '.token')" "top-level token should be redacted" || return 1
  assert_equal "***REDACTED***" "$(printf '%s' "$redacted" | jq -r '.key')" "deploy-key material (key) should be redacted" || return 1
  assert_equal "***REDACTED***" "$(printf '%s' "$redacted" | jq -r '.encrypted_value')" "encrypted secret payloads should be redacted" || return 1
  assert_equal "***REDACTED***" "$(printf '%s' "$redacted" | jq -r '.nested[0].password')" "nested password should be redacted" || return 1
  assert_equal "keep-me" "$(printf '%s' "$redacted" | jq -r '.nested[1].safe')" "unrelated fields must survive redaction" || return 1
  assert_equal "https://example.com" "$(printf '%s' "$redacted" | jq -r '.config.url')" "non-secret fields (incl. webhook config.url) must survive redaction"
}

test_section_from_result_success() {
  local envelope section
  envelope='{"status":200,"ok":true,"body":{"hello":"world"}}'
  section="$(gh_section_from_result "$envelope")"
  assert_equal "collected" "$(printf '%s' "$section" | jq -r '.status')" "200 should map to collected" || return 1
  assert_equal "world" "$(printf '%s' "$section" | jq -r '.data.hello')" "data should carry the body through"
}

test_section_from_result_not_found_is_unavailable() {
  local envelope section
  envelope='{"status":404,"ok":false,"body":{"message":"Not Found"}}'
  section="$(gh_section_from_result "$envelope")"
  assert_equal "unavailable" "$(printf '%s' "$section" | jq -r '.status')" "404 must be reported as unavailable, not empty data" || return 1
  assert_equal "Not Found" "$(printf '%s' "$section" | jq -r '.message')" "message should surface GitHub's error text"
}

test_section_from_result_forbidden_is_unavailable() {
  local envelope section
  envelope='{"status":403,"ok":false,"body":{"message":"Resource not accessible by integration"}}'
  section="$(gh_section_from_result "$envelope")"
  assert_equal "unavailable" "$(printf '%s' "$section" | jq -r '.status')" "403 must be reported as unavailable"
}

test_section_from_result_server_error_is_error() {
  local envelope section
  envelope='{"status":500,"ok":false,"body":{"message":"Internal Server Error"}}'
  section="$(gh_section_from_result "$envelope")"
  assert_equal "error" "$(printf '%s' "$section" | jq -r '.status')" "500 must be reported as error, distinct from unavailable"
}

test_pagination_accumulates_bare_array_across_pages() {
  local result section
  export MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pagination-bare-array.json"
  result="$(gh_api_get_paginated "/repos/acme/widget/collaborators")"
  section="$(gh_section_from_result "$result")"
  assert_equal "collected" "$(printf '%s' "$section" | jq -r '.status')" "paginated bare-array fetch should be collected" || return 1
  assert_equal "105" "$(printf '%s' "$section" | jq -r '.data | length')" "should accumulate both pages (100 + 5 = 105 items)"
}

test_pagination_follows_total_count_for_wrapped_endpoints() {
  local result section
  export MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pagination-wrapped.json"
  result="$(gh_api_get_paginated "/repos/acme/widget/actions/variables")"
  section="$(gh_section_from_result "$result")"
  assert_equal "collected" "$(printf '%s' "$section" | jq -r '.status')" "wrapped paginated fetch should be collected" || return 1
  assert_equal "45" "$(printf '%s' "$section" | jq -r '.data.variables | length')" "should continue past a short first page using total_count, not per_page"
}

test_pagination_partial_failure_keeps_first_page_data() {
  local result section
  export MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pagination-partial-failure.json"
  result="$(gh_api_get_paginated "/repos/acme/widget/collaborators")"
  section="$(gh_section_from_result "$result")"
  assert_equal "collected" "$(printf '%s' "$section" | jq -r '.status')" "a later-page failure should not discard earlier successful pages" || return 1
  assert_equal "true" "$(printf '%s' "$section" | jq -r '.partial')" "result must be flagged partial" || return 1
  assert_equal "100" "$(printf '%s' "$section" | jq -r '.data | length')" "should keep the 100 items collected before the failure"
}

run_test test_redact_strips_nested_secret_like_keys
run_test test_section_from_result_success
run_test test_section_from_result_not_found_is_unavailable
run_test test_section_from_result_forbidden_is_unavailable
run_test test_section_from_result_server_error_is_error
run_test test_pagination_accumulates_bare_array_across_pages
run_test test_pagination_follows_total_count_for_wrapped_endpoints
run_test test_pagination_partial_failure_keeps_first_page_data

report_results
