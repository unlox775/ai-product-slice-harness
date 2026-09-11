#!/usr/bin/env bash
# Refresh Cursor Cloud Agent status files written by the harness.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/docs/ai-product-slice-harness/subagent-runner.sh"

usage() {
  cat <<'EOF'
Usage:
  cursor-agent-status.sh [--wait] [--phase PHASE] [--agent-id ID] [status-file...]

With no files, refreshes every Cursor job in subagents/status/ that still
has a first-line status of running or launched.

  --wait         Poll until those jobs are terminal (or timeout)
  --phase NAME   Limit to status files for one phase
  --agent-id ID  GET one agent from the API and print JSON (no status rewrite)

Environment:
  CURSOR_API_KEY
  HARNESS_CURSOR_POLL_SECONDS   default 15
  HARNESS_CURSOR_WAIT_TIMEOUT   seconds; 0 means no limit
  HARNESS_CURSOR_DRY_RUN        1=do not call the API
EOF
}

WAIT=0
PHASE=""
AGENT_ID=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait)
      WAIT=1
      shift
      ;;
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --agent-id)
      AGENT_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$AGENT_ID" ]]; then
  if _cursor_dry_run; then
    echo '{"id":"'"$AGENT_ID"'","status":"DRY_RUN"}'
    exit 0
  fi
  if [[ -z "$(_cursor_api_key)" ]]; then
    echo "CURSOR_API_KEY is not set." >&2
    exit 1
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/harness-cursor-get.XXXXXX")"
  if ! _cursor_http GET "/v0/agents/${AGENT_ID}" "" "$tmp"; then
    echo "GET /v0/agents/${AGENT_ID} failed (HTTP ${HARNESS_CURSOR_HTTP_CODE:-n/a})" >&2
    cat "$tmp" >&2 || true
    rm -f "$tmp"
    exit 1
  fi
  cat "$tmp"
  echo
  rm -f "$tmp"
  exit 0
fi

collect_cursor_status_files() {
  local file provider current
  HARNESS_CURSOR_STATUS_FILES=()
  shopt -s nullglob
  local candidates=()
  if [[ "${#FILES[@]}" -gt 0 ]]; then
    candidates=("${FILES[@]}")
  elif [[ -n "$PHASE" ]]; then
    candidates=("$HARNESS_STATUS_DIR/${PHASE}-"*.status)
  else
    candidates=("$HARNESS_STATUS_DIR/"*.status)
  fi

  for file in "${candidates[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "missing status file: $file" >&2
      continue
    fi
    provider="$(_cursor_read_status_field "$file" "provider")"
    current="$(sed -n '1p' "$file")"
    if [[ "$provider" != "cursor" ]]; then
      continue
    fi
    case "$current" in
      running|launched)
        HARNESS_CURSOR_STATUS_FILES+=("$file")
        ;;
    esac
  done
}

refresh_all() {
  local file failed
  failed=0
  collect_cursor_status_files
  if [[ "${#HARNESS_CURSOR_STATUS_FILES[@]}" -eq 0 ]]; then
    echo "No running Cursor harness jobs found."
    return 0
  fi
  for file in "${HARNESS_CURSOR_STATUS_FILES[@]}"; do
    if ! _cursor_refresh_status_file "$file"; then
      failed=1
    fi
  done
  return "$failed"
}

if [[ "$WAIT" != "1" ]]; then
  refresh_all
  exit
fi

interval="${HARNESS_CURSOR_POLL_SECONDS:-15}"
timeout="${HARNESS_CURSOR_WAIT_TIMEOUT:-0}"
start="$(date +%s)"

while true; do
  refresh_all || true
  collect_cursor_status_files
  if [[ "${#HARNESS_CURSOR_STATUS_FILES[@]}" -eq 0 ]]; then
    echo "All known Cursor harness jobs are terminal (or dry-run)."
    exit 0
  fi
  now="$(date +%s)"
  elapsed=$((now - start))
  if [[ "$timeout" -gt 0 && "$elapsed" -ge "$timeout" ]]; then
    echo "Timed out after ${elapsed}s with ${#HARNESS_CURSOR_STATUS_FILES[@]} Cursor job(s) still running." >&2
    exit 1
  fi
  echo "Waiting ${interval}s for ${#HARNESS_CURSOR_STATUS_FILES[@]} Cursor job(s)..."
  sleep "$interval"
done
