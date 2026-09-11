#!/usr/bin/env python3
"""Tiny v0 Cloud Agents API stand-in for harness provider tests."""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

STATE = {
    "next_id": "bc_test123",
    "agents": {},
    "last_payload": None,
    "launch_status": "CREATING",
    "get_status": "FINISHED",
    "require_auth": True,
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s\n" % (fmt % args))

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def _write_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_auth(self) -> bool:
        if not STATE["require_auth"]:
            return True
        auth = self.headers.get("Authorization") or ""
        if not auth.startswith("Basic "):
            self._write_json(401, {"error": "missing basic auth"})
            return False
        return True

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v0/agents":
            self._write_json(404, {"error": "not found", "path": self.path})
            return
        if not self._check_auth():
            return
        payload = self._read_json()
        STATE["last_payload"] = payload
        dump = Path(self.server.dump_path)  # type: ignore[attr-defined]
        dump.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        agent_id = STATE["next_id"]
        agent = {
            "id": agent_id,
            "name": "Harness test agent",
            "status": STATE["launch_status"],
            "source": payload.get("source", {}),
            "target": {
                "branchName": payload.get("target", {}).get("branchName")
                or "cursor/harness-test",
                "url": f"https://cursor.com/agents?id={agent_id}",
                "prUrl": "https://github.com/example/repo/pull/42",
                "autoCreatePr": bool(payload.get("target", {}).get("autoCreatePr", False)),
            },
            "summary": "",
        }
        STATE["agents"][agent_id] = agent
        self._write_json(201, agent)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/last-payload":
            self._write_json(200, STATE["last_payload"] or {})
            return
        if not self.path.startswith("/v0/agents/"):
            self._write_json(404, {"error": "not found", "path": self.path})
            return
        if not self._check_auth():
            return
        agent_id = self.path.rsplit("/", 1)[-1]
        agent = dict(STATE["agents"].get(agent_id) or {"id": agent_id})
        agent["status"] = STATE["get_status"]
        agent["summary"] = "Mock agent finished the phase job."
        agent.setdefault(
            "target",
            {
                "url": f"https://cursor.com/agents?id={agent_id}",
                "prUrl": "https://github.com/example/repo/pull/42",
                "branchName": "cursor/harness-test",
            },
        )
        self._write_json(200, agent)


def main() -> None:
    if len(sys.argv) < 3:
        print("usage: mock-cursor-api.py PORT DUMP_JSON_PATH", file=sys.stderr)
        raise SystemExit(2)
    port = int(sys.argv[1])
    dump_path = sys.argv[2]
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.dump_path = dump_path  # type: ignore[attr-defined]
    print(f"mock cursor api on 127.0.0.1:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
