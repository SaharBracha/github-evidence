# Branch-protection predicate

**Predicate type:** `https://jfrog.com/evidence/branch-protection/v1`
**Subject:** the collected settings snapshot, uploaded to
`git-evidence/branch-protection/<owner>-<repo>-<timestamp>.json` and attached via
`jf evd create --subject-repo-path`.

Machine-readable JSON Schema:
[`branch-protection.json`](branch-protection.json).

Every leaf that comes from a GitHub API call carries the collector's status
envelope — `collected` | `unavailable` (token lacked permission: 401/403/404/410)
| `error` — so a missing value is never read as "not configured."

## Fields

| Path | Type | Meaning |
|---|---|---|
| `schema_version` | string | `"1.0"` |
| `predicate_type` | string | `https://jfrog.com/evidence/branch-protection/v1` |
| `subject_type` | string | `"RepositoryBranchProtection"` |
| `repository.{owner,name,full_name,url}` | string | Target repo, derived from `GITHUB_REPOSITORY` |
| `collection.collected_at` | RFC3339 | When the snapshot was taken |
| `collection.collector_version` | string | e.g. `git-evidence` |
| `collection.github_api_host` | string | Supports GHES |
| `collection.workflow_run_url` | string | Provenance of the run that produced the evidence |
| `collection.token_scope_note` | string | Notes that admin-only fields may be `unavailable` under a default `GITHUB_TOKEN` |
| `summary.protected_branch_count` | int | Count of protected branches |
| `summary.ruleset_count` | int | Count of applicable rulesets (incl. inherited) |
| `summary.has_codeowners_file` | bool | CODEOWNERS present |
| `summary.codeowners_rule_count` | int | Parsed owner rules |
| `summary.codeowners_validation_errors_present` | bool | GitHub reported CODEOWNERS errors |
| `branches[]` | array | One normalized entry per protected branch (below) |
| `rulesets[]` | array | Applicable rulesets: `{id,name,enforcement,target,conditions,rules}` |
| `raw_snapshot` | object | *(optional)* the full collector document for full-fidelity audit |

## `branches[]` entry

| Path | Type | Meaning |
|---|---|---|
| `name` | string | Branch name (e.g. `master`) |
| `protection_source` | string[] | Any of `branch_protection`, `ruleset` |
| `required_pull_request_reviews.required` | bool | PR review required to merge |
| `required_pull_request_reviews.required_approving_review_count` | int | Minimum approvals |
| `required_pull_request_reviews.require_code_owner_reviews` | bool | Code-owner approval required |
| `required_pull_request_reviews.dismiss_stale_reviews` | bool | Stale approvals dismissed on push |
| `required_pull_request_reviews.require_last_push_approval` | bool | Last pusher can't self-approve |
| `required_status_checks.strict` | bool | Branch must be up to date before merge |
| `required_status_checks.checks` | string[] | Required check contexts |
| `enforce_admins` | bool | Rules apply to admins too |
| `allow_force_pushes` | bool | Force-push allowed |
| `allow_deletions` | bool | Branch deletion allowed |
| `required_linear_history` | bool | Linear history enforced |
| `required_signatures` | bool | Signed commits required |
| `restrictions.{users,teams,apps}` | string[] | Who may push (if restricted) |
| `code_owner_review_required.{via_branch_protection,via_ruleset}` | bool | Computed correlation |
| `collection_status.{protection,effective_rules}` | enum | `collected`\|`unavailable`\|`error` per source |

## Example

```json
{
  "schema_version": "1.0",
  "predicate_type": "https://jfrog.com/evidence/branch-protection/v1",
  "subject_type": "RepositoryBranchProtection",
  "repository": { "owner": "jfrog", "name": "git-evidence",
    "full_name": "jfrog/git-evidence", "url": "https://github.com/jfrog/git-evidence" },
  "collection": {
    "collected_at": "2026-07-23T09:00:00Z",
    "collector_version": "git-evidence",
    "github_api_host": "https://api.github.com",
    "workflow_run_url": "https://github.com/jfrog/git-evidence/actions/runs/123",
    "token_scope_note": "collected with the workflow GITHUB_TOKEN; admin-only fields may be 'unavailable'"
  },
  "summary": { "protected_branch_count": 1, "ruleset_count": 1,
    "has_codeowners_file": true, "codeowners_rule_count": 4,
    "codeowners_validation_errors_present": false },
  "branches": [{
    "name": "master",
    "protection_source": ["branch_protection", "ruleset"],
    "required_pull_request_reviews": {
      "required": true, "required_approving_review_count": 1,
      "require_code_owner_reviews": true, "dismiss_stale_reviews": true,
      "require_last_push_approval": false },
    "required_status_checks": { "strict": true, "checks": ["build"] },
    "enforce_admins": true, "allow_force_pushes": false, "allow_deletions": false,
    "required_linear_history": true, "required_signatures": false,
    "restrictions": { "users": [], "teams": ["release-managers"], "apps": [] },
    "code_owner_review_required": { "via_branch_protection": true, "via_ruleset": false },
    "collection_status": { "protection": "collected", "effective_rules": "collected" }
  }],
  "rulesets": [{ "id": 42, "name": "protect-master", "enforcement": "active",
    "target": "branch", "conditions": { "ref_name": { "include": ["refs/heads/master"] } },
    "rules": ["pull_request", "required_signatures"] }]
}
```

`build-predicate.sh` maps directly from the collector snapshot: `branches[]` from
`sections.branch_protection.branches[*].protection` + `effective_rules`,
`code_owner_review_required` from the computed
`sections.code_owner_enforcement.per_branch`, and `summary` from the same
document. No new GitHub API calls are needed.
