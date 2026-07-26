#!/usr/bin/env bash
# Shapes a collector's raw JSON document into the signed predicate and its
# subject file, selected by EVIDENCE_TYPE. Writes predicate.json and
# subject.json (paths overridable via PREDICATE_OUT / SUBJECT_OUT).
#
# Required env: EVIDENCE_TYPE, RAW_SNAPSHOT_FILE.
# Optional env: PREDICATE_TYPE (default per mode), PREDICATE_OUT, SUBJECT_OUT,
#   and for branch-protection: COLLECTOR_VERSION, GITHUB_API_URL, WORKFLOW_RUN_URL,
#   GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID, INCLUDE_RAW_SNAPSHOT.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

: "${EVIDENCE_TYPE:?EVIDENCE_TYPE must be set}"
: "${RAW_SNAPSHOT_FILE:?RAW_SNAPSHOT_FILE must be set}"
PREDICATE_OUT="${PREDICATE_OUT:-predicate.json}"
SUBJECT_OUT="${SUBJECT_OUT:-subject.json}"

# Guard against a missing/empty/null snapshot up front: --slurpfile would happily
# bind $raw[0] to null and emit an all-null predicate instead of failing.
if ! jq -e 'if . == null then false else true end' "$RAW_SNAPSHOT_FILE" >/dev/null 2>&1; then
  echo "::error::RAW_SNAPSHOT_FILE ${RAW_SNAPSHOT_FILE} is missing, empty, or not valid JSON" >&2
  exit 1
fi

case "$EVIDENCE_TYPE" in
  pull-request-merge)
    PREDICATE_TYPE="${PREDICATE_TYPE:-https://jfrog.com/evidence/pull-request-merge/v1}"

    jq -n \
      --arg schema_version "1.2" \
      --arg subject_type "PullRequestMerge" \
      --arg predicate_type "$PREDICATE_TYPE" \
      --slurpfile raw "$RAW_SNAPSHOT_FILE" \
      '$raw[0] as $r
       | {
           schema_version: $schema_version,
           subject_type: $subject_type,
           predicate_type: $predicate_type,
           merge: {
             merge_commit_sha: $r.pr.merge_commit_sha,
             merged_at: $r.pr.merged_at,
             merged_by: $r.pr.merged_by,
             target_branch: $r.pr.target_branch,
             target_base_sha: $r.pr.target_base_sha
           },
           approvers: $r.approvers,
           commits_on_target_branch: $r.commits_on_target_branch,
           code_committers: $r.code_committers,
           collection: {
             collected_at: $r.collected_at,
             workflow_run_url: $r.workflow_run_url
           }
         }' > "$PREDICATE_OUT"

    jq -n \
      --slurpfile raw "$RAW_SNAPSHOT_FILE" \
      '$raw[0] as $r
       | {
           head_sha: $r.pr.head_sha,
           pr_number: $r.pr.pr_number,
           head_ref: $r.pr.head_ref,
           repo_url: $r.pr.repo_url,
           created_at: $r.collected_at
         }' > "$SUBJECT_OUT"
    ;;

  branch-protection)
    PREDICATE_TYPE="${PREDICATE_TYPE:-https://jfrog.com/evidence/branch-protection/v1}"
    COLLECTOR_VERSION="${COLLECTOR_VERSION:-git-evidence}"
    API_HOST="${GITHUB_API_URL:-https://api.github.com}"
    SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
    WORKFLOW_RUN_URL="${WORKFLOW_RUN_URL:-$(workflow_run_url)}"
    INCLUDE_RAW_SNAPSHOT="${INCLUDE_RAW_SNAPSHOT:-true}"
    TOKEN_SCOPE_NOTE="collected with the workflow GITHUB_TOKEN; admin-only fields may be 'unavailable'"

    jq -n \
      --arg predicate_type "$PREDICATE_TYPE" \
      --arg collector_version "$COLLECTOR_VERSION" \
      --arg github_api_host "$API_HOST" \
      --arg server_url "$SERVER_URL" \
      --arg workflow_run_url "$WORKFLOW_RUN_URL" \
      --arg token_scope_note "$TOKEN_SCOPE_NOTE" \
      --argjson include_raw "$( [ "$INCLUDE_RAW_SNAPSHOT" = "true" ] && echo true || echo false )" \
      --slurpfile snap "$RAW_SNAPSHOT_FILE" \
      '
      $snap[0] as $s
      | $s.sections.branch_protection as $bp
      | $s.sections.code_owner_enforcement as $enf
      | ($s.repository.full_name) as $full
      | {
          schema_version: "1.0",
          predicate_type: $predicate_type,
          subject_type: "RepositoryBranchProtection",
          repository: {
            owner: $s.repository.owner,
            name: $s.repository.name,
            full_name: $full,
            url: ($server_url + "/" + $full)
          },
          collection: {
            collected_at: $s.generated_at,
            collector_version: $collector_version,
            github_api_host: $github_api_host,
            workflow_run_url: $workflow_run_url,
            token_scope_note: $token_scope_note
          },
          summary: {
            protected_branch_count: (($bp.protected_branches.data // []) | length),
            ruleset_count: (($bp.rulesets.data // []) | length),
            has_codeowners_file: ($enf.has_codeowners_file // false),
            codeowners_rule_count: ($enf.owner_rule_count // 0),
            codeowners_validation_errors_present: ($enf.codeowners_validation_errors_present // false)
          },
          branches: (
            ($bp.branches // {}) | to_entries | map(
              .key as $name
              | .value.protection as $prot
              | .value.effective_rules as $rules
              | ($prot.data // {}) as $p
              | ([ $enf.per_branch[]? | select(.branch == $name) ] | (.[0] // {})) as $e
              | {
                  name: $name,
                  protection_source: (
                    [ (if $prot.status == "collected" then "branch_protection" else empty end),
                      (if ($rules.status == "collected" and (($rules.data // []) | length) > 0) then "ruleset" else empty end) ]
                  ),
                  required_pull_request_reviews: (
                    ($p.required_pull_request_reviews // null) as $rpr
                    | if $rpr == null then
                        { required: false, required_approving_review_count: 0,
                          require_code_owner_reviews: false, dismiss_stale_reviews: false,
                          require_last_push_approval: false }
                      else
                        { required: true,
                          required_approving_review_count: ($rpr.required_approving_review_count // 0),
                          require_code_owner_reviews: ($rpr.require_code_owner_reviews // false),
                          dismiss_stale_reviews: ($rpr.dismiss_stale_reviews // false),
                          require_last_push_approval: ($rpr.require_last_push_approval // false) }
                      end
                  ),
                  required_status_checks: (
                    ($p.required_status_checks // null) as $rsc
                    | if $rsc == null then { strict: false, checks: [] }
                      else { strict: ($rsc.strict // false),
                             checks: ( if ($rsc.checks != null) then [ $rsc.checks[].context ] else ($rsc.contexts // []) end ) }
                      end
                  ),
                  enforce_admins: ($p.enforce_admins.enabled // false),
                  allow_force_pushes: ($p.allow_force_pushes.enabled // false),
                  allow_deletions: ($p.allow_deletions.enabled // false),
                  required_linear_history: ($p.required_linear_history.enabled // false),
                  required_signatures: ($p.required_signatures.enabled // false),
                  restrictions: (
                    ($p.restrictions // null) as $r
                    | if $r == null then { users: [], teams: [], apps: [] }
                      else { users: [ ($r.users // [])[] | .login ],
                             teams: [ ($r.teams // [])[] | .slug ],
                             apps:  [ ($r.apps  // [])[] | .slug ] }
                      end
                  ),
                  code_owner_review_required: {
                    via_branch_protection: ($e.require_code_owner_reviews_via_branch_protection // false),
                    via_ruleset: ($e.require_code_owner_review_via_rules // false)
                  },
                  collection_status: {
                    protection: $prot.status,
                    effective_rules: $rules.status
                  }
                }
            )
          ),
          rulesets: (
            ($bp.rulesets.data // []) | map(
              . as $rs
              | ($bp.ruleset_details[($rs.id | tostring)].data // {}) as $detail
              | {
                  id: $rs.id,
                  name: $rs.name,
                  enforcement: $rs.enforcement,
                  target: $rs.target,
                  conditions: ($detail.conditions // {}),
                  rules: ( [ ($detail.rules // [])[] | .type ] | unique )
                }
            )
          )
        }
      | if $include_raw then . + { raw_snapshot: $s } else . end
      ' > "$PREDICATE_OUT"

    # For branch protection the subject artifact IS the full snapshot document.
    cp "$RAW_SNAPSHOT_FILE" "$SUBJECT_OUT"
    ;;

  *)
    echo "::error::unknown EVIDENCE_TYPE: ${EVIDENCE_TYPE}" >&2
    exit 1
    ;;
esac

echo "Wrote ${PREDICATE_OUT} and ${SUBJECT_OUT}" >&2
