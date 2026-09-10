# Build the RustDesk core + Node-API bridge for HarmonyOS and deploy the module into the
# HAP's native library directory.
#
# Usage (from the repository root, or anywhere -- paths are resolved from this file):
#   pwsh -File flutter/ohos/build_bridge.ps1
#
# Produces:
#   flutter/ohos/entry/libs/arm64-v8a/librustdesk_ohos.so
# which ArkTS imports as `import bridge from 'librustdesk_ohos.so'`.
#
# The location matters: hvigor packages prebuilt native libraries from the MODULE ROOT
# libs/<abi> directory. A copy under entry/src/main/libs/<abi> compiles fine but is silently
# left out of the HAP, so the import resolves at build time and then fails on device.
#
# The .so is a build artifact and is gitignored, matching how the Android build treats
# jniLibs: run this script after cloning, before building the HAP.
#
# Requires the environment described in flutter/ohos/PLAN.md: rustup with the
# aarch64-unknown-linux-ohos target, the DevEco OHOS NDK reachable as C:\ohos-ndk (a
# space-free junction), a mingw-w64 host toolchain, prebuilt OpenSSL for ohos, and a
# cross-built libopus. rust_ohos_build.ps1 carries the rest of the wiring.

param(
  # Skip the cargo build and only re-deploy the last artifact.
  [switch]$DeployOnly
)

$ErrorActionPreference = "Stop"

$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo   = (Resolve-Path (Join-Path $here "..\..")).Path
$native = Join-Path $here "native"

# The space-free junction to the DevEco OHOS NDK, created by setup_ohos_toolchain.ps1.
$NdkLink = "C:\ohos-ndk"

# napi-build-ohos reads OHOS_NDK_HOME; without it the build script panics.
$env:OHOS_NDK_HOME = $NdkLink

if (-not $DeployOnly) {
  Write-Host "Building the core + bridge for aarch64-unknown-linux-ohos..." -ForegroundColor Cyan
  & pwsh -File (Join-Path $here "rust_ohos_build.ps1") `
      -Release -Package rustdesk-ohos-bridge -Features ""
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Bridge build failed; not deploying." -ForegroundColor Red
    exit $LASTEXITCODE
  }
}

# The workspace target dir is shared with the core build, so the artifact lands there
# rather than under flutter/ohos/native/target.
$built = Join-Path $repo "target\aarch64-unknown-linux-ohos\release\librustdesk_ohos.so"
if (-not (Test-Path $built)) {
  Write-Host "Missing build artifact: $built" -ForegroundColor Red
  Write-Host "Run without -DeployOnly, or build the bridge first." -ForegroundColor Red
  exit 1
}

$destDir = Join-Path $here "entry\libs\arm64-v8a"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$dest = Join-Path $destDir "librustdesk_ohos.so"
Copy-Item $built $dest -Force

# Bundle the libc++ the core was linked against.
#
# The core needs libc++_shared.so, and the device ships its own. Those are not the same
# build: on the LMR-AL10 used for testing the system copy is 1291536 bytes dated 2024-06-06
# while this SDK's is 1262504 bytes dated 2026-08-27. A newer libc++ references symbols an
# older one does not export, and dlopen then fails with an unresolved symbol -- which
# surfaces as a jscrash the moment ArkTS imports the module, with nothing in hilog.
# Shipping the matching copy next to the module makes the app use it instead of the
# system's, which is the same thing the Android NDK guidance says to do.
$libcxx = Join-Path $NdkLink "llvm\lib\arm64-v8a\libc++_shared.so"
if (-not (Test-Path $libcxx)) {
  # The NDK keeps it under the llvm lib dir named after the target triple.
  $libcxx = "$NdkLink\llvm\lib\aarch64-linux-ohos\libc++_shared.so"
}
if (Test-Path $libcxx) {
  Copy-Item $libcxx (Join-Path $destDir "libc++_shared.so") -Force
  $lc = [math]::Round((Get-Item (Join-Path $destDir "libc++_shared.so")).Length / 1KB, 0)
  Write-Host "Bundled libc++_shared.so ($lc KB)" -ForegroundColor Green
} else {
  Write-Host "WARNING: could not find libc++_shared.so under $NdkLink\llvm\lib; the app will" -ForegroundColor Yellow
  Write-Host "         fall back to the device's copy, which may be an incompatible version." -ForegroundColor Yellow
}

$mb = [math]::Round((Get-Item $dest).Length / 1MB, 2)
Write-Host "Deployed $mb MB -> $dest" -ForegroundColor Green
