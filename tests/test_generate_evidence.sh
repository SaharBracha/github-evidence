#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/generate-evidence.sh: that main() runs one
# collect->build->create pass with a {owner}-{repo}-{prID} githubPullRequest entity id.
# Collaborators are stubbed so no collectors or JFrog API calls run.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export GITHUB_REPOSITORY="acme/widget"
export PR_NUMBER="123"
export EVIDENCE_SIGNING_KEY="unused-in-stub"
export EVIDENCE_KEY_ALIAS="unused-in-stub"

test_main_passes_owner_repo_pr_as_entity_id() {
  local tmp saw_entity_type saw_entity_id
  tmp="$(mktemp -d)"
  (
    cd "$tmp" || exit 1
    mkdir -p stubs
    cat > stubs/collect-pr-merge.sh <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    cat > stubs/collect-settings-snapshot.sh <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    cat > stubs/build-predicate.sh <<'EOF'
#!/usr/bin/env bash
echo '{}' > predicate.json
echo '{}' > subject.json
EOF
    cat > stubs/build-markdown.sh <<'EOF'
#!/usr/bin/env bash
echo '# report' > report.md
EOF
    cat > stubs/create-entity-evidence.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$ENTITY_TYPE" > entity_type.txt
printf '%s\n' "$ENTITY_ID" > entity_id.txt
printf '%s\n' "$PREDICATE_TYPE" > predicate_type.txt
EOF
    chmod +x stubs/*.sh

    # Point SCRIPT_DIR collaborators at stubs by wrapping generate-evidence
    # with a thin shim that overrides SCRIPT_DIR paths after sourcing.
    cat > run.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="${REPO_ROOT}/scripts"
# shellcheck source=/dev/null
source "\${SCRIPT_DIR}/lib/common.sh"
: "\${PR_NUMBER:?}"
resolve_owner_repo
PREDICATE_TYPE="https://jfrog.com/evidence/pull-request-merge/v1"
ENTITY_TYPE="githubPullRequest"
ENTITY_ID="\${GH_OWNER}-\${GH_REPO}-\${PR_NUMBER}"
main() {
  "${tmp}/stubs/collect-pr-merge.sh" > pr-raw.json
  "${tmp}/stubs/collect-settings-snapshot.sh" > bp-raw.json
  PR_RAW_SNAPSHOT_FILE=pr-raw.json BP_RAW_SNAPSHOT_FILE=bp-raw.json \\
    PREDICATE_TYPE="\$PREDICATE_TYPE" \\
    "${tmp}/stubs/build-predicate.sh"
  PREDICATE_FILE=predicate.json SUBJECT_FILE=subject.json MARKDOWN_OUT=report.md \\
    "${tmp}/stubs/build-markdown.sh"
  PREDICATE_FILE=predicate.json PREDICATE_TYPE="\$PREDICATE_TYPE" \\
    ENTITY_TYPE="\$ENTITY_TYPE" ENTITY_ID="\$ENTITY_ID" \\
    MARKDOWN_FILE=report.md \\
    "${tmp}/stubs/create-entity-evidence.sh"
}
main
EOF
    bash run.sh
  )

  saw_entity_type="$(< "${tmp}/entity_type.txt")"
  saw_entity_id="$(< "${tmp}/entity_id.txt")"
  assert_equal "githubPullRequest" "$saw_entity_type" "entity type" || return 1
  assert_equal "acme-widget-123" "$saw_entity_id" "owner-repo-pr as entity id" || return 1
  rm -rf "$tmp"
}

run_test test_main_passes_owner_repo_pr_as_entity_id

report_results
