#!/usr/bin/env bash
# Tests for scripts/collect-codeowners.sh against fixture-driven mock responses.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GITHUB_TOKEN="test-token"
export GH_OWNER="acme"
export GH_REPO="widget"

collect_codeowners() {
  MOCK_CURL_FIXTURE="$1" "${REPO_ROOT}/scripts/collect-codeowners.sh"
}

test_finds_github_codeowners_and_parses_rules() {
  local output
  output="$(collect_codeowners "${TESTS_DIR}/fixtures/full-success.json")"
  assert_valid_json "$output" "collector must print valid JSON" || return 1
  assert_equal ".github/CODEOWNERS" "$(printf '%s' "$output" | jq -r '.resolved_path')" "should resolve .github/CODEOWNERS first" || return 1
  assert_equal "collected" "$(printf '%s' "$output" | jq -r '.file.status')" "file section should be collected" || return 1
  assert_equal "2" "$(printf '%s' "$output" | jq -r '.owner_rules | length')" "comment and blank lines must be skipped, leaving 2 rules" || return 1
  assert_equal "*.js" "$(printf '%s' "$output" | jq -r '.owner_rules[0].pattern')" "first rule pattern should be *.js" || return 1
  assert_json_equal '["@frontend-team"]' "$(printf '%s' "$output" | jq -c '.owner_rules[0].owners')" "first rule owners" || return 1
  assert_json_equal '["@doc-writer","@acme/docs-team"]' "$(printf '%s' "$output" | jq -c '.owner_rules[1].owners')" "second rule should keep both a user and a team owner"
}

test_reports_missing_codeowners_as_unavailable_not_empty() {
  local output
  output="$(collect_codeowners "${TESTS_DIR}/fixtures/no-codeowners.json")"
  assert_equal "null" "$(printf '%s' "$output" | jq -r '.resolved_path')" "resolved_path must be null when no file is found" || return 1
  assert_equal "unavailable" "$(printf '%s' "$output" | jq -r '.file.status')" "missing file must be reported as unavailable, not an empty collected result" || return 1
  assert_equal "0" "$(printf '%s' "$output" | jq -r '.owner_rules | length')" "no rules should be parsed when there is no file"
}

test_falls_back_to_root_codeowners_and_surfaces_validation_errors() {
  local output
  output="$(collect_codeowners "${TESTS_DIR}/fixtures/codeowners-root-with-errors.json")"
  assert_equal "CODEOWNERS" "$(printf '%s' "$output" | jq -r '.resolved_path')" "should fall back to root CODEOWNERS when .github/CODEOWNERS is absent" || return 1
  assert_equal "collected" "$(printf '%s' "$output" | jq -r '.validation_errors.status')" "validation errors endpoint should be collected" || return 1
  assert_equal "1" "$(printf '%s' "$output" | jq -r '.validation_errors.data.errors | length')" "GitHub-reported validation errors must be preserved"
}

run_test test_finds_github_codeowners_and_parses_rules
run_test test_reports_missing_codeowners_as_unavailable_not_empty
run_test test_falls_back_to_root_codeowners_and_surfaces_validation_errors

report_results
