#!/usr/bin/env python3
"""
mock_island.py — a dependency-free stand-in for the Eidos Swift island server.

It implements the exact HTTP contract from CLAUDE.md / IslandServer.swift so you
can develop and test eidos.py (and any agent integration) without building or
running the macOS app. Uses only the Python standard library.

Endpoints:
    POST /event    -> {"ok": true}                       (fire-and-forget)
    POST /approve  -> blocks, then {"approved": bool, "modified": null}
    GET  /status   -> {"running": bool, "agents": [...]}

Approval behavior (configurable via env):
    EIDOS_MOCK_APPROVE = "auto"   (default) auto-approve after a short delay
    EIDOS_MOCK_APPROVE = "reject"           auto-reject after a short delay
    EIDOS_MOCK_APPROVE = "prompt"           ask on the server's stdin
    EIDOS_MOCK_DELAY   = seconds before auto-decision (default 1.5)

Run:
    python3 mock_island.py            # listen on :7799
    python3 mock_island.py --port 8080
"""
import argparse
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# In-memory agent table, keyed by agent id. Mirrors AgentStore.agents.
_AGENTS = {}
_LOCK = threading.Lock()


def _decide(payload):
    """Return (approved: bool, modified) for an /approve request."""
    mode = os.environ.get("EIDOS_MOCK_APPROVE", "auto")
    delay = float(os.environ.get("EIDOS_MOCK_DELAY", "1.5"))
    actions = payload.get("actions", [])
    task = payload.get("task", "(no task)")
    print(f"  [approve] {payload.get('agent')}: {task} — {len(actions)} action(s)")
    for a in actions:
        desc = f"  ({a['description']})" if a.get("description") else ""
        print(f"            {a.get('op'):>6} {a.get('target')}{desc}")

    if mode == "prompt":
        try:
            ans = input("  approve? [y/N] ").strip().lower()
            return (ans in ("y", "yes"), None)
        except EOFError:
            return (False, None)

    time.sleep(delay)
    if mode == "reject":
        print("  [approve] -> REJECTED (mock)")
        return (False, None)
    print("  [approve] -> APPROVED (mock)")
    return (True, None)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # silence default logging; we print our own

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return None

    def _send_json(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/status":
            with _LOCK:
                agents = [
                    {"agent": a["agent"], "status": a["status"]}
                    for a in _AGENTS.values()
                ]
            self._send_json(200, {"running": len(agents) > 0, "agents": agents})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        payload = self._read_body()
        if payload is None:
            self._send_json(400, {"error": "bad request"})
            return

        if self.path == "/event":
            agent = payload.get("agent", "?")
            with _LOCK:
                _AGENTS[agent] = {
                    "agent": agent,
                    "status": payload.get("status", "running"),
                    "task": payload.get("task", agent),
                    "progress": payload.get("progress", 0.0),
                }
            print(f"  [event]  {agent}: {payload.get('status')} "
                  f"{payload.get('task', '')} ({payload.get('progress', 0)})")
            self._send_json(200, {"ok": True})

        elif self.path == "/approve":
            approved, modified = _decide(payload)
            self._send_json(200, {"approved": approved, "modified": modified})

        else:
            self._send_json(404, {"error": "not found"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=7799)
    args = ap.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"mock_island listening on http://127.0.0.1:{args.port}  "
          f"(approve mode: {os.environ.get('EIDOS_MOCK_APPROVE', 'auto')})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
