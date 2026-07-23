#!/usr/bin/env bash
# Renders a human-readable, per-run markdown report from a normalized predicate
# document. The report is attached alongside the JSON predicate via
# `jf evd create --markdown` so the evidence is legible in the JFrog UI.
#
# The JFrog Evidence markdown viewer HTML-escapes and then literally displays
# the characters " < > (as &#34; &lt; &gt;). Everything emitted here therefore
# avoids those characters: no JSON/quotes/angle-brackets, only headings, bold
# bullet lists, backtick code spans, tables, and markdown links. A `safe`
# helper strips any stray " < > that sneaks in from collected data.
#
# Required env: EVIDENCE_TYPE, PREDICATE_FILE.
# Optional env: SUBJECT_FILE (pull-request-merge identity), MARKDOWN_OUT
#               (default markdown.md).
set -euo pipefail

: "${EVIDENCE_TYPE:?EVIDENCE_TYPE must be set}"
: "${PREDICATE_FILE:?PREDICATE_FILE must be set}"
MARKDOWN_OUT="${MARKDOWN_OUT:-markdown.md}"

case "$EVIDENCE_TYPE" in
  pull-request-merge)
    subject_json='{}'
    if [ -n "${SUBJECT_FILE:-}" ] && [ -f "$SUBJECT_FILE" ]; then
      subject_json="$(< "$SUBJECT_FILE")"
    fi

    jq -r --argjson subj "$subject_json" '
      def safe: if . == null then "" else (tostring | gsub("[<>\"]"; "") | gsub("\\|"; "\\|")) end;
      def dash: if . == null or . == "" then "—" else (. | safe) end;
      def repo_slug: ($subj.repo_url // "") | safe | (split("/") | if length >= 2 then .[-2:] | join("/") else (. | join("/")) end);

      "# Pull Request Merge Evidence Report\n"
      + "\n## Summary\n"
      + "- **Repository:** " + (repo_slug | if . == "" then "—" else . end) + "\n"
      + "- **Pull request:** #" + (($subj.pr_number // "—") | safe) + "\n"
      + "- **Target branch:** " + (.merge.target_branch | dash) + "\n"
      + "- **Merged by:** " + (.merge.merged_by | dash) + "\n"
      + "- **Merged at:** " + (.merge.merged_at | dash) + "\n"
      + "\n## Merge Details\n"
      + "- **Merge commit:** `" + (.merge.merge_commit_sha | dash) + "`\n"
      + "- **Target base SHA:** `" + (.merge.target_base_sha | dash) + "`\n"
      + "- **Head branch:** " + (($subj.head_ref // null) | dash) + "\n"
      + "- **Head SHA:** `" + (($subj.head_sha // null) | dash) + "`\n"
      + "- **Collected at:** " + (.collection.collected_at | dash) + "\n"
      + "- **Workflow run:** " + (.collection.workflow_run_url | dash) + "\n"
      + "\n## Approvers (" + ((.approvers // []) | length | tostring) + ")\n\n"
      + (if ((.approvers // []) | length) == 0 then "_None_\n"
         else "| Login | Submitted At | Approved PR Head |\n|---|---|---|\n"
           + ((.approvers // []) | map(
               "| " + (.login | dash) + " | " + (.submitted_at | dash) + " | "
               + (if .is_pr_head_approval then "yes" else "no" end) + " |"
             ) | join("\n")) + "\n" end)
      + "\n## Commits on Target Branch (" + ((.commits_on_target_branch // []) | length | tostring) + ")\n\n"
      + (if ((.commits_on_target_branch // []) | length) == 0 then "_None_\n"
         else ((.commits_on_target_branch // []) | map("- `" + (. | safe) + "`") | join("\n")) + "\n" end)
      + "\n## Code Committers (" + ((.code_committers // []) | length | tostring) + ")\n\n"
      + (if ((.code_committers // []) | length) == 0 then "_None_\n"
         else "| Login | Email |\n|---|---|\n"
           + ((.code_committers // []) | map(
               "| " + (.login | dash) + " | "
               + ((.email // "") | safe | if . == "" then "—" else "[" + . + "](mailto:" + . + ")" end) + " |"
             ) | join("\n")) + "\n" end)
    ' "$PREDICATE_FILE" > "$MARKDOWN_OUT"
    ;;

  branch-protection)
    jq -r '
      def safe: if . == null then "" else (tostring | gsub("[<>\"]"; "") | gsub("\\|"; "\\|")) end;
      def dash: if . == null or . == "" then "—" else (. | safe) end;
      def yn: if . then "yes" else "no" end;
      (.raw_snapshot.sections.branch_protection.rulesets // {}) as $rs_raw
      | "# Branch Protection Evidence Report\n"
      + "\n## Summary\n"
      + "- **Repository:** [" + (.repository.full_name | dash) + "](" + ((.repository.url // "") | safe) + ")\n"
      + "- **Protected branches:** " + ((.summary.protected_branch_count // 0) | tostring) + "\n"
      + "- **Rulesets:** " + ((.summary.ruleset_count // 0) | tostring) + "\n"
      + "- **CODEOWNERS file:** " + ((.summary.has_codeowners_file // false) | yn) + "\n"
      + "- **CODEOWNERS rules:** " + ((.summary.codeowners_rule_count // 0) | tostring) + "\n"
      + "- **Collected at:** " + (.collection.collected_at | dash) + "\n"
      + "- **Workflow run:** " + (.collection.workflow_run_url | dash) + "\n"
      + "\n## Branches\n\n"
      + (if ((.branches // []) | length) == 0 then "_No protected branches configured._\n"
         else "| Branch | Reviews Required | Approvals | Code-owner Review | Status Checks | Enforce Admins | Force Pushes |\n"
           + "|---|---|---|---|---|---|---|\n"
           + ((.branches // []) | map(
               "| `" + (.name | safe) + "` | "
               + ((.required_pull_request_reviews.required // false) | if . then "yes" else "no" end) + " | "
               + ((.required_pull_request_reviews.required_approving_review_count // 0) | tostring) + " | "
               + ((.required_pull_request_reviews.require_code_owner_reviews // false) | yn) + " | "
               + (((.required_status_checks.checks // []) | map(safe) | join(", ")) | if . == "" then "—" else . end)
               + (if (.required_status_checks.strict // false) then " (strict)" else "" end) + " | "
               + ((.enforce_admins // false) | yn) + " | "
               + ((.allow_force_pushes // false) | if . then "allowed" else "blocked" end) + " |"
             ) | join("\n")) + "\n" end)
      + "\n## Rulesets\n\n"
      + (if ((.rulesets // []) | length) > 0 then
           "| Name | Enforcement | Target | Rules |\n|---|---|---|---|\n"
           + ((.rulesets // []) | map(
               "| " + (.name | dash) + " | " + (.enforcement | dash) + " | " + (.target | dash)
               + " | " + (((.rules // []) | map(safe) | join(", ")) | if . == "" then "—" else . end) + " |"
             ) | join("\n")) + "\n"
         elif ($rs_raw.status // "") == "unavailable" then
           "_Unavailable: " + (($rs_raw.message // "not accessible with this token") | safe) + "_\n"
         else "_No rulesets configured._\n" end)
    ' "$PREDICATE_FILE" > "$MARKDOWN_OUT"
    ;;

  *)
    echo "::error::unknown EVIDENCE_TYPE: ${EVIDENCE_TYPE}" >&2
    exit 1
    ;;
esac

echo "Wrote ${MARKDOWN_OUT}" >&2
