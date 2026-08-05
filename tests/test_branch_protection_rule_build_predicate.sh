#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests scripts/branch-protection-rule/build-predicate.sh — the jq shaping of
# the event payload + branch-protection snapshot into the branch-protection-rule
# predicate and its subject file.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"
BUILD_PREDICATE="${REPO_ROOT}/scripts/branch-protection-rule/build-predicate.sh"
EVENT_FIX="${TESTS_DIR}/fixtures/branch-protection-rule-event.json"
SNAPSHOT_FIX="${TESTS_DIR}/fixtures/branch-protection-rule-snapshot.json"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

run_build_predicate() {
  local tmp="$1"
  ( cd "$tmp" \
      && EVENT_PAYLOAD_FILE="$EVENT_FIX" \
         SNAPSHOT_FILE="$SNAPSHOT_FIX" \
         APP_KEY="my-app" \
         GITHUB_REPOSITORY="acme/widget" \
         GITHUB_RUN_ID="123" \
         "$BUILD_PREDICATE" >/dev/null )
}

test_predicate_top_level_shape() {
  local tmp; tmp="$(mktemp -d)"
  if ! run_build_predicate "$tmp"; then rm -rf "$tmp"; return 1; fi
  local out="${tmp}/predicate.json"
  assert_equal "1.0.0" "$(jq -r .schema_version "$out")" "schema_version" || { rm -rf "$tmp"; return 1; }
  assert_equal "GithubBranchProtectionRule" "$(jq -r .subject_type "$out")" "subject_type" || { rm -rf "$tmp"; return 1; }
  assert_equal "https://jfrog.com/evidence/branch-protection-rule/v1" \
    "$(jq -r .predicate_type "$out")" "predicate_type" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

test_predicate_event_and_snapshot_embedded() {
  local tmp; tmp="$(mktemp -d)"
  if ! run_build_predicate "$tmp"; then rm -rf "$tmp"; return 1; fi
  local out="${tmp}/predicate.json"
  assert_equal "edited" "$(jq -r .branch_protection_rule.event.action "$out")" "event action" || { rm -rf "$tmp"; return 1; }
  assert_equal "main" "$(jq -r .branch_protection_rule.event.rule.name "$out")" "rule name" || { rm -rf "$tmp"; return 1; }
  assert_equal "1" "$(jq -r .branch_protection_rule.event.changes.required_approving_review_count.from "$out")" "changes.from" || { rm -rf "$tmp"; return 1; }
  assert_equal "acme/widget" "$(jq -r .branch_protection_rule.event.repository.full_name "$out")" "repo full_name" || { rm -rf "$tmp"; return 1; }
  assert_equal "octocat" "$(jq -r .branch_protection_rule.event.sender.login "$out")" "sender login" || { rm -rf "$tmp"; return 1; }
  assert_equal "1.0.0" "$(jq -r .branch_protection_rule.repository_snapshot.schema_version "$out")" "snapshot embedded" || { rm -rf "$tmp"; return 1; }
  assert_equal "my-app" "$(jq -r .branch_protection_rule.app_key "$out")" "app_key recorded" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

test_predicate_app_key_null_when_unset() {
  local tmp; tmp="$(mktemp -d)"
  ( cd "$tmp" \
      && EVENT_PAYLOAD_FILE="$EVENT_FIX" \
         SNAPSHOT_FILE="$SNAPSHOT_FIX" \
         APP_KEY="" \
         GITHUB_REPOSITORY="acme/widget" \
         "$BUILD_PREDICATE" >/dev/null ) || { rm -rf "$tmp"; return 1; }
  assert_equal "null" "$(jq -r .branch_protection_rule.app_key "${tmp}/predicate.json")" "app_key null" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

test_subject_shape() {
  local tmp; tmp="$(mktemp -d)"
  if ! run_build_predicate "$tmp"; then rm -rf "$tmp"; return 1; fi
  local subj="${tmp}/subject.json"
  assert_equal "acme/widget" "$(jq -r .repository_full_name "$subj")" "subject repo" || { rm -rf "$tmp"; return 1; }
  assert_equal "12345" "$(jq -r .rule_id "$subj")" "subject rule id" || { rm -rf "$tmp"; return 1; }
  assert_equal "main" "$(jq -r .rule_pattern "$subj")" "subject rule pattern" || { rm -rf "$tmp"; return 1; }
  assert_equal "edited" "$(jq -r .action "$subj")" "subject action" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

test_predicate_fails_on_missing_snapshot() {
  local tmp; tmp="$(mktemp -d)"
  if ( cd "$tmp" \
      && EVENT_PAYLOAD_FILE="$EVENT_FIX" \
         SNAPSHOT_FILE="/nonexistent/snapshot.json" \
         "$BUILD_PREDICATE" >/dev/null 2>&1 ); then
    echo "  FAIL: expected non-zero exit for missing snapshot" >&2
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
}

run_test test_predicate_top_level_shape
run_test test_predicate_event_and_snapshot_embedded
run_test test_predicate_app_key_null_when_unset
run_test test_subject_shape
run_test test_predicate_fails_on_missing_snapshot

report_results
