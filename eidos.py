"""
eidos.py — Agent Island integration for OpenAI Agents SDK
Drop this file into any project that uses the OpenAI Agents SDK.

Usage:
    from eidos import IslandHook, approval_tool

    agent = Agent(
        name="Codex",
        hooks=IslandHook("codex"),
        tools=[approval_tool("codex"), ...your tools...],
    )
"""

import json
import time
import uuid
from typing import Any

try:
    import httpx
except ImportError:
    raise ImportError("eidos.py requires httpx: pip install httpx")

try:
    from agents import AgentHooks, RunContextWrapper, Agent, Tool, FunctionTool
except ImportError:
    raise ImportError("eidos.py requires the OpenAI Agents SDK: pip install openai-agents")

ISLAND_URL = "http://localhost:7799"
DEFAULT_TIMEOUT = 2.0       # status event timeout (fire-and-forget)
APPROVAL_TIMEOUT = 120.0    # approval long-poll timeout


class IslandHook(AgentHooks):
    """
    Lifecycle hook that streams agent status to the Eidos island.
    Silently no-ops if the island is not running.

    Args:
        agent_id: short identifier shown in the island (e.g. "codex", "claude")
        island_url: defaults to http://localhost:7799
    """

    def __init__(self, agent_id: str, island_url: str = ISLAND_URL):
        self.agent_id = agent_id
        self.island_url = island_url
        self._client = httpx.Client(timeout=DEFAULT_TIMEOUT)
        self._start_time: float | None = None

    def _post(self, status: str, **kwargs: Any) -> None:
        try:
            payload = {
                "agent": self.agent_id,
                "status": status,
                "elapsed": int(time.time() - self._start_time) if self._start_time else 0,
                **kwargs,
            }
            self._client.post(f"{self.island_url}/event", json=payload)
        except Exception:
            pass  # island might not be running — that's fine

    def on_start(self, context: RunContextWrapper, agent: Agent) -> None:
        self._start_time = time.time()
        task = ""
        if isinstance(agent.instructions, str):
            # Use first sentence of instructions as the task label
            task = agent.instructions.split(".")[0][:80]
        elif callable(agent.instructions):
            task = agent.name
        self._post("running", task=task or agent.name, progress=0.0)

    def on_end(self, context: RunContextWrapper, agent: Agent, output: Any) -> None:
        self._post("done", progress=1.0)

    def on_tool_start(self, context: RunContextWrapper, agent: Agent, tool: Tool) -> None:
        self._post("running", task=f"Using {tool.name}")

    def on_tool_end(self, context: RunContextWrapper, agent: Agent, tool: Tool, result: str) -> None:
        # just a progress tick; actual progress is approximate
        pass

    def on_handoff(self, context: RunContextWrapper, agent: Agent, source: Agent) -> None:
        self._start_time = time.time()
        self._post("running", task=f"Handed off from {source.name}", progress=0.0)

    def __del__(self):
        try:
            self._client.close()
        except Exception:
            pass


def approval_tool(agent_id: str, island_url: str = ISLAND_URL) -> FunctionTool:
    """
    Returns a FunctionTool that pauses agent execution and asks the user via the island.
    The agent blocks until the user taps Approve or Reject.

    Add this to your agent's tools list. Instruct the agent to call it before
    any file writes, shell commands, or other side-effecting actions.

    Args:
        agent_id: same id used in IslandHook
        island_url: defaults to http://localhost:7799

    Returns:
        FunctionTool named "request_approval"

    Example agent instruction:
        "Before writing to any files or running shell commands, you MUST call
        request_approval with a full list of actions. Only proceed after approval."
    """

    def _request_approval(actions: list[dict]) -> dict:
        """
        Request user approval before executing a list of actions.
        Blocks until the user approves or rejects in the island UI.

        Args:
            actions: list of action dicts with keys:
                - op (str): "edit" | "create" | "delete" | "run" | "read"
                - target (str): file path or command
                - description (str, optional): human-readable explanation

        Returns:
            dict with keys:
                - approved (bool): whether the user approved
                - modified (dict | None): any user modifications (e.g. skip_actions)
        """
        request_id = str(uuid.uuid4())
        payload = {
            "agent": agent_id,
            "requestID": request_id,
            "task": _summarize_actions(actions),
            "actions": actions,
        }
        try:
            with httpx.Client(timeout=APPROVAL_TIMEOUT) as client:
                resp = client.post(f"{island_url}/approve", json=payload)
                result = resp.json()
                return result
        except httpx.TimeoutException:
            # User didn't respond in time — treat as rejection for safety
            return {"approved": False, "modified": None, "reason": "timeout"}
        except Exception:
            # Island not running — auto-approve so the agent can continue
            # Change to return {"approved": False} if you want to be conservative
            return {"approved": True, "modified": None, "reason": "island_unavailable"}

    return FunctionTool(
        name="request_approval",
        description=(
            "Request user approval before executing file edits, shell commands, or other "
            "actions with side effects. Always call this before writing files, running "
            "commands, installing packages, or making any changes to the system. "
            "The function blocks until the user approves or rejects."
        ),
        params_json_schema={
            "type": "object",
            "properties": {
                "actions": {
                    "type": "array",
                    "description": "List of actions to request approval for.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "op": {
                                "type": "string",
                                "enum": ["edit", "create", "delete", "run", "read", "open"],
                                "description": "Operation type",
                            },
                            "target": {
                                "type": "string",
                                "description": "File path or shell command",
                            },
                            "description": {
                                "type": "string",
                                "description": "Optional human-readable explanation of why",
                            },
                        },
                        "required": ["op", "target"],
                    },
                }
            },
            "required": ["actions"],
        },
        on_invoke_tool=lambda ctx, args_str: json.dumps(
            _request_approval(json.loads(args_str).get("actions", []))
        ),
    )


def _summarize_actions(actions: list[dict]) -> str:
    """Generate a short human-readable summary for the island approval header."""
    if not actions:
        return "Unknown actions"
    ops: dict[str, int] = {}
    for a in actions:
        op = a.get("op", "unknown")
        ops[op] = ops.get(op, 0) + 1
    parts = []
    if ops.get("edit"):
        parts.append(f"Edit {ops['edit']} file{'s' if ops['edit'] > 1 else ''}")
    if ops.get("create"):
        parts.append(f"Create {ops['create']} file{'s' if ops['create'] > 1 else ''}")
    if ops.get("delete"):
        parts.append(f"Delete {ops['delete']} file{'s' if ops['delete'] > 1 else ''}")
    if ops.get("run"):
        parts.append(f"Run {ops['run']} command{'s' if ops['run'] > 1 else ''}")
    return " + ".join(parts) if parts else "Perform actions"


# ── Quick connectivity check ──────────────────────────────────────────────────

def island_running(island_url: str = ISLAND_URL) -> bool:
    """Returns True if the Eidos island app is running and reachable."""
    try:
        resp = httpx.get(f"{island_url}/status", timeout=1.0)
        return resp.status_code == 200
    except Exception:
        return False


# ── Example usage (run this file directly to test) ───────────────────────────

if __name__ == "__main__":
    import sys

    print(f"Checking if island is running at {ISLAND_URL}...")
    if island_running():
        print("Island is running.")
    else:
        print("Island is NOT running. Start the Eidos app first.")
        sys.exit(1)

    # Send a test event
    hook = IslandHook("codex")
    print("Sending test status event...")

    with httpx.Client(timeout=2.0) as c:
        c.post(f"{ISLAND_URL}/event", json={
            "agent": "codex",
            "status": "running",
            "task": "eidos.py connectivity test",
            "progress": 0.5,
            "elapsed": 0,
        })
    print("Event sent. You should see the island switch to mini state.")

    print("\nSending test approval request (will block until you respond in the island)...")
    with httpx.Client(timeout=30.0) as c:
        resp = c.post(f"{ISLAND_URL}/approve", json={
            "agent": "codex",
            "task": "Test approval flow",
            "actions": [
                {"op": "edit",   "target": "src/test.ts",         "description": "Connectivity test"},
                {"op": "run",    "target": "echo hello"},
                {"op": "create", "target": "src/generated/test.ts"},
            ],
        })
        result = resp.json()
        print(f"User decision: {'APPROVED' if result.get('approved') else 'REJECTED'}")

    # Done
    with httpx.Client(timeout=2.0) as c:
        c.post(f"{ISLAND_URL}/event", json={
            "agent": "codex", "status": "done", "progress": 1.0
        })
    print("Done.")
