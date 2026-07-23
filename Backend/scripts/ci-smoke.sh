#!/usr/bin/env bash
# Boot a mock SceneMe API and run the smoke suite. Used by npm run test:smoke / CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT="${SMOKE_PORT:-8099}"
BASE="http://127.0.0.1:${PORT}"
export STYLEAI_ENABLE_MOCK_GENERATION=true
export STYLEAI_REUSE_IDENTICAL_RESULTS=true
export STYLEAI_JWT_SECRET="${STYLEAI_JWT_SECRET:-ci-test-secret-at-least-32-characters-long}"
export PORT
export PUBLIC_BASE_URL="$BASE"
export SMOKE_BASE_URL="$BASE"

node src/server.mjs &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 40); do
  if curl -fsS "$BASE/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

curl -fsS "$BASE/health" >/dev/null

node scripts/smoke-test.mjs
echo "CI smoke OK"
