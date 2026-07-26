#!/usr/bin/env bash
# Collects merged-pull-request evidence for a single PR and prints a raw JSON
# document on stdout for build-predicate.sh to shape into the
# pull-request-merge predicate.
#
# Self-contained: no code-review evidence lookup, no polling. Repository and
# server identity are derived from the runner-provided environment; the PR to
# collect is passed as PR_NUMBER.
#
# Required env: GITHUB_TOKEN, PR_NUMBER, GITHUB_REPOSITORY.
# Optional env: GITHUB_API_URL (default https://api.github.com),
#               GITHUB_SERVER_URL (default https://github.com), GITHUB_RUN_ID.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/github-api.sh
source "${SCRIPT_DIR}/lib/github-api.sh"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"

resolve_owner_repo
GH_API_URL="${GITHUB_API_URL:-https://api.github.com}"
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
REPOSITORY_URL="${SERVER_URL}/${GITHUB_REPOSITORY}"

PR_JSON=$(gh_get_required "${GH_API_URL}/repos/${GH_OWNER}/${GH_REPO}/pulls/${PR_NUMBER}")
IS_MERGED=$(echo "$PR_JSON" | jq -r '.merged // false')
if [ "$IS_MERGED" != "true" ]; then
  echo "::error::PR ${PR_NUMBER} is not merged; merged PR evidence is only created for merged PRs" >&2
  exit 1
fi

HEAD_SHA=$(echo "$PR_JSON" | jq -r '.head.sha // ""')
HEAD_REF=$(echo "$PR_JSON" | jq -r '.head.ref // ""')
TARGET_BRANCH=$(echo "$PR_JSON" | jq -r '.base.ref // ""')
TARGET_BASE_SHA=$(echo "$PR_JSON" | jq -r '.base.sha // ""')
MERGE_COMMIT_SHA=$(echo "$PR_JSON" | jq -r '.merge_commit_sha // ""')
MERGED_AT=$(echo "$PR_JSON" | jq -r '.merged_at // ""')
MERGED_BY=$(echo "$PR_JSON" | jq -r '.merged_by.login // ""')

# Prefer the merge commit's first parent as the target-branch base, so the
# compare below reflects exactly what this merge introduced onto the target.
if [ -n "$MERGE_COMMIT_SHA" ] && [ "$MERGE_COMMIT_SHA" != "null" ]; then
  MERGE_COMMIT_JSON=$(gh_get_required "${GH_API_URL}/repos/${GH_OWNER}/${GH_REPO}/commits/${MERGE_COMMIT_SHA}")
  MERGE_PARENT_SHA=$(echo "$MERGE_COMMIT_JSON" | jq -r '.parents[0].sha // ""')
  if [ -n "$MERGE_PARENT_SHA" ] && [ "$MERGE_PARENT_SHA" != "null" ]; then
    TARGET_BASE_SHA="$MERGE_PARENT_SHA"
  fi
fi

COLLECTED_AT=$(rfc3339_now)
WORKFLOW_RUN_URL=$(workflow_run_url)

# Reviews are paginated (Link header), like the PR commits below: a PR with more
# than one page of reviews must not silently truncate the approver list.
REVIEWS=$(gh_get_paginated_array \
  "${GH_API_URL}/repos/${GH_OWNER}/${GH_REPO}/pulls/${PR_NUMBER}/reviews?per_page=100&page=1")
APPROVERS=$(echo "$REVIEWS" | jq --arg head_sha "$HEAD_SHA" '
  [ .[] | select(.state == "APPROVED") ]
  | group_by(.user.login)
  | map(
      (sort_by(.submitted_at) | last) as $latest
      | {
          review_id: $latest.id,
          login: $latest.user.login,
          body: ($latest.body // ""),
          submitted_at: $latest.submitted_at,
          approved_sha: ($latest.commit_id // ""),
          is_pr_head_approval: (($latest.commit_id // "") == $head_sha)
        }
    )
')

COMMITS_ON_TARGET_BRANCH=$(bash "${SCRIPT_DIR}/lib/compare-commits.sh" \
  "$GH_API_URL" \
  "$GH_OWNER" \
  "$GH_REPO" \
  "$TARGET_BASE_SHA" \
  "$MERGE_COMMIT_SHA")

# If the compare base is already the merge commit, preserve the merge commit as
# the target-branch commit that represents this merged PR.
if [ "$(echo "$COMMITS_ON_TARGET_BRANCH" | jq 'length')" -eq 0 ] \
  && [ -n "$MERGE_COMMIT_SHA" ] \
  && [ "$MERGE_COMMIT_SHA" != "null" ]; then
  COMMITS_ON_TARGET_BRANCH=$(jq -n --arg sha "$MERGE_COMMIT_SHA" '[$sha]')
fi

CODE_COMMITTERS=$(bash "${SCRIPT_DIR}/lib/get-pr-commits.sh" \
  committers \
  "$GH_API_URL" \
  "$GH_OWNER" \
  "$GH_REPO" \
  "$PR_NUMBER")

jq -n \
  --arg owner "$GH_OWNER" \
  --arg repo "$GH_REPO" \
  --arg pr_number "$PR_NUMBER" \
  --arg head_sha "$HEAD_SHA" \
  --arg head_ref "$HEAD_REF" \
  --arg repo_url "$REPOSITORY_URL" \
  --arg target_branch "$TARGET_BRANCH" \
  --arg target_base_sha "$TARGET_BASE_SHA" \
  --arg merge_commit_sha "$MERGE_COMMIT_SHA" \
  --arg merged_at "$MERGED_AT" \
  --arg merged_by "$MERGED_BY" \
  --argjson approvers "$APPROVERS" \
  --argjson commits_on_target_branch "$COMMITS_ON_TARGET_BRANCH" \
  --argjson code_committers "$CODE_COMMITTERS" \
  --arg collected_at "$COLLECTED_AT" \
  --arg workflow_run_url "$WORKFLOW_RUN_URL" \
  '{
    pr: {
      owner: $owner,
      repo: $repo,
      pr_number: $pr_number,
      head_sha: $head_sha,
      head_ref: $head_ref,
      repo_url: $repo_url,
      target_branch: $target_branch,
      target_base_sha: $target_base_sha,
      merge_commit_sha: $merge_commit_sha,
      merged_at: $merged_at,
      merged_by: $merged_by
    },
    approvers: $approvers,
    commits_on_target_branch: $commits_on_target_branch,
    code_committers: $code_committers,
    collected_at: $collected_at,
    workflow_run_url: $workflow_run_url
  }'
