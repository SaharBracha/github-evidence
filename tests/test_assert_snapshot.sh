#!/usr/bin/env bash
# Unit tests for tests/assert-snapshot.sh - the snapshot verifier the
# smoke-test job feeds the live collector's output into. Runs with zero
# network: it builds one real snapshot by running the orchestrator against the
# full-success mock fixture, then feeds assert-snapshot.sh that snapshot and
# deliberately broken variants of it, checking the exit code each time.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GITHUB_TOKEN="test-token"
export GITHUB_REPOSITORY="acme/widget"
unset GH_OWNER GH_REPO

ASSERT="${TESTS_DIR}/assert-snapshot.sh"

# One healthy snapshot, reused (with mutations) by every test below.
VALID_BODY="$(MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/full-success.json" \
  "${REPO_ROOT}/scripts/branch-protection/collect-settings-snapshot.sh")"

# Pipe a snapshot document into the verifier and echo its exit code.
assert_exit_code() {
  local body="$1" repo="${2:-$GITHUB_REPOSITORY}"
  printf '%s\n' "$body" | GITHUB_REPOSITORY="$repo" bash "$ASSERT" >/dev/null 2>&1
  echo "$?"
}

test_valid_snapshot_passes() {
  assert_equal "0" "$(assert_exit_code "$VALID_BODY")" "a healthy snapshot must pass"
}

test_invalid_json_fails() {
  assert_equal "1" "$(assert_exit_code "{ not valid json")" "non-JSON input must fail"
}

test_wrong_schema_version_fails() {
  local body
  body="$(printf '%s' "$VALID_BODY" | jq '.schema_version = "9.9.9"')"
  assert_equal "1" "$(assert_exit_code "$body")" "an unexpected schema_version must fail"
}

test_repository_identity_mismatch_fails() {
  # Body says acme/widget; tell the verifier we expected a different repo.
  assert_equal "1" "$(assert_exit_code "$VALID_BODY" "other/repo")" "a repository.full_name mismatch must fail"
}

test_missing_top_level_section_fails() {
  local body
  body="$(printf '%s' "$VALID_BODY" | jq 'del(.sections.code_owner_enforcement)')"
  assert_equal "1" "$(assert_exit_code "$body")" "a missing top-level section must fail"
}

test_status_error_anywhere_fails() {
  local body
  body="$(printf '%s' "$VALID_BODY" \
    | jq '.sections.code_owners.file = {status:"error", http_status:500, message:"boom", reason:"error"}')"
  assert_equal "1" "$(assert_exit_code "$body")" "any field with status \"error\" must fail"
}

test_repository_metadata_not_collected_fails() {
  local body
  body="$(printf '%s' "$VALID_BODY" \
    | jq '.sections.repository_access.repository = {status:"unavailable", http_status:403, message:"denied", reason:"permission_denied"}')"
  assert_equal "1" "$(assert_exit_code "$body")" "repository metadata not collected must fail the liveness anchor"
}

test_tolerated_unavailable_section_passes() {
  # A non-anchor section being unavailable is an expected, successful outcome
  # for a contents:read token and must NOT fail the smoke-test.
  local body
  body="$(printf '%s' "$VALID_BODY" \
    | jq '.sections.repository_access.collaborators = {status:"unavailable", http_status:403, message:"denied", reason:"permission_denied"}')"
  assert_equal "0" "$(assert_exit_code "$body")" "a tolerated unavailable section must still pass"
}

run_test test_valid_snapshot_passes
run_test test_invalid_json_fails
run_test test_wrong_schema_version_fails
run_test test_repository_identity_mismatch_fails
run_test test_missing_top_level_section_fails
run_test test_status_error_anywhere_fails
run_test test_repository_metadata_not_collected_fails
run_test test_tolerated_unavailable_section_passes

report_results
