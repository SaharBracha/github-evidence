#!/usr/bin/env bash
# Collects the CODEOWNERS file (in GitHub's lookup precedence order), parses
# its ownership rules, and collects GitHub's own CODEOWNERS validation errors.
#
# Correlating these rules with branch-protection / ruleset "require code owner
# reviews" settings happens in collect-settings-snapshot.sh, once both sections
# are available. GitHub has no API that returns a per-owner approval count or
# that predicts the owners of an arbitrary future change - only the declared
# pattern -> owner rules and whether code-owner review is enforced at all.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/github-api-settings.sh
source "${SCRIPT_DIR}/lib/github-api-settings.sh"

: "${GH_OWNER:?GH_OWNER must be set}"
: "${GH_REPO:?GH_REPO must be set}"

repo_path="/repos/${GH_OWNER}/${GH_REPO}"

# GitHub looks for CODEOWNERS in this exact order.
candidate_paths=(".github/CODEOWNERS" "CODEOWNERS" "docs/CODEOWNERS")

file_section='{"status":"unavailable","http_status":404,"message":"No CODEOWNERS file found at .github/CODEOWNERS, CODEOWNERS, or docs/CODEOWNERS."}'
found_path=""
raw_content=""

for candidate in "${candidate_paths[@]}"; do
  result="$(gh_api_get "${repo_path}/contents/${candidate}" "application/vnd.github.raw")"
  status="$(printf '%s' "$result" | jq -r '.status')"
  if [[ "$status" == "200" ]]; then
    found_path="$candidate"
    raw_content="$(printf '%s' "$result" | jq -r '.body')"
    file_section="$(jq -n --arg path "$candidate" --arg content "$raw_content" \
      '{status: "collected", http_status: 200, data: {path: $path, content: $content}}')"
    break
  fi
done

rules="[]"
if [[ -n "$found_path" ]]; then
  line_number=0
  # Disable pathname expansion while splitting each CODEOWNERS line into tokens.
  # Patterns legitimately contain glob metacharacters (e.g. "*.js", "docs/*");
  # with globbing enabled the unquoted split below would expand them against the
  # runner's checkout and silently corrupt the recorded pattern. Restore the
  # caller's previous -f state afterwards.
  codeowners_noglob_was_set="off"
  [[ "$-" == *f* ]] && codeowners_noglob_was_set="on"
  set -f
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == \#* ]] && continue

    # shellcheck disable=SC2206  # intentional word-split; globbing disabled via set -f
    tokens=($trimmed)
    pattern="${tokens[0]}"
    owners=("${tokens[@]:1}")

    owners_json="$(printf '%s\n' "${owners[@]:-}" | jq -R 'select(length > 0)' | jq -s '.')"
    rules="$(jq -c -n --argjson acc "$rules" --arg pattern "$pattern" --argjson owners "$owners_json" --argjson line "$line_number" \
      '$acc + [{pattern: $pattern, owners: $owners, line: $line}]')"
  done <<< "$raw_content"
  [[ "$codeowners_noglob_was_set" == "off" ]] && set +f
fi

errors_section="$(gh_section_get "${repo_path}/codeowners/errors")"

jq -n \
  --argjson file "$file_section" \
  --arg found_path "$found_path" \
  --argjson rules "$rules" \
  --argjson errors "$errors_section" \
  '{
    file: $file,
    resolved_path: (if $found_path == "" then null else $found_path end),
    owner_rules: $rules,
    validation_errors: $errors
  }'
