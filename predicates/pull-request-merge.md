# Pull-request-merge predicate

**Predicate type:** `https://jfrog.com/evidence/pull-request-merge/v1`
**Subject:** a small identity document for the merged PR, uploaded to
`git-evidence/pull-request-merge/<owner>-<repo>-pr-<number>.json` and attached via
`jf evd create --subject-repo-path`.

Machine-readable JSON Schema:
[`pull-request-merge.json`](pull-request-merge.json).

Recorded only when the triggering event is a **merged** pull request
(`github.event.pull_request.merged == true`). It captures who approved the PR,
which commits it added to the target branch, and who authored them.

## Fields

| Path | Type | Meaning |
|---|---|---|
| `schema_version` | string | `"1.2"` |
| `subject_type` | string | `"PullRequestMerge"` |
| `predicate_type` | string | `https://jfrog.com/evidence/pull-request-merge/v1` |
| `merge.merge_commit_sha` | string | SHA of the merge commit |
| `merge.merged_at` | string | When the PR was merged |
| `merge.merged_by` | string | Login of who merged it |
| `merge.target_branch` | string | Branch the PR merged into |
| `merge.target_base_sha` | string | Base SHA on the target branch before the merge |
| `approvers[]` | array | One entry per approving review (below) |
| `commits_on_target_branch[]` | string[] | SHAs the PR added to the target branch |
| `code_committers[]` | array | Distinct commit authors: `{login, email}` |
| `collection.collected_at` | string | UTC timestamp of collection |
| `collection.workflow_run_url` | string | Provenance of the run that produced the evidence |

## `approvers[]` entry

| Path | Type | Meaning |
|---|---|---|
| `review_id` | integer | GitHub review id |
| `login` | string \| null | Reviewer login |
| `body` | string | Review comment body |
| `submitted_at` | string \| null | When the review was submitted |
| `approved_sha` | string | Commit SHA the approval was against |
| `is_pr_head_approval` | boolean | Whether the approval was against the merged PR head |

## Subject document

The uploaded subject is `{head_sha, pr_number, head_ref, repo_url, created_at}`,
identifying the exact commit the evidence is about.

## Example

```json
{
  "schema_version": "1.2",
  "subject_type": "PullRequestMerge",
  "predicate_type": "https://jfrog.com/evidence/pull-request-merge/v1",
  "merge": {
    "merge_commit_sha": "9f2c…",
    "merged_at": "2026-07-23T09:00:00Z",
    "merged_by": "octocat",
    "target_branch": "main",
    "target_base_sha": "1a2b…"
  },
  "approvers": [{
    "review_id": 123456,
    "login": "reviewer-1",
    "body": "LGTM",
    "submitted_at": "2026-07-23T08:50:00Z",
    "approved_sha": "abcd…",
    "is_pr_head_approval": true
  }],
  "commits_on_target_branch": ["abcd…", "ef01…"],
  "code_committers": [{ "login": "author-1", "email": "author-1@example.com" }],
  "collection": {
    "collected_at": "2026-07-23T09:00:01.000Z",
    "workflow_run_url": "https://github.com/jfrog/git-evidence/actions/runs/123"
  }
}
```

`build-predicate.sh` maps this directly from `collect-pr-merge.sh` output; no
`review` block is emitted (dropped in schema `1.2`).
