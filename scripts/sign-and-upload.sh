#!/usr/bin/env bash
# Uploads the subject artifact (optional) and attaches signed JFrog evidence to
# it with the JFrog CLI. Assumes the CLI is already configured (jf c / env), as
# the setup-jfrog-cli step in action.yml does.
#
# Required env: SUBJECT_FILE, SUBJECT_REPO_PATH, PREDICATE_FILE, PREDICATE_TYPE,
#               PROJECT_KEY, EVIDENCE_SIGNING_KEY, EVIDENCE_KEY_ALIAS.
# Optional env: UPLOAD_SUBJECT (default "true"),
#               MARKDOWN_FILE (human-readable report attached via --markdown).
set -euo pipefail
# This script writes the private signing key to disk. Force xtrace off so an
# inherited `set -x` or RUNNER_DEBUG=1 can never echo the PEM into the run log.
set +x

: "${SUBJECT_FILE:?SUBJECT_FILE must be set}"
: "${SUBJECT_REPO_PATH:?SUBJECT_REPO_PATH must be set}"
: "${PREDICATE_FILE:?PREDICATE_FILE must be set}"
: "${PREDICATE_TYPE:?PREDICATE_TYPE must be set}"
: "${PROJECT_KEY:?PROJECT_KEY must be set}"
: "${EVIDENCE_SIGNING_KEY:?EVIDENCE_SIGNING_KEY must be set}"
: "${EVIDENCE_KEY_ALIAS:?EVIDENCE_KEY_ALIAS must be set}"
UPLOAD_SUBJECT="${UPLOAD_SUBJECT:-true}"

jf rt ping

if [ "$UPLOAD_SUBJECT" = "true" ]; then
  echo "Uploading subject ${SUBJECT_FILE} to ${SUBJECT_REPO_PATH}" >&2
  jf rt upload "$SUBJECT_FILE" "$SUBJECT_REPO_PATH"
else
  echo "Skipping subject upload for existing subject ${SUBJECT_REPO_PATH}" >&2
fi

# Register cleanup before creating the key file, and create it with a
# restrictive umask, so the private key is never briefly world-readable and is
# always removed on exit (including if a signal arrives mid-write).
trap 'rm -f evidence-signing-key.pem' EXIT
( umask 077; printf '%s\n' "$EVIDENCE_SIGNING_KEY" > evidence-signing-key.pem )
chmod 600 evidence-signing-key.pem

evd_args=(
  --subject-repo-path "$SUBJECT_REPO_PATH"
  --predicate "$PREDICATE_FILE"
  --key ./evidence-signing-key.pem
  --key-alias "$EVIDENCE_KEY_ALIAS"
  --predicate-type "$PREDICATE_TYPE"
  --project "$PROJECT_KEY"
)

if [ -n "${MARKDOWN_FILE:-}" ]; then
  if [ -f "$MARKDOWN_FILE" ]; then
    echo "Attaching markdown report ${MARKDOWN_FILE}" >&2
    evd_args+=(--markdown "$MARKDOWN_FILE")
  else
    echo "::warning::MARKDOWN_FILE set but not found: ${MARKDOWN_FILE}; skipping --markdown" >&2
  fi
fi

jf evd create "${evd_args[@]}"

echo "Evidence uploaded successfully" >&2
