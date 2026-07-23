#!/usr/bin/env bash
# Tests for scripts/collect-pr-merge.sh against fixture-driven mock responses.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GH_TOKEN="test-token"
export GITHUB_REPOSITORY="acme/widget"
export GITHUB_SERVER_URL="https://github.com"
export GITHUB_RUN_ID="999"
export PR_NUMBER="7"
export MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-success.json"

collect_pr_merge() {
  "${REPO_ROOT}/scripts/collect-pr-merge.sh"
}

test_collects_merged_pr_fields() {
  local out
  out="$(collect_pr_merge)" || return 1
  assert_valid_json "$out" "collector must print valid JSON" || return 1
  assert_equal "mergesha" "$(printf '%s' "$out" | jq -r '.pr.merge_commit_sha')" "merge commit sha" || return 1
  assert_equal "parentsha" "$(printf '%s' "$out" | jq -r '.pr.target_base_sha')" "target base sha should become the merge commit's first parent" || return 1
  assert_equal "headsha" "$(printf '%s' "$out" | jq -r '.pr.head_sha')" "head sha" || return 1
  assert_equal "main" "$(printf '%s' "$out" | jq -r '.pr.target_branch')" "target branch"
}

test_approvers_are_deduped_latest_per_login() {
  local out approvers
  out="$(collect_pr_merge)" || return 1
  approvers="$(printf '%s' "$out" | jq -c '.approvers')"
  assert_equal "2" "$(printf '%s' "$approvers" | jq 'length')" "only the two APPROVED reviewers, not the commenter" || return 1
  assert_equal "true" "$(printf '%s' "$approvers" | jq -r '.[] | select(.login=="alice") | .is_pr_head_approval')" "alice approved the head sha" || return 1
  assert_equal "false" "$(printf '%s' "$approvers" | jq -r '.[] | select(.login=="bob") | .is_pr_head_approval')" "bob approved an older sha"
}

test_commits_and_committers() {
  local out
  out="$(collect_pr_merge)" || return 1
  assert_json_equal '["c1","c2"]' "$(printf '%s' "$out" | jq -c '.commits_on_target_branch')" "commits on target branch from compare" || return 1
  assert_equal "2" "$(printf '%s' "$out" | jq '.code_committers | length')" "two code committers" || return 1
  assert_equal "alice@example.com" "$(printf '%s' "$out" | jq -r '.code_committers[] | select(.login=="alice") | .email')" "committer email lowercased"
}

test_unmerged_pr_fails() {
  local rc
  MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-not-merged.json" collect_pr_merge >/dev/null 2>&1
  rc=$?
  assert_equal "1" "$rc" "an unmerged PR must fail the collector"
}

run_test test_collects_merged_pr_fields
run_test test_approvers_are_deduped_latest_per_login
run_test test_commits_and_committers
run_test test_unmerged_pr_fails

report_results
