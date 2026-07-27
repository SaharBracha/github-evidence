#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Verifies a settings snapshot produced by
# scripts/branch-protection/collect-settings-snapshot.sh.
#
# Reads the snapshot JSON document on stdin and confirms it is a well-formed,
# live snapshot of the intended repository. Exits non-zero on any
# hard-assertion failure, so it can gate the CI smoke-test job (fed the real
# collector's output) and be exercised deterministically by
# tests/test_assert_snapshot.sh (fed canned snapshots).
#
# Balanced by design: a section that is `unavailable` (permission_denied /
# not_found / not_supported) is an expected, successful outcome for a
# contents:read token and does NOT fail this check. What fails is a run that
# did not genuinely collect settings:
#   - content that is not a single valid JSON document;
#   - the wrong schema_version or repository identity;
#   - a missing top-level section;
#   - ANY field with status "error" (unexpected 5xx / network / bad shape);
#   - repository metadata that was not `collected` (the liveness anchor - any
#     valid token can read it, so its absence means the run is broken).
set -euo pipefail

EXPECTED_SCHEMA_VERSION="1.0.0"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set so repository identity can be verified}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

body="$(cat)"

printf '%s' "$body" | jq -e . >/dev/null 2>&1 || fail "snapshot is not a single valid JSON document"

schema_version="$(printf '%s' "$body" | jq -r '.schema_version // empty')"
[[ "$schema_version" == "$EXPECTED_SCHEMA_VERSION" ]] \
  || fail "schema_version should be ${EXPECTED_SCHEMA_VERSION}, got '${schema_version}'"

full_name="$(printf '%s' "$body" | jq -r '.repository.full_name // empty')"
[[ "$full_name" == "$GITHUB_REPOSITORY" ]] \
  || fail "repository.full_name should be '${GITHUB_REPOSITORY}', got '${full_name}'"

for section in branch_protection code_owners code_owner_enforcement repository_access; do
  printf '%s' "$body" | jq -e --arg s "$section" '.sections | has($s)' >/dev/null 2>&1 \
    || fail "top-level section '.sections.${section}' is missing"
done

# Walk the whole document for any field that failed unexpectedly. "error" is
# reserved for network errors, 5xx, or unexpected response shapes - never a
# permission/absence outcome - so any occurrence must fail the smoke-test
# rather than pass silently.
error_paths="$(printf '%s' "$body" \
  | jq -r '[paths(objects | select(.status? == "error")) | map(tostring) | join(".")] | .[]')"
if [[ -n "$error_paths" ]]; then
  echo "Fields with status \"error\" (unexpected failures):" >&2
  printf '%s\n' "$error_paths" | sed 's/^/  ./' >&2
  error_count="$(printf '%s\n' "$error_paths" | grep -c . || true)"
  fail "the snapshot contains ${error_count} field(s) with status \"error\""
fi

# Liveness anchor: repository metadata is readable by any valid token, so if
# it is not `collected` the run did not genuinely reach the API.
repo_status="$(printf '%s' "$body" | jq -r '.sections.repository_access.repository.status // empty')"
[[ "$repo_status" == "collected" ]] \
  || fail "repository metadata was not collected (status='${repo_status}'); the run did not genuinely collect settings"

# Informative summary - mirrors what a human would read off the log.
collected="$(printf '%s' "$body" | jq '[.. | objects | select(.status? == "collected")] | length')"
unavailable="$(printf '%s' "$body" | jq '[.. | objects | select(.status? == "unavailable")] | length')"
errors="$(printf '%s' "$body" | jq '[.. | objects | select(.status? == "error")] | length')"
echo "Snapshot verified for ${full_name}: ${collected} collected, ${unavailable} unavailable, ${errors} error."
echo "PASS"
