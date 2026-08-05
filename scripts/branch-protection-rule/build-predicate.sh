#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Shapes the branch_protection_rule event payload + full branch-protection API
# snapshot into the "branch-protection-rule" predicate and its subject file.
# Writes predicate.json and subject.json (paths overridable via
# PREDICATE_OUT / SUBJECT_OUT).
#
# Required env: EVENT_PAYLOAD_FILE, SNAPSHOT_FILE.
# Optional env: PREDICATE_TYPE (default branch-protection-rule/v1),
#   PREDICATE_OUT, SUBJECT_OUT, APP_KEY (recorded in the predicate for audit).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

: "${EVENT_PAYLOAD_FILE:?EVENT_PAYLOAD_FILE must be set}"
: "${SNAPSHOT_FILE:?SNAPSHOT_FILE must be set}"
PREDICATE_OUT="${PREDICATE_OUT:-predicate.json}"
SUBJECT_OUT="${SUBJECT_OUT:-subject.json}"

PREDICATE_TYPE="${PREDICATE_TYPE:-https://jfrog.com/evidence/branch-protection-rule/v1}"

for f in "$EVENT_PAYLOAD_FILE" "$SNAPSHOT_FILE"; do
  if ! jq -e 'if . == null then false else true end' "$f" >/dev/null 2>&1; then
    echo "::error::file ${f} is missing, empty, or not valid JSON" >&2
    exit 1
  fi
done

collected_at="$(rfc3339_now)"
run_url="$(workflow_run_url)"

jq -n \
  --arg schema_version "1.0.0" \
  --arg subject_type "GithubBranchProtectionRule" \
  --arg predicate_type "$PREDICATE_TYPE" \
  --arg app_key "${APP_KEY:-}" \
  --arg collected_at "$collected_at" \
  --arg run_url "$run_url" \
  --slurpfile event "$EVENT_PAYLOAD_FILE" \
  --slurpfile snapshot "$SNAPSHOT_FILE" \
  '
  $event[0] as $e
  | $snapshot[0] as $s
  | {
      schema_version: $schema_version,
      subject_type: $subject_type,
      predicate_type: $predicate_type,
      branch_protection_rule: {
        event: {
          action: $e.action,
          rule: $e.rule,
          changes: ($e.changes // null),
          sender: ($e.sender // null),
          repository: (
            $e.repository
            | if . == null then null
              else {full_name: .full_name, id: .id, default_branch: .default_branch}
              end
          )
        },
        app_key: (if $app_key == "" then null else $app_key end),
        repository_snapshot: $s,
        collection: {
          collected_at: $collected_at,
          workflow_run_url: $run_url
        }
      }
    }
  ' > "$PREDICATE_OUT"

jq -n \
  --arg collected_at "$collected_at" \
  --slurpfile event "$EVENT_PAYLOAD_FILE" \
  '$event[0] as $e
   | {
       repository_full_name: ($e.repository.full_name // null),
       rule_id: ($e.rule.id // null),
       rule_pattern: ($e.rule.name // $e.rule.pattern // null),
       action: $e.action,
       created_at: $collected_at
     }' > "$SUBJECT_OUT"

echo "Wrote ${PREDICATE_OUT} and ${SUBJECT_OUT}" >&2
