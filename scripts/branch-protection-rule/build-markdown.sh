#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Renders a human-readable markdown report for the branch-protection-rule
# predicate. The JFrog Evidence markdown viewer HTML-escapes " < > (rendering
# them as &#34; &lt; &gt;), so this report avoids those characters and pipes
# any collected data through a `safe` helper.
#
# Required env: PREDICATE_FILE.
# Optional env: SUBJECT_FILE, MARKDOWN_OUT (default markdown.md).
set -euo pipefail

: "${PREDICATE_FILE:?PREDICATE_FILE must be set}"
MARKDOWN_OUT="${MARKDOWN_OUT:-markdown.md}"

MD_HELPERS='
  def safe: if . == null then "" else (tostring | gsub("[<>\"]"; "") | gsub("\\|"; "\\|")) end;
  def dash: if . == null or . == "" then "—" else (. | safe) end;
  def yn(x): if x == true then "yes" elif x == false then "no" else "—" end;
'

subject_json='{}'
if [ -n "${SUBJECT_FILE:-}" ] && [ -f "$SUBJECT_FILE" ]; then
  subject_json="$(< "$SUBJECT_FILE")"
fi

jq -r --argjson subj "$subject_json" "$MD_HELPERS"'
  .branch_protection_rule as $bpr
  | $bpr.event as $e
  | ($bpr.repository_snapshot.sections.branch_protection // null) as $bp
  | ($bpr.repository_snapshot.sections.code_owner_enforcement // null) as $coe

  | "# Branch Protection Rule Evidence Report\n"

  + "\n## Summary\n"
  + "- **Repository:** " + (($e.repository.full_name // $subj.repository_full_name) | dash) + "\n"
  + "- **Action:** " + ($e.action | dash) + "\n"
  + "- **Rule pattern:** `" + (($e.rule.name // $e.rule.pattern // $subj.rule_pattern) | dash) + "`\n"
  + "- **Rule id:** " + (($e.rule.id // $subj.rule_id) | dash) + "\n"
  + "- **Sender:** " + (($e.sender.login // null) | dash) + "\n"
  + "- **Collected at:** " + ($bpr.collection.collected_at | dash) + "\n"
  + "- **Workflow run:** " + ($bpr.collection.workflow_run_url | dash) + "\n"
  + "- **App key:** " + ($bpr.app_key | dash) + "\n"

  + "\n## Rule\n"
  + (if $e.rule == null then "_No rule payload_\n"
     else "- **Requires approving reviews:** " + (yn($e.rule.required_approving_review_count != null and $e.rule.required_approving_review_count > 0)) + "\n"
       + "- **Required approving review count:** " + (($e.rule.required_approving_review_count // 0) | tostring | safe) + "\n"
       + "- **Dismiss stale reviews on push:** " + (yn($e.rule.dismiss_stale_reviews_on_push)) + "\n"
       + "- **Require code owner review:** " + (yn($e.rule.require_code_owner_review)) + "\n"
       + "- **Required status checks strict:** " + (yn($e.rule.strict_required_status_checks_policy)) + "\n"
       + "- **Signature requirement enforcement level:** " + (($e.rule.signature_requirement_enforcement_level // "—") | dash) + "\n"
     end)

  + "\n## Changes\n"
  + (if $e.changes == null or ($e.changes | length) == 0 then "_No changes reported_\n"
     else "| Field | From | To |\n|---|---|---|\n"
       + ($e.changes | to_entries | map(
           "| " + (.key | safe) + " | "
           + (.value.from | dash) + " | "
           + ((.value.to // null) | dash) + " |"
         ) | join("\n")) + "\n" end)

  + "\n## Repository Snapshot\n"
  + (if $bp == null then "_No snapshot collected_\n"
     else "- **Protected branches collected:** " + yn(($bp.protected_branches.status // "") == "collected") + "\n"
       + "- **Branches with details:** " + (($bp.branches // {} | length) | tostring | safe) + "\n"
       + "- **Rulesets collected:** " + yn(($bp.rulesets.status // "") == "collected") + "\n"
     end)

  + "\n## Code-owner Enforcement\n"
  + (if $coe == null then "_Not collected_\n"
     else "- **CODEOWNERS file present:** " + yn($coe.has_codeowners_file) + "\n"
       + "- **Owner rules:** " + (($coe.owner_rule_count // 0) | tostring | safe) + "\n"
       + "- **Validation errors present:** " + yn($coe.codeowners_validation_errors_present) + "\n"
     end)
' "$PREDICATE_FILE" > "$MARKDOWN_OUT"

echo "Wrote ${MARKDOWN_OUT}" >&2
