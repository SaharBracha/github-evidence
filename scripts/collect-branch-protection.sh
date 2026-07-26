#!/usr/bin/env bash
# Collects full branch protection settings: protected branches, each branch's
# full protection document, repository rulesets (including inherited ones
# GitHub reports as applicable), and the effective rules per protected branch.
#
# Prints a single JSON object on stdout. Never fails the job on its own -
# every API call is wrapped in a section record via github-api.sh.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/github-api.sh
source "${SCRIPT_DIR}/lib/github-api.sh"

: "${GH_OWNER:?GH_OWNER must be set}"
: "${GH_REPO:?GH_REPO must be set}"

repo_path="/repos/${GH_OWNER}/${GH_REPO}"

protected_branches_section="$(gh_section_get_paginated "${repo_path}/branches?protected=true")"

branches_detail="{}"
if [[ "$(printf '%s' "$protected_branches_section" | jq -r '.status')" == "collected" ]]; then
  branch_names="$(printf '%s' "$protected_branches_section" | jq -r '.data[].name')"
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    encoded_branch="$(jq -rn --arg b "$branch" '$b | @uri')"
    protection_section="$(gh_section_get "${repo_path}/branches/${encoded_branch}/protection")"
    rules_section="$(gh_section_get "${repo_path}/rules/branches/${encoded_branch}")"
    branches_detail="$(jq -n \
      --argjson acc "$branches_detail" \
      --arg name "$branch" \
      --argjson protection "$protection_section" \
      --argjson rules "$rules_section" \
      '$acc + {($name): {protection: $protection, effective_rules: $rules}}')"
  done <<< "$branch_names"
fi

rulesets_section="$(gh_section_get_paginated "${repo_path}/rulesets?includes_parents=true")"

ruleset_details="{}"
if [[ "$(printf '%s' "$rulesets_section" | jq -r '.status')" == "collected" ]]; then
  ruleset_ids="$(printf '%s' "$rulesets_section" | jq -r '.data[].id')"
  while IFS= read -r ruleset_id; do
    [[ -z "$ruleset_id" ]] && continue
    detail_section="$(gh_section_get "${repo_path}/rulesets/${ruleset_id}?includes_parents=true")"
    ruleset_details="$(jq -n \
      --argjson acc "$ruleset_details" \
      --arg id "$ruleset_id" \
      --argjson detail "$detail_section" \
      '$acc + {($id): $detail}')"
  done <<< "$ruleset_ids"
fi

jq -n \
  --argjson protected_branches "$protected_branches_section" \
  --argjson branches "$branches_detail" \
  --argjson rulesets "$rulesets_section" \
  --argjson ruleset_details "$ruleset_details" \
  '{
    protected_branches: $protected_branches,
    branches: $branches,
    rulesets: $rulesets,
    ruleset_details: $ruleset_details
  }'
