#!/usr/bin/env bash
# Launch one Cursor Cloud Agent with a prompt file or stdin.
# Intended for Grok Bot / humans. Phase scripts use the same provider via make phase-*.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/docs/ai-product-slice-harness/subagent-runner.sh"
HARNESS_AGENT_PROVIDER=cursor

usage() {
  cat <<'EOF'
Usage:
  cursor-agent-launch.sh --prompt-file PATH [--label RUN-LABEL] [--status-label TEXT]
  cursor-agent-launch.sh --label RUN-LABEL < prompt.txt

Launches one Cursor Cloud Agent against the configured repository.
Does not invoke Codex. Records agent_id in subagents/status/.

Environment:
  CURSOR_API_KEY              required unless HARNESS_CURSOR_DRY_RUN=1
  HARNESS_CURSOR_REPO         override git origin
  HARNESS_CURSOR_REF          override current branch
  HARNESS_CURSOR_MODEL        default: default (account/team default; not a paid model id)
  HARNESS_CURSOR_WAIT         0=fire-and-forget (default), 1=poll until terminal
  HARNESS_CURSOR_DRY_RUN      1=write status/payload locally, do not call the API
  HARNESS_CURSOR_AUTO_CREATE_PR  default 1
EOF
}

LABEL="ad-hoc"
STATUS_LABEL="cursor-ad-hoc"
PROMPT_FILE=""
PHASE_NAME="${HARNESS_PHASE:-cursor-ad-hoc}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file)
      PROMPT_FILE="$2"
      shift 2
      ;;
    --label)
      LABEL="$2"
      shift 2
      ;;
    --status-label)
      STATUS_LABEL="$2"
      shift 2
      ;;
    --phase)
      PHASE_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$PROMPT_FILE" ]]; then
  prompt="$(cat "$PROMPT_FILE")"
elif [[ ! -t 0 ]]; then
  prompt="$(cat)"
else
  echo "Pass --prompt-file PATH or pipe a prompt on stdin." >&2
  usage >&2
  exit 2
fi

start_phase "$PHASE_NAME"
_run_cursor_agent "$LABEL" "$STATUS_LABEL" "$prompt"
