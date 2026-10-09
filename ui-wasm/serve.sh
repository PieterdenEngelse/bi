#!/usr/bin/env bash
# Qt wasm must be served over http:// - file:// is blocked by CORS.
set -euo pipefail
cd "$(dirname "$0")"
command -v python3 >/dev/null || { echo "run inside: nix develop .#wasm" >&2; exit 1; }
[ -f build/nixdash_ui_wasm_app.html ] || { echo "run ./build.sh first" >&2; exit 1; }
cd build
PORT="${PORT:-8099}"
echo "http://127.0.0.1:$PORT/nixdash_ui_wasm_app.html"
echo "(the engine must also be running: cargo run -p nixdash-engine)"
exec python3 -m http.server "$PORT" --bind 127.0.0.1
