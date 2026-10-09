#!/usr/bin/env bash
# Build the wasm UI. Run inside:  nix develop .#wasm
set -euo pipefail
cd "$(dirname "$0")"
: "${QT_WASM_TOOLCHAIN:?not in the wasm dev shell - run: nix develop .#wasm}"

cmake -G Ninja -B build \
  -DCMAKE_TOOLCHAIN_FILE="$QT_WASM_TOOLCHAIN" \
  -DQT_ADDITIONAL_PACKAGES_PREFIX_PATH="$QT_ADDITIONAL_PACKAGES_PREFIX_PATH" \
  -DQT_HOST_PATH="$QT_HOST_PATH" \
  -DCXXQT_QMAKE="$CXXQT_QMAKE" \
  -DCMAKE_BUILD_TYPE=Release \
  .

cmake --build build --parallel "${JOBS:-2}"
echo
ls -la build/nixdash_ui_wasm_app.{html,js,wasm}
