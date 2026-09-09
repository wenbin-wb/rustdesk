#!/usr/bin/env bash
# Build RustDesk Flutter HAP for HarmonyOS NEXT / OpenHarmony
# Requires flutter-ohos SDK in PATH

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Step 1: Building Rust shared library for HarmonyOS..."
bash ./ohos_arm64.sh

echo "Step 2: Copying librustdesk.so to ohos entry libs..."
mkdir -p ./ohos/entry/src/main/libs/arm64-v8a
cp ../target/aarch64-unknown-linux-ohos/release/librustdesk.so ./ohos/entry/src/main/libs/arm64-v8a/

echo "Step 3: Building Flutter HAP..."
flutter build hap --release

echo "Build complete! Output located in ./ohos/entry/build/default/outputs/default/"
