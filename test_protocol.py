#!/usr/bin/env python3
"""
test_protocol.py — exercise the Eidos HTTP contract against a running server.

Works against either mock_island.py OR the real Eidos.app (both implement the
same contract). Uses only the standard library so it runs anywhere.

    python3 test_protocol.py                 # against localhost:7799
    python3 test_protocol.py --port 8080

Exit code 0 = all assertions passed.
"""
import argparse
import json
import sys
import time
import urllib.request


def _post(url, obj, timeout):
    data = json.dumps(obj).encode()
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json"},
                                 method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, json.loads(r.read() or b"{}")


def _get(url, timeout):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.status, json.loads(r.read() or b"{}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=7799)
    args = ap.parse_args()
    base = f"http://127.0.0.1:{args.port}"

    passed = 0
    failed = 0

    def check(name, cond):
        nonlocal passed, failed
        if cond:
            passed += 1
            print(f"  PASS  {name}")
        else:
            failed += 1
            print(f"  FAIL  {name}")

    print(f"Testing Eidos contract at {base}\n")

    # 1. /event running
    st, body = _post(f"{base}/event", {
        "agent": "codex", "status": "running",
        "task": "Refactor auth module", "progress": 0.0, "elapsed": 0,
    }, timeout=3)
    check("POST /event returns 200", st == 200)
    check("POST /event returns ok=true", body.get("ok") is True)

    # 2. /status reflects the agent
    st, body = _get(f"{base}/status", timeout=3)
    check("GET /status returns 200", st == 200)
    check("GET /status running=true", body.get("running") is True)
    agents = body.get("agents", [])
    check("GET /status lists codex", any(a.get("agent") == "codex" for a in agents))

    # 3. /event progress update
    st, _ = _post(f"{base}/event", {
        "agent": "codex", "status": "running",
        "task": "Refactor auth module", "progress": 0.65,
    }, timeout=3)
    check("POST /event progress update 200", st == 200)

    # 4. /approve blocks then returns a decision shape
    t0 = time.time()
    st, body = _post(f"{base}/approve", {
        "agent": "codex",
        "task": "Update config files",
        "actions": [
            {"op": "edit", "target": "config/app.ts"},
            {"op": "run", "target": "npm install dotenv"},
            {"op": "create", "target": "config/.env.example"},
        ],
    }, timeout=125)
    dt = time.time() - t0
    check("POST /approve returns 200", st == 200)
    check("POST /approve has 'approved' bool", isinstance(body.get("approved"), bool)
          if "approved" in body else False)
    check("POST /approve has 'modified' key", "modified" in body)
    print(f"        (approve resolved in {dt:.2f}s, decision={body.get('approved')})")

    # 5. /event done
    st, _ = _post(f"{base}/event", {
        "agent": "codex", "status": "done", "progress": 1.0,
    }, timeout=3)
    check("POST /event done 200", st == 200)

    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
