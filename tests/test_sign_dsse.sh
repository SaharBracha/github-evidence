#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/lib/sign-dsse.mjs: PAE signing produces a valid DSSE envelope
# shape and keyid, and can verify with the matching public key (RSA).
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

SIGN_DSSE="${REPO_ROOT}/scripts/lib/sign-dsse.mjs"

test_sign_dsse_envelope_shape_and_verify() {
  local tmp payload_b64 envelope keyid sig_ok
  tmp="$(mktemp -d)"

  openssl genrsa -out "${tmp}/key.pem" 2048 >/dev/null 2>&1
  openssl rsa -in "${tmp}/key.pem" -pubout -out "${tmp}/pub.pem" >/dev/null 2>&1

  payload_b64="$(printf '{"_type":"https://in-toto.io/Statement/v1","subject":[{"name":"githubPullRequest","digest":{"githubPullRequest":"abc123"}}]}' | base64 | tr -d '\n')"
  jq -n \
    --arg payload "$payload_b64" \
    '{dsse_payload: $payload, dsse_payload_type: "application/vnd.in-toto+json", post_url: "/evidence/api/v1/entity/githubPullRequest/abc123"}' \
    > "${tmp}/prep.json"

  envelope="$(node "$SIGN_DSSE" \
    --prepare-response "${tmp}/prep.json" \
    --key "${tmp}/key.pem" \
    --key-id "my-alias")"

  assert_valid_json "$envelope" "envelope is JSON" || { rm -rf "$tmp"; return 1; }
  keyid="$(printf '%s' "$envelope" | jq -r '.signatures[0].keyid')"
  assert_equal "my-alias" "$keyid" "signature keyid" || { rm -rf "$tmp"; return 1; }
  assert_equal "$payload_b64" "$(printf '%s' "$envelope" | jq -r '.payload')" "payload echoed" || { rm -rf "$tmp"; return 1; }
  assert_equal "application/vnd.in-toto+json" "$(printf '%s' "$envelope" | jq -r '.payloadType')" "payloadType" || { rm -rf "$tmp"; return 1; }

  # Verify RSA-SHA256 PKCS#1 signature over DSSE PAE.
  printf '%s' "$envelope" | jq -r '.signatures[0].sig' | base64 -d > "${tmp}/sig.bin"
  payload_raw="$(printf '%s' "$envelope" | jq -r '.payload' | base64 -d)"
  payload_type="$(printf '%s' "$envelope" | jq -r '.payloadType')"
  {
    printf 'DSSEv1 %s %s %s ' "${#payload_type}" "$payload_type" "${#payload_raw}"
    printf '%s' "$payload_raw"
  } > "${tmp}/pae.bin"

  if openssl dgst -sha256 -verify "${tmp}/pub.pem" -signature "${tmp}/sig.bin" "${tmp}/pae.bin" >/dev/null 2>&1; then
    sig_ok=true
  else
    sig_ok=false
  fi
  assert_true "$sig_ok" "openssl verifies DSSE PAE signature" || { rm -rf "$tmp"; return 1; }

  rm -rf "$tmp"
}

test_sign_dsse_rejects_missing_args() {
  local rc
  set +e
  node "$SIGN_DSSE" --key /dev/null >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAIL: expected non-zero exit for missing args" >&2
    return 1
  fi
  return 0
}

run_test test_sign_dsse_envelope_shape_and_verify
run_test test_sign_dsse_rejects_missing_args

report_results
