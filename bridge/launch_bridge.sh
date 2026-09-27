#!/usr/bin/env bash
# Rick & Morty AI Executor - Cowork bridge launcher (macOS / Linux)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo
  echo "  Node.js was not found on your PATH."
  echo "  Install it from https://nodejs.org (LTS, 18 or newer) and run this file again."
  echo
  exit 1
fi

echo
echo "  Starting the Cowork bridge on http://localhost:7896 ..."
echo

# Open the browser when a desktop session is available (best effort).
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "http://localhost:7896" >/dev/null 2>&1 &
elif command -v open >/dev/null 2>&1; then
  open "http://localhost:7896" >/dev/null 2>&1 &
fi

node server.js
