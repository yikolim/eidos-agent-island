#!/usr/bin/env python3
"""
test_eidos.py — exercise the real eidos.py integration code paths.

The OpenAI Agents SDK isn't required to test eidos.py's wire behavior, so we
inject a minimal stub `agents` module into sys.modules before importing eidos.
This drives the actual IslandHook + approval_tool code against mock_island.py.

Run inside the venv that has httpx:
    .venv/bin/python test_eidos.py
"""
import json
import os
import sys
import threading
import time
import types
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ── Inject a minimal stub `agents` module so `import eidos` succeeds ──────────
_stub = types.ModuleType("agents")


class AgentHooks:  # noqa: D401 - matches SDK base class shape
    pass


class RunContextWrapper:
    pass


class Agent:
    def __init__(self, name="Agent", instructions=""):
        self.name = name
        self.instructions = instructions


class Tool:
    def __init__(self, name="tool"):
        self.name = name


class FunctionTool:
    """Captures the same args the real SDK FunctionTool takes."""
    def __init__(self, name, description, params_json_schema, on_invoke_tool):
        self.name = name
        self.description = description
        self.params_json_schema = params_json_schema
        self.on_invoke_tool = on_invoke_tool


for _n, _o in [("AgentHooks", AgentHooks), ("RunContextWrapper", RunContextWrapper),
               ("Agent", Agent), ("Tool", Tool), ("FunctionTool", FunctionTool)]:
    setattr(_stub, _n, _o)
sys.modules["agents"] = _stub

import eidos  # noqa: E402  (must come after the stub injection)

# ── Tiny inline island server (auto-approve) on a free port ──────────────────
PORT = 7799
_AGENTS = {}


class _H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, status, obj):
        b = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/status":
            self._json(200, {"running": True, "agents": list(_AGENTS.values())})
        else:
            self._json(404, {"error": "nf"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(n) or b"{}")
        if self.path == "/event":
            _AGENTS[payload.get("agent")] = {"agent": payload.get("agent"),
                                             "status": payload.get("status")}
            EVENTS.append(payload)
            self._json(200, {"ok": True})
        elif self.path == "/approve":
            APPROVE_REQUESTS.append(payload)
            self._json(200, {"approved": True, "modified": None})
        else:
            self._json(404, {"error": "nf"})


EVENTS = []
APPROVE_REQUESTS = []

passed = failed = 0


def check(name, cond):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}")


def main():
    global passed, failed
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), _H)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    time.sleep(0.3)
    print("Testing real eidos.py against inline island\n")

    # 1. connectivity
    check("eidos.island_running() is True", eidos.island_running() is True)

    # 2. IslandHook.on_start posts a running event
    hook = eidos.IslandHook("codex")
    agent = _stub.Agent(name="Codex", instructions="Refactor the auth module. Then test it.")
    hook.on_start(_stub.RunContextWrapper(), agent)
    time.sleep(0.2)
    check("on_start sent an event", len(EVENTS) >= 1)
    check("event has agent=codex", EVENTS[-1].get("agent") == "codex")
    check("event status=running", EVENTS[-1].get("status") == "running")
    check("task derived from instructions",
          EVENTS[-1].get("task") == "Refactor the auth module")

    # 3. on_end posts done
    hook.on_end(_stub.RunContextWrapper(), agent, "result")
    time.sleep(0.2)
    check("on_end sent done", EVENTS[-1].get("status") == "done")

    # 4. approval_tool invokes /approve and returns the decision
    tool = eidos.approval_tool("codex")
    check("approval_tool name is request_approval", tool.name == "request_approval")
    args = json.dumps({"actions": [
        {"op": "edit", "target": "src/auth/jwt.ts", "description": "HS256->RS256"},
        {"op": "run", "target": "npm install jsonwebtoken@9"},
    ]})
    out = tool.on_invoke_tool(None, args)
    result = json.loads(out)
    check("approval returned approved=True", result.get("approved") is True)
    check("/approve received the request", len(APPROVE_REQUESTS) == 1)
    check("/approve summarized task",
          "Edit 1 file" in APPROVE_REQUESTS[-1].get("task", "")
          and "Run 1 command" in APPROVE_REQUESTS[-1].get("task", ""))

    # 5. island-unavailable fallback (server down) -> approved True by design.
    # Must server_close() too: shutdown() stops serving but leaves the listening
    # socket open, which would accept-but-never-handle the next connection.
    srv.shutdown()
    srv.server_close()
    time.sleep(0.2)
    check("island_running() False when down", eidos.island_running() is False)
    out2 = tool.on_invoke_tool(None, args)
    r2 = json.loads(out2)
    check("fallback approves when island down (per eidos.py default)",
          r2.get("approved") is True and r2.get("reason") == "island_unavailable")

    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
