#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests prepare-request JSON shaping used by create-entity-evidence.sh
# (jq filter only — no network / jf api).
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

build_prepare_req() {
  local predicate_file="$1" markdown_file="${2:-}"
  local jq_args jq_filter
  jq_args=(
    -n
    --slurpfile predicate "$predicate_file"
    --arg predicate_type "https://jfrog.com/evidence/github-pull-request/v1"
    --arg provider_id "github-actions"
    --arg project_key "demo"
    --arg entity_type "githubPullRequest"
    --arg entity_id "abcdef1234567890abcdef1234567890abcdef12"
  )
  jq_filter='{
    predicate: $predicate[0],
    predicate_type: $predicate_type,
    provider_id: $provider_id,
    project_key: $project_key,
    subject: {
      subject_type: "entity",
      entity_type: $entity_type,
      entity_id: $entity_id
    }
  }'
  if [[ -n "$markdown_file" ]]; then
    jq_args+=(--rawfile markdown "$markdown_file")
    jq_filter+=' | . + {markdown: $markdown}'
  fi
  jq "${jq_args[@]}" "$jq_filter"
}

test_prepare_request_entity_subject() {
  local tmp req
  tmp="$(mktemp -d)"
  printf '%s\n' '{"pull_request_merge":{},"branch_protection":{}}' > "${tmp}/predicate.json"
  req="$(build_prepare_req "${tmp}/predicate.json")"
  assert_json_equal \
    '{"predicate":{"branch_protection":{},"pull_request_merge":{}},"predicate_type":"https://jfrog.com/evidence/github-pull-request/v1","project_key":"demo","provider_id":"github-actions","subject":{"entity_id":"abcdef1234567890abcdef1234567890abcdef12","entity_type":"githubPullRequest","subject_type":"entity"}}' \
    "$req" \
    "prepare body without markdown" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

test_prepare_request_includes_markdown() {
  local tmp req md
  tmp="$(mktemp -d)"
  printf '%s\n' '{"x":1}' > "${tmp}/predicate.json"
  printf '%s\n' '# hello' > "${tmp}/report.md"
  req="$(build_prepare_req "${tmp}/predicate.json" "${tmp}/report.md")"
  md="$(printf '%s' "$req" | jq -r '.markdown')"
  assert_equal "# hello" "$(printf '%s' "$md" | tr -d '\n')" "markdown field from file" || { rm -rf "$tmp"; return 1; }
  assert_equal "entity" "$(printf '%s' "$req" | jq -r '.subject.subject_type')" "subject_type" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

run_test test_prepare_request_entity_subject
run_test test_prepare_request_includes_markdown

report_results
