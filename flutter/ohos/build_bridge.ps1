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

  # libsodium is attached with a raw `-C link-arg=<path>/libsodium.a` in
  # .cargo/config.toml, and cargo does not fingerprint the CONTENT of a link-arg. Rebuilding
  # libsodium therefore does not trigger a relink: the module silently keeps whatever was
  # linked last time. That is how a fixed libsodium archive produced an unchanged .so.
  # Touching a source file in the final crate forces the relink.
  $stamp = Get-Item (Join-Path $native "src\lib.rs") -ErrorAction SilentlyContinue
  if ($stamp) { $stamp.LastWriteTime = Get-Date }

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

# ---------------------------------------------------------------------------
# Fail loudly on a dependency the device cannot satisfy.
#
# This check exists because the same class of bug has now shipped twice and reached the
# device both times. The module is loaded by name, so a missing NEEDED entry does not fail
# the build or the install -- it fails at dlopen, where ArkTS only reports that the module is
# undefined. libsodium was one case (wrong architecture, resolved symbols) and OpenSSL the
# other (libssl.so, absent from the system).
#
# HarmonyOS provides these; anything else has to be bundled next to the module.
$systemLibs = @(
  'libc.so', 'libc++_shared.so', 'libm.so', 'libdl.so', 'libz.so',
  'libace_napi.z.so', 'libace_compatible.z.so', 'libhilog.so', 'libhitrace.so',
  'libnative_window.so', 'libnative_vsync.so', 'libnative_buffer.so',
  'libnative_image.so', 'libpixelmap.so', 'libimage_source.so',
  'libjnigraphics.so', 'libEGL.so', 'libGLESv3.so', 'libvulkan.so',
  'libhidumper.so', 'libparameter.so', 'libbegetutil.so'
)

$readelf = Join-Path $NdkLink "llvm\bin\llvm-readelf.exe"
if (Test-Path $readelf) {
  $needed = & $readelf -d $dest 2>$null |
    Select-String -Pattern '\(NEEDED\)' |
    ForEach-Object { if ($_.Line -match '\[([^\]]+)\]') { $Matches[1] } }

  $bundled = @{}
  Get-ChildItem $destDir -Filter '*.so' | ForEach-Object { $bundled[$_.Name] = $true }

  $missing = @($needed | Where-Object { $systemLibs -notcontains $_ -and -not $bundled.ContainsKey($_) })
  if ($missing.Count -gt 0) {
    Write-Host "UNRESOLVABLE DEPENDENCY -- the module will fail to load on device:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "Bundle it into $destDir, or link it statically." -ForegroundColor Red
    exit 1
  }
  Write-Host "Dependencies OK: $($needed.Count) NEEDED, all satisfied" -ForegroundColor Green
}
