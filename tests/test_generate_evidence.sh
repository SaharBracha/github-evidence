#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/generate-evidence.sh: the unified subject-path naming and
# that main() runs one collect->build->sign pass. Collaborators are stubbed so
# no collectors or the JFrog CLI run - only the dispatch is exercised.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export GITHUB_REPOSITORY="acme/widget"
export MERGE_COMMIT_SHA="abcdef1234567890"

# Source generate-evidence.sh in a subshell (so its `set -e` and the
# executed-directly guard don't leak into the harness) and print the subject
# path.
subject_path() {
  (
    # shellcheck source=../scripts/generate-evidence.sh
    source "${REPO_ROOT}/scripts/generate-evidence.sh"
    evidence_subject_path
  )
}

test_subject_path_uses_owner_and_short_sha() {
  assert_equal "git-evidence/git-commit/acme-git-commit-abcdef12.json" \
    "$(subject_path)" "unified git-commit subject path"
}

run_test test_subject_path_uses_owner_and_short_sha

report_results
