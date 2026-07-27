#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Orchestrates all repository-settings collectors, merges their output into one
# document, and adds a computed code-owner-enforcement correlation. Prints the
# resulting JSON document exactly once on stdout (no log markers), so
# build-predicate.sh can consume it directly.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../lib/github-api.sh
source "${SCRIPT_DIR}/../lib/github-api.sh"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

SCHEMA_VERSION="1.0.0"

: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set; pass github.token via env in action.yml}"

resolve_owner_repo
export GH_OWNER GH_REPO GITHUB_TOKEN

branch_protection="$("${SCRIPT_DIR}/collect-branch-protection.sh")"
code_owners="$("${SCRIPT_DIR}/collect-codeowners.sh")"
repository_access="$("${SCRIPT_DIR}/collect-repository-access.sh")"

# Correlate declared CODEOWNERS rules with the API's own code-owner
# enforcement flags. This is computed, not fetched: GitHub does not expose a
# single endpoint for "is code-owner approval required", so we read it out of
# both branch protection and rulesets, per branch.
code_owner_enforcement="$(jq -n \
  --argjson branch_protection "$branch_protection" \
  --argjson code_owners "$code_owners" \
  '
  ($code_owners.resolved_path != null) as $has_codeowners_file |
  ($branch_protection.branches | to_entries | map({
    branch: .key,
    require_code_owner_reviews_via_branch_protection: (
      if .value.protection.status == "collected" then
        (.value.protection.data.required_pull_request_reviews as $rpr
         | if ($rpr | type) == "object" and ($rpr | has("require_code_owner_reviews")) then
             $rpr.require_code_owner_reviews
           else
             false
           end)
      else
        null
      end
    ),
    require_code_owner_review_via_rules: (
      if .value.effective_rules.status == "collected" then
        ([.value.effective_rules.data[]? | select(.type == "pull_request") | .parameters.require_code_owner_review]
         | any(. == true))
      else
        null
      end
    )
  })) as $per_branch |
  {
    has_codeowners_file: $has_codeowners_file,
    owner_rule_count: ($code_owners.owner_rules | length),
    codeowners_validation_errors_present: (
      ($code_owners.validation_errors.status == "collected") and
      (($code_owners.validation_errors.data.errors // []) | length > 0)
    ),
    per_branch: $per_branch
  }
  ')"

generated_at="$(rfc3339_now)"

jq -n \
  --arg schema_version "$SCHEMA_VERSION" \
  --arg generated_at "$generated_at" \
  --arg owner "$GH_OWNER" \
  --arg repo "$GH_REPO" \
  --argjson branch_protection "$branch_protection" \
  --argjson code_owners "$code_owners" \
  --argjson code_owner_enforcement "$code_owner_enforcement" \
  --argjson repository_access "$repository_access" \
  '{
    schema_version: $schema_version,
    generated_at: $generated_at,
    repository: {owner: $owner, name: $repo, full_name: ($owner + "/" + $repo)},
    sections: {
      branch_protection: $branch_protection,
      code_owners: $code_owners,
      code_owner_enforcement: $code_owner_enforcement,
      repository_access: $repository_access
    }
  }'
