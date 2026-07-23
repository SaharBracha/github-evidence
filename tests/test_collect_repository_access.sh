#!/usr/bin/env bash
# Tests for scripts/collect-repository-access.sh against fixture-driven mock responses.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GITHUB_TOKEN="test-token"
export GH_OWNER="acme"
export GH_REPO="widget"

collect_repository_access() {
  MOCK_CURL_FIXTURE="$1" "${REPO_ROOT}/scripts/collect-repository-access.sh"
}

test_collects_access_and_configuration_sections() {
  local output
  output="$(collect_repository_access "${TESTS_DIR}/fixtures/full-success.json")"
  assert_valid_json "$output" "collector must print valid JSON" || return 1

  assert_equal "acme/widget" "$(printf '%s' "$output" | jq -r '.repository.data.full_name')" "repository metadata should be collected" || return 1
  assert_equal "2" "$(printf '%s' "$output" | jq -r '.collaborators.data | length')" "both collaborators should be listed" || return 1
  assert_equal "admin" "$(printf '%s' "$output" | jq -r '.collaborators.data[0].role_name')" "collaborator role should be preserved" || return 1
  assert_equal "docs-team" "$(printf '%s' "$output" | jq -r '.teams.data[0].slug')" "team grants should be listed" || return 1

  assert_equal "unavailable" "$(printf '%s' "$output" | jq -r '.installation.status')" "no GitHub App installed -> unavailable, not empty" || return 1

  assert_equal "collected" "$(printf '%s' "$output" | jq -r '.environments.status')" "environments (total_count-wrapped) should be collected" || return 1
  assert_equal "1" "$(printf '%s' "$output" | jq -r '.environments.data.environments | length')" "environments wrapper array should be unwrapped and merged correctly" || return 1
  assert_equal "collected" "$(printf '%s' "$output" | jq -r '.environment_details.production.detail.status')" "per-environment detail should be fetched" || return 1

  assert_equal "1" "$(printf '%s' "$output" | jq -r '.actions_variables.data.variables | length')" "actions variables (wrapped) should be unwrapped" || return 1
  assert_equal "DEPLOY_TOKEN" "$(printf '%s' "$output" | jq -r '.actions_secrets.data.secrets[0].name')" "secret metadata (name only, no value) should be preserved" || return 1
  assert_equal "null" "$(printf '%s' "$output" | jq -r '.actions_secrets.data.secrets[0].value // "null"')" "secrets endpoint must never carry a value field" || return 1

  assert_equal "***REDACTED***" "$(printf '%s' "$output" | jq -r '.webhooks.data[0].config.secret')" "webhook config secret must be redacted even though GitHub does not normally return it in the clear" || return 1
  assert_equal "https://example.com/hook" "$(printf '%s' "$output" | jq -r '.webhooks.data[0].config.url')" "non-secret webhook config fields must survive redaction"
}

run_test test_collects_access_and_configuration_sections

report_results
