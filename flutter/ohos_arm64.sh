#!/usr/bin/env bash
# Build RustDesk core library for HarmonyOS NEXT / OpenHarmony (aarch64)
# Requires OHOS_NDK_HOME or OpenHarmony SDK configured

set -e

TARGET="aarch64-unknown-linux-ohos"

echo "Building librustdesk for ${TARGET}..."
cargo build --features flutter --release --target "${TARGET}" --lib

echo "Build successful: target/${TARGET}/release/librustdesk.so"
