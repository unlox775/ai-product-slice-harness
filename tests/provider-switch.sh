#!/usr/bin/env bash
# Verify Codex remains default and the Cursor provider never calls Codex.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-provider-test.XXXXXX")"
cleanup() {
  if [[ -n "${MOCK_PID:-}" ]] && kill -0 "$MOCK_PID" 2>/dev/null; then
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

PROJ="$WORKDIR/proj"
FAKE_BIN="$WORKDIR/bin"
CODEX_SENTINEL="$WORKDIR/codex-was-called"
MOCK_DUMP="$WORKDIR/last-payload.json"
mkdir -p "$FAKE_BIN" "$PROJ"

cat >"$FAKE_BIN/codex" <<EOF
#!/bin/sh
echo "CODEX_WAS_CALLED" >>"$CODEX_SENTINEL"
echo "unexpected Codex invocation" >&2
exit 97
EOF
chmod +x "$FAKE_BIN/codex"
export PATH="$FAKE_BIN:$PATH"

echo "== install copies Cursor helpers =="
"$REPO_ROOT/bin/install" "$PROJ" >/dev/null
for required in \
  docs/ai-product-slice-harness/cursor-agent-provider.sh \
  docs/ai-product-slice-harness/cursor-agent-launch.sh \
  docs/ai-product-slice-harness/cursor-agent-status.sh
do
  if [[ ! -x "$PROJ/$required" ]]; then
    echo "missing executable after install: $required" >&2
    exit 1
  fi
done
if ! grep -q 'HARNESS_AGENT_PROVIDER' "$PROJ/docs/ai-product-slice-harness/config.env"; then
  echo "installed config.env is missing provider notes" >&2
  exit 1
fi

cd "$PROJ"
git init -q
git checkout -q -b main
git config user.email "harness-test@example.com"
git config user.name "Harness Test"
git remote add origin git@github.com:example/harness-product.git
mkdir -p packages/demo/docs/specs
echo "# demo" >packages/demo/README.md
git add -A
git commit -qm "test fixture"

assert_no_codex() {
  if [[ -f "$CODEX_SENTINEL" ]]; then
    echo "Codex was invoked; sentinel contains:" >&2
    cat "$CODEX_SENTINEL" >&2
    exit 1
  fi
}

echo "== default provider is Codex and does not call Cursor =="
rm -f "$CODEX_SENTINEL"
CODEX_BIN=/nonexistent/codex-missing bash -c '
  set -euo pipefail
  source docs/ai-product-slice-harness/subagent-runner.sh
  test "$(_harness_agent_provider)" = "codex"
  start_phase "phase-codex-default"
  if _run_agent "demo" "packages/demo" "do not actually run"; then
    echo "missing Codex binary should block the job" >&2
    exit 1
  fi
'
status_file="subagents/status/phase-codex-default-demo.status"
test "$(sed -n '1p' "$status_file")" = "blocked"
grep -q "Codex executable not found" "$status_file"
if grep -q "provider: cursor" "$status_file"; then
  echo "default Codex run wrote Cursor metadata" >&2
  exit 1
fi
assert_no_codex

echo "== Codex provider still execs the Codex binary =="
rm -f "$CODEX_SENTINEL"
CODEX_BIN="$FAKE_BIN/codex" bash -c '
  set -euo pipefail
  source docs/ai-product-slice-harness/subagent-runner.sh
  start_phase "phase-codex-exec"
  _run_agent "demo" "packages/demo" "prompt for fake Codex"
' || true
test -f "$CODEX_SENTINEL"
grep -q CODEX_WAS_CALLED "$CODEX_SENTINEL"
test "$(sed -n '1p' subagents/status/phase-codex-exec-demo.status)" = "failed"
rm -f "$CODEX_SENTINEL"

echo "== env provider=cursor dry-run never calls Codex =="
rm -f "$CODEX_SENTINEL"
CODEX_BIN="$FAKE_BIN/codex" \
HARNESS_AGENT_PROVIDER=cursor \
HARNESS_CURSOR_DRY_RUN=1 \
HARNESS_CURSOR_REPO=https://github.com/example/harness-product \
bash -c '
  set -euo pipefail
  source docs/ai-product-slice-harness/subagent-runner.sh
  test "$(_harness_agent_provider)" = "cursor"
  start_phase "phase-cursor-dry"
  _run_agent "demo" "packages/demo" "Write the product spec. Result: __HARNESS_RESULT_FILE__"
'
dry_status="subagents/status/phase-cursor-dry-demo.status"
test "$(sed -n '1p' "$dry_status")" = "running"
grep -q "provider: cursor" "$dry_status"
grep -q "agent_id: bc-dry-run-phase-cursor-dry-demo" "$dry_status"
grep -q "Dry-run" "subagents/logs/phase-cursor-dry-demo.log"
grep -q "repository" "subagents/logs/phase-cursor-dry-demo.log"
if grep -qiE 'codex exec|invok(e|ing) codex|"$HARNESS_CODEX_BIN"' "subagents/logs/phase-cursor-dry-demo.log"; then
  echo "Cursor dry-run log looks like it invoked Codex" >&2
  cat "subagents/logs/phase-cursor-dry-demo.log" >&2
  exit 1
fi
assert_no_codex

echo "== config.env cursor is overridden by env=codex =="
printf '\nHARNESS_AGENT_PROVIDER=cursor\n' >>docs/ai-product-slice-harness/config.env
HARNESS_AGENT_PROVIDER=codex bash -c '
  set -euo pipefail
  source docs/ai-product-slice-harness/subagent-runner.sh
  test "$(_harness_agent_provider)" = "codex"
'

echo "== enqueue parallel dry-run launches two Cursor jobs =="
rm -f "$CODEX_SENTINEL"
CODEX_BIN="$FAKE_BIN/codex" \
HARNESS_AGENT_PROVIDER=cursor \
HARNESS_CURSOR_DRY_RUN=1 \
HARNESS_CURSOR_REPO=https://github.com/example/harness-product \
bash -c '
  set -euo pipefail
  source docs/ai-product-slice-harness/subagent-runner.sh
  start_phase "phase-03-product-specs"
  enqueue_product_spec_agent "packages/demo"
  enqueue_product_spec_agent "packages/other"
  mkdir -p packages/other
  run_enqueued_agents_in_parallel
'
test -f subagents/status/phase-03-product-specs-demo.status
test -f subagents/status/phase-03-product-specs-other.status
grep -q "agent_id: bc-dry-run-" subagents/status/phase-03-product-specs-demo.status
grep -q "agent_id: bc-dry-run-" subagents/status/phase-03-product-specs-other.status
assert_no_codex

echo "== require_phase_successes still gates on running Cursor jobs =="
if HARNESS_AGENT_PROVIDER=cursor bash -c '
  set -euo pipefail
  source docs/ai-product-slice-harness/subagent-runner.sh
  start_phase "phase-04-customer-requests"
  require_phase_successes "phase-03-product-specs" "demo"
'; then
  echo "require_phase_successes accepted a running Cursor job" >&2
  exit 1
fi

echo "== mock Cloud Agents API launch + wait =="
MOCK_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
python3 "$REPO_ROOT/tests/mock-cursor-api.py" "$MOCK_PORT" "$MOCK_DUMP" &
MOCK_PID="$!"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf "http://127.0.0.1:${MOCK_PORT}/last-payload" >/dev/null; then
    break
  fi
  sleep 0.1
done

rm -f "$CODEX_SENTINEL"
CODEX_BIN="$FAKE_BIN/codex" \
HARNESS_AGENT_PROVIDER=cursor \
HARNESS_CURSOR_DRY_RUN=0 \
HARNESS_CURSOR_WAIT=1 \
HARNESS_CURSOR_POLL_SECONDS=1 \
CURSOR_API_KEY=test-key \
HARNESS_CURSOR_API_BASE="http://127.0.0.1:${MOCK_PORT}" \
HARNESS_CURSOR_REPO=https://github.com/example/harness-product \
HARNESS_CURSOR_REF=main \
HARNESS_CURSOR_MODEL=default \
bash -c '
  set -euo pipefail
  source docs/ai-product-slice-harness/subagent-runner.sh
  start_phase "phase-cursor-api"
  _run_agent "demo" "packages/demo" "Implement the scoped phase job."
'
api_status="subagents/status/phase-cursor-api-demo.status"
test "$(sed -n '1p' "$api_status")" = "succeeded"
grep -q "agent_id: bc_test123" "$api_status"
grep -q "pr_url: https://github.com/example/repo/pull/42" "$api_status"
test -f subagents/logs/phase-cursor-api-demo.launch.json
python3 - "$MOCK_DUMP" <<'PY'
import json, sys
payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert payload["prompt"]["text"].startswith("You are running as a Cursor Cloud Agent")
assert "Implement the scoped phase job." in payload["prompt"]["text"]
assert payload["source"]["repository"] == "https://github.com/example/harness-product"
assert payload["source"]["ref"] == "main"
assert payload["model"] == "default"
assert payload["target"]["autoCreatePr"] is True
print("payload ok")
PY
assert_no_codex

echo "== planning sequence stops after Cursor Phase 03 =="
mkdir -p subagents
cat >subagents/phase-03-product-specs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/docs/ai-product-slice-harness/subagent-runner.sh"
start_phase "phase-03-product-specs"
_run_agent "plan" "packages/demo" "planning prompt"
EOF
cat >subagents/phase-04-customer-requests.sh <<'EOF'
#!/usr/bin/env bash
echo SHOULD_NOT_RUN_PHASE_04
exit 1
EOF
cat >subagents/phase-05-producer-responses.sh <<'EOF'
#!/usr/bin/env bash
echo SHOULD_NOT_RUN_PHASE_05
exit 1
EOF
chmod +x subagents/phase-03-product-specs.sh \
  subagents/phase-04-customer-requests.sh \
  subagents/phase-05-producer-responses.sh

git add -A
git commit -qm "provider-switch test artifacts"

rm -f "$CODEX_SENTINEL"
set +e
CODEX_BIN="$FAKE_BIN/codex" \
HARNESS_AGENT_PROVIDER=cursor \
HARNESS_CURSOR_DRY_RUN=1 \
HARNESS_CURSOR_REPO=https://github.com/example/harness-product \
bash docs/ai-product-slice-harness/run-planning-phases.sh phase-3-5 >"$WORKDIR/planning.out" 2>&1
plan_ec=$?
set -e
if [[ "$plan_ec" != "0" ]]; then
  echo "planning sequence exited $plan_ec" >&2
  cat "$WORKDIR/planning.out" >&2
  exit 1
fi
if grep -q SHOULD_NOT_RUN "$WORKDIR/planning.out"; then
  echo "planning sequence continued into a later Cursor phase" >&2
  cat "$WORKDIR/planning.out" >&2
  exit 1
fi
grep -q "Stopping the combined planning sequence after Phase 03" "$WORKDIR/planning.out"
assert_no_codex

echo
echo "All provider-switch checks passed."
