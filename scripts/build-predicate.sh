#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Shapes the two collector raw JSON documents into a single unified "github-pull-request"
# predicate and its subject file. The predicate carries both bodies under root
# keys `pull_request_merge` and `branch_protection`; the subject is a compact
# merge-commit identity. Writes predicate.json and subject.json (paths
# overridable via PREDICATE_OUT / SUBJECT_OUT).
#
# Required env: PR_RAW_SNAPSHOT_FILE, BP_RAW_SNAPSHOT_FILE.
# Optional env: PREDICATE_TYPE (default github-pull-request/v1), PREDICATE_OUT,
#   SUBJECT_OUT, COLLECTOR_VERSION, WORKFLOW_RUN_URL, GITHUB_SERVER_URL,
#   GITHUB_REPOSITORY, GITHUB_RUN_ID.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

: "${PR_RAW_SNAPSHOT_FILE:?PR_RAW_SNAPSHOT_FILE must be set}"
: "${BP_RAW_SNAPSHOT_FILE:?BP_RAW_SNAPSHOT_FILE must be set}"
PREDICATE_OUT="${PREDICATE_OUT:-predicate.json}"
SUBJECT_OUT="${SUBJECT_OUT:-subject.json}"

PREDICATE_TYPE="${PREDICATE_TYPE:-https://jfrog.com/evidence/github-pull-request/v1}"
COLLECTOR_VERSION="${COLLECTOR_VERSION:-git-evidence}"
API_HOST="https://api.github.com"
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
WORKFLOW_RUN_URL="${WORKFLOW_RUN_URL:-$(workflow_run_url)}"
TOKEN_SCOPE_NOTE="collected with the workflow GITHUB_TOKEN; admin-only fields may be 'unavailable'"

# Guard against a missing/empty/null snapshot up front: --slurpfile would happily
# bind $x[0] to null and emit an all-null section instead of failing.
for f in "$PR_RAW_SNAPSHOT_FILE" "$BP_RAW_SNAPSHOT_FILE"; do
  if ! jq -e 'if . == null then false else true end' "$f" >/dev/null 2>&1; then
    echo "::error::snapshot file ${f} is missing, empty, or not valid JSON" >&2
    exit 1
  fi
done

jq -n \
  --arg schema_version "1.0.0" \
  --arg subject_type "GithubPullRequest" \
  --arg predicate_type "$PREDICATE_TYPE" \
  --arg collector_version "$COLLECTOR_VERSION" \
  --arg github_api_host "$API_HOST" \
  --arg server_url "$SERVER_URL" \
  --arg workflow_run_url "$WORKFLOW_RUN_URL" \
  --arg token_scope_note "$TOKEN_SCOPE_NOTE" \
  --slurpfile pr "$PR_RAW_SNAPSHOT_FILE" \
  --slurpfile bp "$BP_RAW_SNAPSHOT_FILE" \
  '
  $pr[0] as $p
  | $bp[0] as $s
  | $s.sections.branch_protection as $bprot
  | $s.sections.code_owner_enforcement as $enf
  | ($s.repository.full_name) as $full
  | {
      schema_version: $schema_version,
      subject_type: $subject_type,
      predicate_type: $predicate_type,
      pull_request_merge: {
        merge: {
          merge_commit_sha: $p.pr.merge_commit_sha,
          merged_at: $p.pr.merged_at,
          merged_by: $p.pr.merged_by,
          target_branch: $p.pr.target_branch,
          target_base_sha: $p.pr.target_base_sha
        },
        approvers: $p.approvers,
        commits_on_target_branch: $p.commits_on_target_branch,
        code_committers: $p.code_committers,
        commit_signatures: $p.commit_signatures,
        all_commits_verified: $p.all_commits_verified,
        collection: {
          collected_at: $p.collected_at,
          workflow_run_url: $p.workflow_run_url
        }
      },
      branch_protection: (
        {
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
            protected_branch_count: (($bprot.protected_branches.data // []) | length),
            ruleset_count: (($bprot.rulesets.data // []) | length),
            has_codeowners_file: ($enf.has_codeowners_file // false),
            codeowners_rule_count: ($enf.owner_rule_count // 0),
            codeowners_validation_errors_present: ($enf.codeowners_validation_errors_present // false)
          },
          branches: (
            ($bprot.branches // {}) | to_entries | map(
              .key as $name
              | .value.protection as $prot
              | .value.effective_rules as $rules
              | ($prot.data // {}) as $bpd
              | ([ $enf.per_branch[]? | select(.branch == $name) ] | (.[0] // {})) as $e
              | {
                  name: $name,
                  protection_source: (
                    [ (if $prot.status == "collected" then "branch_protection" else empty end),
                      (if ($rules.status == "collected" and (($rules.data // []) | length) > 0) then "ruleset" else empty end) ]
                  ),
                  required_pull_request_reviews: (
                    ($bpd.required_pull_request_reviews // null) as $rpr
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
                    ($bpd.required_status_checks // null) as $rsc
                    | if $rsc == null then { strict: false, checks: [] }
                      else { strict: ($rsc.strict // false),
                             checks: ( if ($rsc.checks != null) then [ $rsc.checks[].context ] else ($rsc.contexts // []) end ) }
                      end
                  ),
                  enforce_admins: ($bpd.enforce_admins.enabled // false),
                  allow_force_pushes: ($bpd.allow_force_pushes.enabled // false),
                  allow_deletions: ($bpd.allow_deletions.enabled // false),
                  required_linear_history: ($bpd.required_linear_history.enabled // false),
                  required_signatures: ($bpd.required_signatures.enabled // false),
                  restrictions: (
                    ($bpd.restrictions // null) as $r
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
            ($bprot.rulesets.data // []) | map(
              . as $rs
              | ($bprot.ruleset_details[($rs.id | tostring)].data // {}) as $detail
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
        | . + { raw_snapshot: $s }
      )
    }
  ' > "$PREDICATE_OUT"

# The subject is a compact merge-commit identity built from the PR snapshot.
jq -n \
  --slurpfile pr "$PR_RAW_SNAPSHOT_FILE" \
  '$pr[0] as $p
   | {
       merge_commit_sha: $p.pr.merge_commit_sha,
       head_sha: $p.pr.head_sha,
       pr_number: $p.pr.pr_number,
       head_ref: $p.pr.head_ref,
       repo_url: $p.pr.repo_url,
       created_at: $p.collected_at
     }' > "$SUBJECT_OUT"

echo "Wrote ${PREDICATE_OUT} and ${SUBJECT_OUT}" >&2
