#!/usr/bin/env bash
# TraceScout source-maps upload — Action runner. The token lives ONLY in
# TRACESCOUT_AUTH_TOKEN for this process; it is never printed (the CLI
# additionally redacts Authorization headers and never logs map contents).
set -euo pipefail

ARGS=(sourcemaps upload
  --project "$TS_PROJECT"
  --release "$TS_RELEASE"
  --path "$TS_PATH"
  --url-prefix "${TS_URL_PREFIX:-~/}"
  --retries "${TS_RETRIES:-3}"
  --json)
[ -n "${TS_DIST:-}" ] && ARGS+=(--dist "$TS_DIST")
[ -n "${TS_POLICY:-}" ] && ARGS+=(--policy "$TS_POLICY")
[ "${TS_DRY_RUN:-false}" = "true" ] && ARGS+=(--dry-run)

set +e
OUT=$(npx --yes "@tracescout/cli@${TS_CLI_VERSION:-latest}" "${ARGS[@]}")
CODE=$?
set -e

# Summary WITHOUT source content or token — counts + typed error codes only.
export TS_UPLOAD_JSON="$OUT"
python3 "${TS_ACTION_DIR}/summary.py" "$CODE"
exit "$CODE"
