#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/github-api-pr.sh"

github_compare_commit_shas() {
  local gh_api_host="$1"
  local owner="$2"
  local repo="$3"
  local previous_sha="${4:-}"
  local current_sha="${5:-}"

  if [[ -z "$current_sha" || "$current_sha" == "null" ]]; then
    echo "::error::current_sha is required" >&2
    exit 1
  fi

  if [[ -z "$previous_sha" || "$previous_sha" == "null" ]]; then
    jq -n --arg sha "$current_sha" '[$sha]'
    return
  fi

  local diff_response
  diff_response=$(github_api_get \
    "${gh_api_host}/repos/${owner}/${repo}/compare/${previous_sha}...${current_sha}")

  # Strip unescaped control characters (U+0000-U+001F) that jq cannot parse
  # inside JSON strings. Keep tab, newline, and carriage return JSON whitespace.
  diff_response=$(printf '%s' "$diff_response" | LC_ALL=C tr -d '\000-\010\013-\014\016-\037')

  # GitHub's compare endpoint caps the returned .commits array at 250 while
  # .total_commits reports the true count. Warn when the list is truncated so
  # an incomplete commits_on_target_branch is visible in the run log rather
  # than silently under-reported.
  local total_commits collected
  total_commits=$(printf '%s' "$diff_response" | jq -r '.total_commits // (.commits | length)')
  collected=$(printf '%s' "$diff_response" | jq '.commits | length')
  if [[ "$total_commits" -gt "$collected" ]]; then
    echo "::warning::compare ${previous_sha}...${current_sha} reports ${total_commits} commits but the API returned ${collected} (GitHub caps compare results at 250); commits_on_target_branch is incomplete." >&2
  fi

  echo "$diff_response" | jq '[.commits[].sha]'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "$#" -ne 5 ]]; then
    echo "usage: $0 <gh-api-host> <owner> <repo> <previous-sha> <current-sha>" >&2
    exit 2
  fi

  github_compare_commit_shas "$1" "$2" "$3" "$4" "$5"
fi
