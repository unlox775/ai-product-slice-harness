#!/usr/bin/env bash

# Cursor Cloud Agents provider for Phase 03+ harness jobs.
#
# Uses the stable v0 Cloud Agents API (v1 is still public beta):
#   POST https://api.cursor.com/v0/agents
#   GET  https://api.cursor.com/v0/agents/{id}
# Auth: HTTP Basic with CURSOR_API_KEY as the username and an empty password.
#
# Cursor agents edit a remote branch/PR. They do not write this local worktree.

_harness_agent_provider() {
  printf '%s' "${HARNESS_AGENT_PROVIDER:-codex}" | tr '[:upper:]' '[:lower:]'
}

_cursor_api_base() {
  local base="${HARNESS_CURSOR_API_BASE:-https://api.cursor.com}"
  printf '%s' "${base%/}"
}

_cursor_trim() {
  printf '%s' "${1:-}" | tr -d '\r\n'
}

_cursor_api_key() {
  _cursor_trim "${CURSOR_API_KEY:-}"
}

_cursor_dry_run() {
  case "${HARNESS_CURSOR_DRY_RUN:-0}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

_cursor_wait_enabled() {
  case "${HARNESS_CURSOR_WAIT:-0}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

_cursor_auto_create_pr() {
  case "${HARNESS_CURSOR_AUTO_CREATE_PR:-1}" in
    0|false|FALSE|no|NO) printf 'false' ;;
    *) printf 'true' ;;
  esac
}

_cursor_normalize_repo_url() {
  local url="$1"
  url="${url%.git}"
  if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
    printf 'https://%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return
  fi
  if [[ "$url" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
    printf 'https://%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return
  fi
  printf '%s' "$url"
}

_cursor_detect_repo() {
  if [[ -n "${HARNESS_CURSOR_REPO:-}" ]]; then
    _cursor_normalize_repo_url "$HARNESS_CURSOR_REPO"
    return 0
  fi
  local url
  url="$(git -C "$HARNESS_ROOT_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    return 1
  fi
  _cursor_normalize_repo_url "$url"
}

_cursor_detect_ref() {
  if [[ -n "${HARNESS_CURSOR_REF:-}" ]]; then
    printf '%s' "$HARNESS_CURSOR_REF"
    return
  fi
  local ref
  ref="$(git -C "$HARNESS_ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$ref" || "$ref" == "HEAD" ]]; then
    printf '%s' "main"
    return
  fi
  printf '%s' "$ref"
}

_cursor_json_get() {
  local json_file="$1"
  local path="$2"
  python3 - "$json_file" "$path" <<'PY'
import json
import sys

path = sys.argv[2].split(".")
with open(sys.argv[1], encoding="utf-8") as handle:
    cur = json.load(handle)
for key in path:
    if isinstance(cur, dict):
        cur = cur.get(key)
    else:
        cur = None
        break
if cur is None:
    print("")
elif isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
PY
}

_cursor_build_payload() {
  local prompt_file="$1"
  local repo="$2"
  local ref="$3"
  local out_file="$4"
  local model="${HARNESS_CURSOR_MODEL:-default}"
  local auto_pr branch
  auto_pr="$(_cursor_auto_create_pr)"
  branch="${HARNESS_CURSOR_BRANCH_NAME:-}"
  python3 - "$prompt_file" "$repo" "$ref" "$model" "$auto_pr" "$branch" "$out_file" <<'PY'
import json
import pathlib
import sys

prompt_path, repo, ref, model, auto_pr, branch, out_file = sys.argv[1:8]
payload = {
    "prompt": {"text": pathlib.Path(prompt_path).read_text(encoding="utf-8")},
    "source": {"repository": repo},
    "target": {"autoCreatePr": auto_pr == "true"},
}
if ref:
    payload["source"]["ref"] = ref
if model:
    payload["model"] = model
if branch:
    payload["target"]["branchName"] = branch
pathlib.Path(out_file).write_text(json.dumps(payload), encoding="utf-8")
PY
}

_cursor_http() {
  local method="$1"
  local path="$2"
  local body_file="${3:-}"
  local out_file="$4"
  local key url code curl_ec
  key="$(_cursor_api_key)"
  url="$(_cursor_api_base)$path"

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required for the Cursor Cloud Agents provider." >&2
    return 2
  fi

  local args
  args=(-sS -o "$out_file" -w "%{http_code}" -u "${key}:" -H "Accept: application/json")
  if [[ "$method" != "GET" ]]; then
    args+=(-X "$method")
  fi
  if [[ -n "$body_file" ]]; then
    args+=(-H "Content-Type: application/json" --data-binary @"$body_file")
  fi

  code=0
  curl_ec=0
  code="$(curl "${args[@]}" "$url")" || curl_ec="$?"
  HARNESS_CURSOR_HTTP_CODE="$code"
  if [[ "$curl_ec" != "0" ]]; then
    return 2
  fi
  [[ "$code" =~ ^2 ]]
}

_cursor_is_terminal_status() {
  local status
  status="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$status" in
    FINISHED|FAILED|ERROR|EXPIRED|CANCELLED|CANCELED|STOPPED) return 0 ;;
    *) return 1 ;;
  esac
}

_cursor_map_harness_status() {
  local status
  status="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$status" in
    FINISHED) printf 'succeeded' ;;
    FAILED|ERROR|EXPIRED|CANCELLED|CANCELED|STOPPED) printf 'failed' ;;
    *) printf 'running' ;;
  esac
}

_cursor_write_job_files() {
  local status="$1"
  local status_label="$2"
  local log_file="$3"
  local result_file="$4"
  local status_file="$5"
  local summary="$6"
  local details="${7:-}"

  {
    echo "$status"
    echo "$status_label"
    echo "log: $log_file"
    echo "result: $result_file"
    echo "summary: $summary"
    echo "provider: cursor"
    if [[ -n "${HARNESS_CURSOR_AGENT_ID:-}" ]]; then
      echo "agent_id: ${HARNESS_CURSOR_AGENT_ID}"
    fi
    if [[ -n "${HARNESS_CURSOR_AGENT_URL:-}" ]]; then
      echo "agent_url: ${HARNESS_CURSOR_AGENT_URL}"
    fi
    if [[ -n "${HARNESS_CURSOR_PR_URL:-}" ]]; then
      echo "pr_url: ${HARNESS_CURSOR_PR_URL}"
    fi
    if [[ -n "${HARNESS_CURSOR_BRANCH:-}" ]]; then
      echo "branch: ${HARNESS_CURSOR_BRANCH}"
    fi
    if [[ -n "${HARNESS_CURSOR_API_STATUS:-}" ]]; then
      echo "cursor_status: ${HARNESS_CURSOR_API_STATUS}"
    fi
  } >"$status_file"

  local result_status="$status"
  case "$status" in
    succeeded|blocked|failed) ;;
    *) result_status="running" ;;
  esac

  {
    echo "STATUS: $result_status"
    echo "SUMMARY: $summary"
    echo "DETAILS:"
    if [[ -n "$details" ]]; then
      printf '%s\n' "$details"
    fi
    if [[ -n "${HARNESS_CURSOR_AGENT_ID:-}" ]]; then
      echo "agent_id: ${HARNESS_CURSOR_AGENT_ID}"
    fi
    if [[ -n "${HARNESS_CURSOR_AGENT_URL:-}" ]]; then
      echo "agent_url: ${HARNESS_CURSOR_AGENT_URL}"
    fi
    if [[ -n "${HARNESS_CURSOR_PR_URL:-}" ]]; then
      echo "pr_url: ${HARNESS_CURSOR_PR_URL}"
    fi
    if [[ -n "${HARNESS_CURSOR_BRANCH:-}" ]]; then
      echo "branch: ${HARNESS_CURSOR_BRANCH}"
    fi
    echo "Cursor agents edit a remote branch/PR, not this local worktree."
    echo "Merge the PR and pull before treating those files as present here."
  } >"$result_file"
}

_cursor_apply_agent_json() {
  local json_file="$1"
  HARNESS_CURSOR_AGENT_ID="$(_cursor_json_get "$json_file" "id")"
  HARNESS_CURSOR_API_STATUS="$(_cursor_json_get "$json_file" "status")"
  HARNESS_CURSOR_AGENT_URL="$(_cursor_json_get "$json_file" "target.url")"
  if [[ -z "$HARNESS_CURSOR_AGENT_URL" && -n "$HARNESS_CURSOR_AGENT_ID" ]]; then
    HARNESS_CURSOR_AGENT_URL="https://cursor.com/agents?id=${HARNESS_CURSOR_AGENT_ID}"
  fi
  HARNESS_CURSOR_PR_URL="$(_cursor_json_get "$json_file" "target.prUrl")"
  HARNESS_CURSOR_BRANCH="$(_cursor_json_get "$json_file" "target.branchName")"
  HARNESS_CURSOR_SUMMARY="$(_cursor_json_get "$json_file" "summary")"
}

_cursor_read_status_field() {
  local status_file="$1"
  local key="$2"
  awk -F': ' -v wanted="$key" '
    $1 == wanted {
      sub(/^[^:]+: /, "")
      print
      exit
    }
  ' "$status_file"
}

_cursor_load_status_metadata() {
  local status_file="$1"
  HARNESS_CURSOR_AGENT_ID="$(_cursor_read_status_field "$status_file" "agent_id")"
  HARNESS_CURSOR_AGENT_URL="$(_cursor_read_status_field "$status_file" "agent_url")"
  HARNESS_CURSOR_PR_URL="$(_cursor_read_status_field "$status_file" "pr_url")"
  HARNESS_CURSOR_BRANCH="$(_cursor_read_status_field "$status_file" "branch")"
  HARNESS_CURSOR_API_STATUS="$(_cursor_read_status_field "$status_file" "cursor_status")"
}

_cursor_prepare_prompt() {
  local prompt="$1"
  local result_file="$2"
  local rel_result="${result_file#$HARNESS_ROOT_DIR/}"

  if [[ -n "$HARNESS_EXTRA_CONTEXT" ]]; then
    prompt="$(cat <<PROMPT
${prompt}

Additional human context for this phase run:
${HARNESS_EXTRA_CONTEXT}

If this is a rerun, update the existing files in place. Keep prior correct work, but revise anything that conflicts with the additional context above.
PROMPT
)"
  fi

  prompt="${prompt//__HARNESS_RESULT_FILE__/$rel_result}"
  cat <<PROMPT
You are running as a Cursor Cloud Agent on a remote VM.

Important semantic difference vs the Codex harness path:
- You edit a remote git branch and pull request, not a local harness worktree.
- Commit your scoped files on the agent branch and rely on autoCreatePr when enabled.
- Do not assume files you write are already present on the operator's laptop.

Before finishing, write your phase result to this repository path (create parent directories if needed):
${rel_result}

${prompt}
PROMPT
}

_run_cursor_agent() {
  local run_label="$1"
  local status_label="$2"
  local prompt="$3"
  local artifact_name
  artifact_name="$(_artifact_name "$run_label")"
  local log_file="$HARNESS_LOG_DIR/${artifact_name}.log"
  local status_file="$HARNESS_STATUS_DIR/${artifact_name}.status"
  local result_file="$HARNESS_RESULT_DIR/${artifact_name}.result"
  local tmp_dir prompt_file payload_file response_file
  local repo ref summary details

  HARNESS_CURSOR_AGENT_ID=""
  HARNESS_CURSOR_AGENT_URL=""
  HARNESS_CURSOR_PR_URL=""
  HARNESS_CURSOR_BRANCH=""
  HARNESS_CURSOR_API_STATUS=""
  HARNESS_CURSOR_SUMMARY=""
  HARNESS_CURSOR_HTTP_CODE=""

  mkdir -p "$HARNESS_LOG_DIR" "$HARNESS_STATUS_DIR" "$HARNESS_RESULT_DIR"
  : >"$result_file"
  prompt="$(_cursor_prepare_prompt "$prompt" "$result_file")"

  summary="Launching Cursor cloud agent"
  _cursor_write_job_files "running" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
  echo "running $run_label (cursor)"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/harness-cursor.XXXXXX")"
  prompt_file="$tmp_dir/prompt.txt"
  payload_file="$tmp_dir/payload.json"
  response_file="$tmp_dir/response.json"
  printf '%s' "$prompt" >"$prompt_file"

  if ! repo="$(_cursor_detect_repo)"; then
    summary="Could not detect GitHub repository URL. Set HARNESS_CURSOR_REPO."
    {
      echo "blocked: $summary"
    } >"$log_file"
    _cursor_write_job_files "blocked" "$status_label" "$log_file" "$result_file" "$status_file" "$summary" \
      "Set HARNESS_CURSOR_REPO=https://github.com/org/repo or add a git origin remote."
    rm -rf "$tmp_dir"
    return 1
  fi
  ref="$(_cursor_detect_ref)"
  if ! _cursor_build_payload "$prompt_file" "$repo" "$ref" "$payload_file"; then
    summary="Failed to build Cursor launch JSON payload."
    echo "$summary" >>"$log_file"
    _cursor_write_job_files "failed" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
    rm -rf "$tmp_dir"
    return 1
  fi

  {
    echo "provider: cursor"
    echo "api: $(_cursor_api_base)/v0/agents"
    echo "repository: $repo"
    echo "ref: $ref"
    echo "model: ${HARNESS_CURSOR_MODEL:-default}"
    echo "autoCreatePr: $(_cursor_auto_create_pr)"
    echo "wait: ${HARNESS_CURSOR_WAIT:-0}"
    echo "dry_run: ${HARNESS_CURSOR_DRY_RUN:-0}"
    echo
    echo "Launch payload (prompt omitted; full JSON in ${payload_file##*/} is not re-logged after send):"
    python3 - "$payload_file" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
payload["prompt"] = {"text": f"<{len(payload.get('prompt', {}).get('text', ''))} chars>"}
print(json.dumps(payload, indent=2))
PY
  } >"$log_file"

  if _cursor_dry_run; then
    HARNESS_CURSOR_AGENT_ID="bc-dry-run-${artifact_name}"
    HARNESS_CURSOR_AGENT_URL="https://cursor.com/agents?id=${HARNESS_CURSOR_AGENT_ID}"
    HARNESS_CURSOR_API_STATUS="DRY_RUN"
    summary="Dry-run: Cursor launch skipped (HARNESS_CURSOR_DRY_RUN=1). No Codex and no Cloud Agents API call."
    {
      echo
      echo "$summary"
      echo "agent_id: $HARNESS_CURSOR_AGENT_ID"
    } >>"$log_file"
    if _cursor_wait_enabled; then
      _cursor_write_job_files "succeeded" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
    else
      _cursor_write_job_files "running" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
    fi
    rm -rf "$tmp_dir"
    return 0
  fi

  if [[ -z "$(_cursor_api_key)" ]]; then
    summary="CURSOR_API_KEY is not set."
    echo "$summary" >>"$log_file"
    _cursor_write_job_files "blocked" "$status_label" "$log_file" "$result_file" "$status_file" "$summary" \
      "Create a Cloud Agents API key and export CURSOR_API_KEY. Do not commit the key."
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! _cursor_http POST "/v0/agents" "$payload_file" "$response_file"; then
    details="$(cat "$response_file" 2>/dev/null || true)"
    summary="Cursor launch failed (HTTP ${HARNESS_CURSOR_HTTP_CODE:-n/a}). See log."
    {
      echo
      echo "HTTP ${HARNESS_CURSOR_HTTP_CODE:-n/a}"
      echo "$details"
    } >>"$log_file"
    _cursor_write_job_files "failed" "$status_label" "$log_file" "$result_file" "$status_file" "$summary" "$details"
    rm -rf "$tmp_dir"
    return 1
  fi

  cp "$response_file" "$HARNESS_LOG_DIR/${artifact_name}.launch.json"
  _cursor_apply_agent_json "$response_file"
  if [[ -z "$HARNESS_CURSOR_AGENT_ID" ]]; then
    summary="Cursor launch response did not include an agent id."
    echo "$summary" >>"$log_file"
    cat "$response_file" >>"$log_file"
    _cursor_write_job_files "failed" "$status_label" "$log_file" "$result_file" "$status_file" "$summary" "$(cat "$response_file")"
    rm -rf "$tmp_dir"
    return 1
  fi

  {
    echo
    echo "launched agent_id=${HARNESS_CURSOR_AGENT_ID}"
    echo "agent_url=${HARNESS_CURSOR_AGENT_URL}"
    echo "cursor_status=${HARNESS_CURSOR_API_STATUS}"
    echo "pr_url=${HARNESS_CURSOR_PR_URL}"
    echo "branch=${HARNESS_CURSOR_BRANCH}"
  } >>"$log_file"

  summary="Cursor cloud agent launched: ${HARNESS_CURSOR_AGENT_ID}"
  _cursor_write_job_files "running" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
  echo "launched $run_label agent_id=${HARNESS_CURSOR_AGENT_ID}"

  if ! _cursor_wait_enabled; then
    rm -rf "$tmp_dir"
    return 0
  fi

  if ! _cursor_poll_agent "$HARNESS_CURSOR_AGENT_ID" "$log_file" "$status_label" "$result_file" "$status_file"; then
    rm -rf "$tmp_dir"
    return 1
  fi
  rm -rf "$tmp_dir"
  return 0
}

_cursor_poll_agent() {
  local agent_id="$1"
  local log_file="$2"
  local status_label="$3"
  local result_file="$4"
  local status_file="$5"
  local interval timeout start now elapsed response_file harness_status summary
  interval="${HARNESS_CURSOR_POLL_SECONDS:-15}"
  timeout="${HARNESS_CURSOR_WAIT_TIMEOUT:-0}"
  start="$(date +%s)"
  response_file="$(mktemp "${TMPDIR:-/tmp}/harness-cursor-status.XXXXXX")"

  while true; do
    if ! _cursor_http GET "/v0/agents/${agent_id}" "" "$response_file"; then
      summary="Cursor status poll failed (HTTP ${HARNESS_CURSOR_HTTP_CODE:-n/a})."
      echo "$summary" >>"$log_file"
      cat "$response_file" >>"$log_file" || true
      _cursor_write_job_files "failed" "$status_label" "$log_file" "$result_file" "$status_file" "$summary" "$(cat "$response_file" 2>/dev/null || true)"
      rm -f "$response_file"
      return 1
    fi

    _cursor_apply_agent_json "$response_file"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cursor_status=${HARNESS_CURSOR_API_STATUS} pr_url=${HARNESS_CURSOR_PR_URL}" >>"$log_file"
    _cursor_write_job_files "running" "$status_label" "$log_file" "$result_file" "$status_file" \
      "Cursor cloud agent ${agent_id} is ${HARNESS_CURSOR_API_STATUS:-running}"

    if _cursor_is_terminal_status "${HARNESS_CURSOR_API_STATUS}"; then
      harness_status="$(_cursor_map_harness_status "$HARNESS_CURSOR_API_STATUS")"
      if [[ -n "${HARNESS_CURSOR_SUMMARY}" ]]; then
        summary="$HARNESS_CURSOR_SUMMARY"
      else
        summary="Cursor cloud agent ${agent_id} ${HARNESS_CURSOR_API_STATUS}"
      fi
      cp "$response_file" "${log_file%.log}.status.json"
      _cursor_write_job_files "$harness_status" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
      rm -f "$response_file"
      [[ "$harness_status" == "succeeded" ]]
      return
    fi

    now="$(date +%s)"
    elapsed=$((now - start))
    if [[ "$timeout" -gt 0 && "$elapsed" -ge "$timeout" ]]; then
      summary="Timed out waiting for Cursor agent ${agent_id} after ${elapsed}s."
      echo "$summary" >>"$log_file"
      _cursor_write_job_files "failed" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
      rm -f "$response_file"
      return 1
    fi
    sleep "$interval"
  done
}

_cursor_refresh_status_file() {
  local status_file="$1"
  local log_file result_file status_label current response_file harness_status summary

  if [[ ! -f "$status_file" ]]; then
    echo "status file not found: $status_file" >&2
    return 1
  fi

  current="$(sed -n '1p' "$status_file")"
  status_label="$(sed -n '2p' "$status_file")"
  log_file="$(_cursor_read_status_field "$status_file" "log")"
  result_file="$(_cursor_read_status_field "$status_file" "result")"
  _cursor_load_status_metadata "$status_file"

  if [[ -z "$HARNESS_CURSOR_AGENT_ID" ]]; then
    echo "no agent_id in $status_file" >&2
    return 1
  fi
  if [[ "$HARNESS_CURSOR_AGENT_ID" == bc-dry-run-* ]]; then
    echo "$status_file: dry-run agent $HARNESS_CURSOR_AGENT_ID (not polled)"
    return 0
  fi
  if [[ -z "$log_file" ]]; then
    log_file="$HARNESS_LOG_DIR/$(basename "${status_file%.status}").log"
  fi
  if [[ -z "$result_file" ]]; then
    result_file="$HARNESS_RESULT_DIR/$(basename "${status_file%.status}").result"
  fi

  if _cursor_dry_run; then
    echo "$status_file: dry-run refresh skipped for $HARNESS_CURSOR_AGENT_ID"
    return 0
  fi

  if [[ -z "$(_cursor_api_key)" ]]; then
    echo "CURSOR_API_KEY is not set." >&2
    return 1
  fi

  response_file="$(mktemp "${TMPDIR:-/tmp}/harness-cursor-refresh.XXXXXX")"
  if ! _cursor_http GET "/v0/agents/${HARNESS_CURSOR_AGENT_ID}" "" "$response_file"; then
    echo "Failed to refresh ${HARNESS_CURSOR_AGENT_ID} (HTTP ${HARNESS_CURSOR_HTTP_CODE:-n/a})" >&2
    cat "$response_file" >&2 || true
    rm -f "$response_file"
    return 1
  fi

  _cursor_apply_agent_json "$response_file"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) refresh ${HARNESS_CURSOR_AGENT_ID} cursor_status=${HARNESS_CURSOR_API_STATUS}" >>"$log_file"
  cp "$response_file" "${log_file%.log}.status.json"

  if _cursor_is_terminal_status "${HARNESS_CURSOR_API_STATUS}"; then
    harness_status="$(_cursor_map_harness_status "$HARNESS_CURSOR_API_STATUS")"
    summary="${HARNESS_CURSOR_SUMMARY:-Cursor cloud agent ${HARNESS_CURSOR_AGENT_ID} ${HARNESS_CURSOR_API_STATUS}}"
  else
    harness_status="running"
    summary="Cursor cloud agent ${HARNESS_CURSOR_AGENT_ID} is ${HARNESS_CURSOR_API_STATUS:-running}"
  fi

  _cursor_write_job_files "$harness_status" "$status_label" "$log_file" "$result_file" "$status_file" "$summary"
  echo "$status_file: ${current} -> ${harness_status} (${HARNESS_CURSOR_API_STATUS})"
  rm -f "$response_file"
  return 0
}
