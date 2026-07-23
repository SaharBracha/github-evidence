#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/github-api-pr.sh"

github_get_pr_commits_json() {
  local gh_api_host="$1"
  local owner="$2"
  local repo="$3"
  local pr_number="$4"

  github_api_get_json_array_paginated \
    "${gh_api_host}/repos/${owner}/${repo}/pulls/${pr_number}/commits?per_page=100&page=1"
}

github_get_pr_code_committers_json() {
  local gh_api_host="$1"
  local owner="$2"
  local repo="$3"
  local pr_number="$4"
  local commits_json

  commits_json=$(github_get_pr_commits_json "$gh_api_host" "$owner" "$repo" "$pr_number")

  echo "$commits_json" | jq '
    [
      .[]
      | {
          login: (.author.login // null),
          email: ((.commit.author.email // "") | ascii_downcase)
        }
      | select((.login != null and .login != "") or .email != "")
      | . + {key: (if .login != null and .login != "" then "login:" + .login else "email:" + .email end)}
    ]
    | sort_by(.key)
    | group_by(.key)
    | map({
        login: .[0].login,
        email: ([.[].email | select(. != "")] | first // "")
      })
  '
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "$#" -ne 5 ]]; then
    echo "usage: $0 <commits|committers> <gh-api-host> <owner> <repo> <pr-number>" >&2
    exit 2
  fi

  mode="$1"
  shift

  case "$mode" in
    commits)
      github_get_pr_commits_json "$@"
      ;;
    committers)
      github_get_pr_code_committers_json "$@"
      ;;
    *)
      echo "usage: $0 <commits|committers> <gh-api-host> <owner> <repo> <pr-number>" >&2
      exit 2
      ;;
  esac
fi
