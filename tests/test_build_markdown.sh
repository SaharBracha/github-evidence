#!/usr/bin/env bash
# Tests for scripts/build-markdown.sh: renders a human-readable, render-safe
# markdown report from a normalized predicate (plus subject for PR-merge), for
# both evidence types. The report is attached via `jf evd create --markdown`.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert_contains() {
  local haystack="$1" needle="$2" message="${3:-output should contain substring}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  FAIL: $message" >&2
    echo "    missing: $needle" >&2
    return 1
  fi
}

# The JFrog viewer mangles " < > — the report must never emit them.
assert_render_safe() {
  local haystack="$1" message="${2:-output must not contain \" < or >}"
  if [[ "$haystack" == *'"'* || "$haystack" == *'<'* || "$haystack" == *'>'* ]]; then
    echo "  FAIL: $message" >&2
    return 1
  fi
}

test_pull_request_merge_markdown() {
  local pred subj md
  pred="${WORK}/pred-pr.json"; subj="${WORK}/subj-pr.json"; md="${WORK}/pr.md"

  cat > "$pred" <<'JSON'
{
  "schema_version": "1.2",
  "subject_type": "PullRequestMerge",
  "merge": {
    "merge_commit_sha": "ed0be7a1",
    "merged_at": "2026-07-23T11:28:03Z",
    "merged_by": "octocat",
    "target_branch": "main",
    "target_base_sha": "ed6de7af"
  },
  "approvers": [
    { "login": "hubot", "submitted_at": "2026-07-23T11:27:58Z", "is_pr_head_approval": true }
  ],
  "commits_on_target_branch": ["55bf3c3a", "0b2b9eec"],
  "code_committers": [
    { "login": null, "email": "octocat@example.com" }
  ],
  "collection": {
    "collected_at": "2026-07-23T11:28:30.000Z",
    "workflow_run_url": "https://github.com/acme/widget/actions/runs/30003234739"
  }
}
JSON

  cat > "$subj" <<'JSON'
{ "head_sha": "0b2b9eec", "pr_number": "7", "head_ref": "feature-x", "repo_url": "https://github.com/acme/widget", "created_at": "2026-07-23T11:28:30.000Z" }
JSON

  EVIDENCE_TYPE=pull-request-merge PREDICATE_FILE="$pred" SUBJECT_FILE="$subj" MARKDOWN_OUT="$md" \
    "${REPO_ROOT}/scripts/build-markdown.sh" || return 1

  local out; out="$(cat "$md")"
  assert_contains "$out" "# Pull Request Merge Evidence Report" "PR title" || return 1
  assert_contains "$out" "**Repository:** acme/widget" "repository slug from subject" || return 1
  assert_contains "$out" "**Pull request:** #7" "pr number" || return 1
  assert_contains "$out" "**Merged by:** octocat" "merged_by" || return 1
  assert_contains "$out" "ed0be7a1" "merge commit sha" || return 1
  assert_contains "$out" "Approvers (1)" "approver count" || return 1
  assert_contains "$out" "hubot" "approver login" || return 1
  assert_contains "$out" "Commits on Target Branch (2)" "commit count" || return 1
  assert_contains "$out" "55bf3c3a" "commit sha listed" || return 1
  assert_contains "$out" "Code Committers (1)" "committer count" || return 1
  assert_contains "$out" "mailto:octocat@example.com" "committer email as mailto link" || return 1
  assert_contains "$out" "| — |" "null committer login renders as dash" || return 1
  assert_render_safe "$out" "PR report must be render-safe"
}

test_branch_protection_markdown_populated() {
  local pred md
  pred="${WORK}/pred-bp.json"; md="${WORK}/bp.md"

  cat > "$pred" <<'JSON'
{
  "schema_version": "1.0",
  "subject_type": "RepositoryBranchProtection",
  "repository": { "full_name": "acme/widget", "url": "https://github.com/acme/widget" },
  "collection": { "collected_at": "2026-07-23T11:00:00Z", "workflow_run_url": "https://github.com/acme/widget/actions/runs/1" },
  "summary": { "protected_branch_count": 1, "ruleset_count": 1, "has_codeowners_file": true, "codeowners_rule_count": 3 },
  "branches": [
    {
      "name": "main",
      "required_pull_request_reviews": { "required": true, "required_approving_review_count": 2, "require_code_owner_reviews": true },
      "required_status_checks": { "strict": true, "checks": ["ci/build"] },
      "enforce_admins": true,
      "allow_force_pushes": false
    }
  ],
  "rulesets": [
    { "name": "protect-main", "enforcement": "active", "target": "branch", "rules": ["pull_request", "required_status_checks"] }
  ]
}
JSON

  EVIDENCE_TYPE=branch-protection PREDICATE_FILE="$pred" MARKDOWN_OUT="$md" \
    "${REPO_ROOT}/scripts/build-markdown.sh" || return 1

  local out; out="$(cat "$md")"
  assert_contains "$out" "# Branch Protection Evidence Report" "BP title" || return 1
  assert_contains "$out" "acme/widget" "repository name" || return 1
  assert_contains "$out" "**Protected branches:** 1" "protected branch count" || return 1
  assert_contains "$out" "\`main\`" "branch row" || return 1
  assert_contains "$out" "ci/build" "status check listed" || return 1
  assert_contains "$out" "protect-main" "ruleset name" || return 1
  assert_contains "$out" "pull_request" "ruleset rule listed" || return 1
  assert_render_safe "$out" "BP report must be render-safe"
}

# Empty rulesets with a 403 raw-snapshot status must show the reason, not a bare table.
test_branch_protection_markdown_ruleset_unavailable() {
  local pred md
  pred="${WORK}/pred-bp-unavail.json"; md="${WORK}/bp-unavail.md"

  cat > "$pred" <<'JSON'
{
  "schema_version": "1.0",
  "repository": { "full_name": "acme/widget", "url": "https://github.com/acme/widget" },
  "collection": { "collected_at": "2026-07-23T11:28:24Z", "workflow_run_url": "https://github.com/acme/widget/actions/runs/1" },
  "summary": { "protected_branch_count": 0, "ruleset_count": 0, "has_codeowners_file": false, "codeowners_rule_count": 0 },
  "branches": [],
  "rulesets": [],
  "raw_snapshot": {
    "sections": {
      "branch_protection": {
        "rulesets": { "http_status": 403, "status": "unavailable", "message": "Upgrade to GitHub Pro or make this repository public to enable this feature." }
      }
    }
  }
}
JSON

  EVIDENCE_TYPE=branch-protection PREDICATE_FILE="$pred" MARKDOWN_OUT="$md" \
    "${REPO_ROOT}/scripts/build-markdown.sh" || return 1

  local out; out="$(cat "$md")"
  assert_contains "$out" "_No protected branches configured._" "empty branches note" || return 1
  assert_contains "$out" "Unavailable: Upgrade to GitHub Pro" "ruleset unavailable reason" || return 1
  assert_render_safe "$out" "unavailable BP report must be render-safe"
}

# A branch name containing a pipe must be escaped so it cannot break out of the
# markdown table column (attacker-influenceable ref names).
test_branch_protection_markdown_escapes_pipe() {
  local pred md
  pred="${WORK}/pred-pipe.json"; md="${WORK}/pipe.md"

  cat > "$pred" <<'JSON'
{
  "schema_version": "1.0",
  "repository": { "full_name": "acme/widget", "url": "https://github.com/acme/widget" },
  "collection": { "collected_at": "2026-07-23T11:00:00Z", "workflow_run_url": "https://github.com/acme/widget/actions/runs/1" },
  "summary": { "protected_branch_count": 1, "ruleset_count": 0, "has_codeowners_file": false, "codeowners_rule_count": 0 },
  "branches": [
    {
      "name": "feat|inject",
      "required_pull_request_reviews": { "required": true, "required_approving_review_count": 1, "require_code_owner_reviews": false },
      "required_status_checks": { "strict": false, "checks": [] },
      "enforce_admins": false,
      "allow_force_pushes": false
    }
  ],
  "rulesets": []
}
JSON

  EVIDENCE_TYPE=branch-protection PREDICATE_FILE="$pred" MARKDOWN_OUT="$md" \
    "${REPO_ROOT}/scripts/build-markdown.sh" || return 1

  local out; out="$(cat "$md")"
  assert_contains "$out" 'feat\|inject' "pipe in branch name must be escaped as \\|" || return 1
  if [[ "$out" == *'feat|inject'* ]]; then
    echo "  FAIL: raw unescaped pipe leaked into table cell" >&2
    return 1
  fi
}

test_unknown_evidence_type_fails() {
  local pred; pred="${WORK}/pred-x.json"; echo '{}' > "$pred"
  if EVIDENCE_TYPE=nonsense PREDICATE_FILE="$pred" MARKDOWN_OUT="${WORK}/x.md" \
      "${REPO_ROOT}/scripts/build-markdown.sh" 2>/dev/null; then
    echo "  FAIL: expected non-zero exit for unknown EVIDENCE_TYPE" >&2
    return 1
  fi
}

run_test test_pull_request_merge_markdown
run_test test_branch_protection_markdown_populated
run_test test_branch_protection_markdown_ruleset_unavailable
run_test test_branch_protection_markdown_escapes_pipe
run_test test_unknown_evidence_type_fails

report_results
