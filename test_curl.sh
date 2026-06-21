#!/bin/bash
# Smoke test for the IslandServer HTTP API
# Run after Phase 3 (IslandServer implemented)
# Usage: bash test_curl.sh

BASE="http://localhost:7799"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Eidos Island smoke test ===${NC}"
echo ""

echo "1. Checking /status..."
curl -s "$BASE/status" | python3 -m json.tool
echo ""

echo -e "2. Sending ${YELLOW}running${NC} event for 'codex'..."
curl -s -X POST "$BASE/event" \
  -H "Content-Type: application/json" \
  -d '{"agent":"codex","status":"running","task":"Refactoring auth module","progress":0.0,"elapsed":0}'
echo ""
sleep 1

echo "3. Progress update..."
curl -s -X POST "$BASE/event" \
  -H "Content-Type: application/json" \
  -d '{"agent":"codex","status":"running","task":"Refactoring auth module","progress":0.45,"elapsed":30}'
echo ""
sleep 1

echo "4. Second agent joins..."
curl -s -X POST "$BASE/event" \
  -H "Content-Type: application/json" \
  -d '{"agent":"claude","status":"running","task":"Writing unit tests","progress":0.1,"elapsed":5}'
echo ""
sleep 2

echo -e "5. ${YELLOW}Approval request${NC} (will BLOCK until you tap in the island)..."
echo "   → Switch to the island and tap Approve or Reject"
curl -s -X POST "$BASE/approve" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "codex",
    "task": "Edit 3 files + run npm install",
    "actions": [
      {"op": "edit",   "target": "src/auth/jwt.ts",         "description": "Replace HS256 signing with RS256"},
      {"op": "edit",   "target": "src/middleware/session.ts","description": "Update session expiry handling"},
      {"op": "create", "target": "src/auth/refresh.ts",      "description": "New refresh token handler"},
      {"op": "run",    "target": "npm install jsonwebtoken@9"}
    ]
  }' | python3 -m json.tool
echo ""

echo "6. Codex marks done..."
curl -s -X POST "$BASE/event" \
  -H "Content-Type: application/json" \
  -d '{"agent":"codex","status":"done","progress":1.0}'
echo ""

sleep 5

echo "7. Claude marks done..."
curl -s -X POST "$BASE/event" \
  -H "Content-Type: application/json" \
  -d '{"agent":"claude","status":"done","progress":1.0}'
echo ""

echo -e "${GREEN}Done. Island should return to idle after ~4 seconds.${NC}"
