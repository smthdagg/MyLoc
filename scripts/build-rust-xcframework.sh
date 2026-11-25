#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CRATE_DIR="$ROOT_DIR/Rust/myloc-engine"
OUT_DIR="$ROOT_DIR/Frameworks"
XCFRAMEWORK="$OUT_DIR/MyLocEngine.xcframework"

echo "=== Building myloc-engine for aarch64-apple-ios ==="
cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target aarch64-apple-ios

echo "=== Building myloc-engine for aarch64-apple-ios-sim ==="
cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target aarch64-apple-ios-sim

rm -rf "$XCFRAMEWORK"
mkdir -p "$OUT_DIR"

echo "=== Creating MyLocEngine.xcframework ==="
xcodebuild -create-xcframework \
  -library "$CRATE_DIR/target/aarch64-apple-ios/release/libmyloc_engine.a" \
  -headers "$CRATE_DIR/include" \
  -library "$CRATE_DIR/target/aarch64-apple-ios-sim/release/libmyloc_engine.a" \
  -headers "$CRATE_DIR/include" \
  -output "$XCFRAMEWORK"

echo "=== Done: $XCFRAMEWORK ==="
