#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests the ?application=<APP_KEY> URL rewrite in create-entity-evidence.sh by
# stubbing `jf` on PATH and inspecting the URL passed to it.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"
CREATE_SCRIPT="${REPO_ROOT}/scripts/create-entity-evidence.sh"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

# Runs create-entity-evidence.sh with a stubbed `jf` that:
#   - returns a fixed prepare response containing $post_url
#   - captures the create URL to $tmp/create-url.txt
# Also stubs `node` to write a minimal envelope.json.
# Args: $1 tmp dir  $2 post_url  $3 APP_KEY (may be empty)
run_create() {
  local tmp="$1" post_url="$2" app_key="$3"
  cat > "${tmp}/jf" <<STUB
#!/usr/bin/env bash
# Args from create-entity-evidence.sh:
#   1: api
#   ...
#   last arg is the URL (or endpoint for prepare)
url="\${!#}"
if [[ "\$url" == "/evidence/api/v1/evidence/prepare" ]]; then
  cat <<'RESP'
{"post_url": "${post_url}", "payload": {}}
RESP
  exit 0
fi
printf '%s' "\$url" > "${tmp}/create-url.txt"
echo '{"ok":true}'
exit 0
STUB
  chmod +x "${tmp}/jf"

  cat > "${tmp}/node" <<'STUB'
#!/usr/bin/env bash
echo '{"payload":"","payloadType":"","signatures":[]}'
STUB
  chmod +x "${tmp}/node"

  printf '%s' '{"pull_request_merge":{}}' > "${tmp}/predicate.json"

  (
    cd "$tmp"
    PATH="${tmp}:$PATH" \
      PREDICATE_FILE="${tmp}/predicate.json" \
      PREDICATE_TYPE="https://example.com/x/v1" \
      ENTITY_TYPE="application" \
      ENTITY_ID="my-app" \
      EVIDENCE_SIGNING_KEY="dummy" \
      EVIDENCE_KEY_ALIAS="alias" \
      APP_KEY="$app_key" \
      "$CREATE_SCRIPT" >/dev/null 2>&1
  )
}

test_app_key_appended_when_no_query() {
  local tmp; tmp="$(mktemp -d)"
  if ! run_create "$tmp" "/evidence/api/v1/entity/application/my-app" "my-app"; then
    rm -rf "$tmp"; return 1
  fi
  local url; url="$(cat "${tmp}/create-url.txt")"
  assert_equal "/evidence/api/v1/entity/application/my-app?application=my-app" "$url" "url with ?application=" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

test_app_key_appended_with_ampersand_when_existing_query() {
  local tmp; tmp="$(mktemp -d)"
  if ! run_create "$tmp" "/evidence/api/v1/entity/application/my-app?foo=bar" "my-app"; then
    rm -rf "$tmp"; return 1
  fi
  local url; url="$(cat "${tmp}/create-url.txt")"
  assert_equal "/evidence/api/v1/entity/application/my-app?foo=bar&application=my-app" "$url" "url with &application=" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

test_no_app_key_leaves_url_untouched() {
  local tmp; tmp="$(mktemp -d)"
  if ! run_create "$tmp" "/evidence/api/v1/entity/githubPullRequest/xxx" ""; then
    rm -rf "$tmp"; return 1
  fi
  local url; url="$(cat "${tmp}/create-url.txt")"
  assert_equal "/evidence/api/v1/entity/githubPullRequest/xxx" "$url" "url unchanged when APP_KEY unset" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

run_test test_app_key_appended_when_no_query
run_test test_app_key_appended_with_ampersand_when_existing_query
run_test test_no_app_key_leaves_url_untouched

report_results
