# Recreate the HarmonyOS cross-compilation toolchain on a fresh Windows machine.
#
# Usage (from anywhere):
#   pwsh -File flutter/ohos/setup_ohos_toolchain.ps1
#
# Idempotent: every step checks for its result first, so re-running is safe and a partial
# run can be resumed. Run it once after cloning, then use build_bridge.ps1 to build.
#
# What this sets up, and why each piece is needed -- every one of these was hit as a
# blocker while getting the core to link, so they are not optional extras:
#
#   %USERPROFILE%\mingw-tools\mingw64   Host toolchain for the rustup windows-gnu target.
#                                       binutils gives dlltool (windows-sys needs it),
#                                       gcc builds host build scripts (ring needs it),
#                                       and crt/headers/winpthreads are needed to link.
#   C:\ohos-ndk                         Junction to the DevEco OHOS NDK. A junction exists
#                                       because the real path contains spaces and
#                                       --sysroot= cannot carry one.
#   %USERPROFILE%\ohos-openssl          Prebuilt OpenSSL for ohos. HarmonyOS has no system
#                                       OpenSSL and vendoring it needs perl.
#   %USERPROFILE%\ohos-libs\prefix      libopus cross-built for ohos (magnum-opus needs it).
#   C:\ohos-vcpkg-root                  VCPKG_ROOT layout pointing at that opus, because
#                                       magnum-opus selects pkg-config vs vcpkg with
#                                       cfg(target_os = "linux") -- the HOST in a build
#                                       script -- so on Windows only the vcpkg route works.
#
# Requires: DevEco Studio installed (the SDK path below), and network access to the TUNA
# MSYS2 mirror and crates.io.

param(
  # DevEco Studio installation root.
  [string]$DevEco = "D:\Program Files\Huawei\DevEco Studio",
  # Where the space-free junction to the OHOS NDK is created.
  [string]$NdkLink = "C:\ohos-ndk"
)

$ErrorActionPreference = "Stop"

$msysBase   = "https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/mingw64/"
$mingwRoot  = "$env:USERPROFILE\mingw-tools"
$mingwBin   = "$mingwRoot\mingw64\bin"
$ohosSdk    = "$DevEco\sdk\default\openharmony"
$opensslDir = "$env:USERPROFILE\ohos-openssl"
$libsDir    = "$env:USERPROFILE\ohos-libs"
$vcpkgRoot  = "C:\ohos-vcpkg-root"

function Step($msg) { Write-Host "== $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Skip($msg) { Write-Host "   already done: $msg" -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
# Run first: the source-side half of the port.
#
# libs/hbb_common is a submodule pointing at upstream rustdesk/hbb_common, and several of
# its files need `target_env = "ohos"` gates (see the patch subjects). Those changes live
# here as patches rather than as a pinned submodule commit, because a local commit cannot
# be fetched by anyone else -- `git submodule update` would simply fail. The patches are
# also what an upstream PR would carry.
Step "Applying the HarmonyOS patches to libs/hbb_common"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sub  = Join-Path $repo "libs\hbb_common"
$patches = Join-Path $PSScriptRoot "patches\hbb_common"

if (-not (Test-Path (Join-Path $sub "Cargo.toml"))) {
  Write-Host "   initialising the submodule" -ForegroundColor DarkGray
  & git -C $repo submodule update --init libs/hbb_common
  if ($LASTEXITCODE -ne 0) { throw "git submodule update failed" }
}

$pending = @(Get-ChildItem $patches -Filter "*.patch" -ErrorAction SilentlyContinue)
if ($pending.Count -eq 0) {
  Write-Host "   no patches found in $patches; skipping" -ForegroundColor Yellow
} else {
  # Detect an already-applied patch by asking git whether it can be reversed; this is what
  # makes re-running the setup safe.
  $applied = 0
  foreach ($p in $pending) {
    & git -C $sub apply --reverse --check $p.FullName 2>$null
    if ($LASTEXITCODE -eq 0) { $applied++ }
  }
  if ($applied -eq $pending.Count) {
    Skip "$applied/$($pending.Count) patches already applied"
  } else {
    # A detached HEAD after `submodule update` would leave the commits unreferenced, so put
    # them on a branch first.
    $head = (& git -C $sub rev-parse --abbrev-ref HEAD).Trim()
    if ($head -eq "HEAD") {
      & git -C $sub checkout -b feat/harmonyos-ohos 2>$null | Out-Null
    }
    foreach ($p in $pending) {
      & git -C $sub am $p.FullName
      if ($LASTEXITCODE -ne 0) {
        Write-Host "   '$($p.Name)' did not apply cleanly. Resolve it in libs/hbb_common," -ForegroundColor Yellow
        Write-Host "   then 'git am --continue' (or 'git am --skip'), and re-run this script." -ForegroundColor Yellow
        throw "patch failed: $($p.Name)"
      }
    }
    # `am` leaves a stray .git/rebase-apply on some failures; make sure it is gone.
    if (Test-Path (Join-Path $sub ".git\rebase-apply")) {
      & git -C $sub am --abort
    }
    Ok "applied $($pending.Count) patches"
  }
}

# ---------------------------------------------------------------------------
Step "Checking DevEco Studio"
if (-not (Test-Path $ohosSdk)) { throw "OHOS SDK not found at $ohosSdk. Pass -DevEco <path>." }
Ok "SDK: $ohosSdk"

# ---------------------------------------------------------------------------
Step "Rust toolchain"
$cargo  = "$env:USERPROFILE\.cargo\bin\cargo.exe"
$rustup = "$env:USERPROFILE\.cargo\bin\rustup.exe"
if (-not (Test-Path $cargo)) {
  throw "cargo not found. Install rustup first (the GNU host is what this project uses): " +
        "rustup-init.exe -y --default-host x86_64-pc-windows-gnu --profile minimal"
}
Ok (& $cargo --version)
if ((& $rustup target list --installed) -notmatch 'aarch64-unknown-linux-ohos') {
  & $rustup target add aarch64-unknown-linux-ohos
  Ok "added target aarch64-unknown-linux-ohos"
} else { Skip "target aarch64-unknown-linux-ohos" }

# ---------------------------------------------------------------------------
Step "mingw-w64 host toolchain (dlltool, gcc, crt, headers, winpthreads)"
if (Test-Path "$mingwBin\gcc.exe") {
  Skip "mingw at $mingwBin"
} else {
  New-Item -ItemType Directory -Force -Path $mingwRoot | Out-Null
  Write-Host "   fetching package list..." -ForegroundColor DarkGray
  $listing = (Invoke-WebRequest -Uri $msysBase -TimeoutSec 60 -UseBasicParsing).Links |
    Select-Object -ExpandProperty href | Where-Object { $_ -notmatch '\.sig$' }

  # Exact names differ per build, so match by pattern and take the newest.
  $want = @(
    '^mingw-w64-x86_64-binutils-\d',
    '^mingw-w64-x86_64-gcc-\d',
    '^mingw-w64-x86_64-crt-\d',
    '^mingw-w64-x86_64-headers-\d',
    '^mingw-w64-x86_64-winpthreads-git-',
    '^mingw-w64-x86_64-gcc-libs-\d',
    '^mingw-w64-x86_64-libiconv-\d',
    '^mingw-w64-x86_64-gettext-runtime-\d',
    '^mingw-w64-x86_64-zlib-\d',
    '^mingw-w64-x86_64-zstd-\d',
    '^mingw-w64-x86_64-pkgconf-\d'
  )

  # .pkg.tar.zst is a zstd-compressed tar and Windows ships no zstd, so decompress with
  # Node (v22+ has zlib.zstdDecompressSync) and let tar handle the plain tar.
  $unzst = Join-Path $mingwRoot 'unzst.js'
  Set-Content -Path $unzst -Value @'
const fs = require('fs'), zlib = require('zlib');
const out = zlib.zstdDecompressSync(fs.readFileSync(process.argv[2]));
fs.writeFileSync(process.argv[3], out);
'@

  foreach ($pat in $want) {
    $pkg = $listing | Where-Object { $_ -match $pat } | Select-Object -Last 1
    if (-not $pkg) { Write-Host "   no match for $pat (skipping)" -ForegroundColor Yellow; continue }
    $zst = Join-Path $mingwRoot $pkg
    $tar = Join-Path $mingwRoot ($pkg -replace '\.zst$','')
    if (-not (Test-Path $tar)) {
      if (-not (Test-Path $zst)) {
        Write-Host "   downloading $pkg" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri "$msysBase$pkg" -OutFile $zst -TimeoutSec 300 -UseBasicParsing
      }
      node $unzst $zst $tar
    }
    tar -xf $tar -C $mingwRoot
  }
  if (-not (Test-Path "$mingwBin\gcc.exe")) { throw "mingw install incomplete: no gcc.exe" }
  Ok "mingw installed"
}

# ---------------------------------------------------------------------------
Step "Space-free junction to the OHOS NDK"
if (Test-Path $NdkLink) {
  Skip "$NdkLink"
} else {
  New-Item -ItemType Junction -Path $NdkLink -Target "$ohosSdk\native" | Out-Null
  Ok "$NdkLink -> $ohosSdk\native"
}

# ---------------------------------------------------------------------------
Step "Prebuilt OpenSSL for ohos"
$opensslPre = "$opensslDir\ohos-openssl-main\prelude\arm64-v8a"
if (Test-Path "$opensslPre\lib\libcrypto.a") {
  Skip "openssl at $opensslPre"
} else {
  New-Item -ItemType Directory -Force -Path $opensslDir | Out-Null
  $zip = "$opensslDir\ohos-openssl.zip"
  Write-Host "   downloading ohos-rs/ohos-openssl (~40 MB, this is the slow step)" -ForegroundColor DarkGray
  Invoke-WebRequest -Uri "https://codeload.github.com/ohos-rs/ohos-openssl/zip/refs/heads/main" `
    -OutFile $zip -TimeoutSec 900 -UseBasicParsing
  Expand-Archive -Path $zip -DestinationPath $opensslDir -Force
  if (-not (Test-Path "$opensslPre\lib\libcrypto.a")) { throw "openssl extract incomplete" }
  Ok "openssl installed"
}

# ---------------------------------------------------------------------------
Step "libopus cross-compiled for ohos"
$opusPrefix = "$libsDir\prefix"
if (Test-Path "$opusPrefix\lib\libopus.a") {
  Skip "opus at $opusPrefix"
} else {
  $cmake  = "$NdkLink\build-tools\cmake\bin\cmake.exe"
  $ninja  = "$NdkLink\build-tools\cmake\bin\ninja.exe"
  $opusSrc = "$libsDir\opus-1.5.2"
  New-Item -ItemType Directory -Force -Path $libsDir | Out-Null

  if (-not (Test-Path "$opusSrc\CMakeLists.txt")) {
    $tgz = "$libsDir\opus.tar.gz"
    Write-Host "   downloading opus source" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri "https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz" `
      -OutFile $tgz -TimeoutSec 300 -UseBasicParsing
    tar -xzf $tgz -C $libsDir
  }

  # CMAKE_MAKE_PROGRAM must be given explicitly: the bundled cmake does not find the
  # bundled ninja on its own.
  & $cmake -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" `
      -DCMAKE_TOOLCHAIN_FILE="$($NdkLink -replace '\\','/')/build/cmake/ohos.toolchain.cmake" `
      -DOHOS_ARCH=arm64-v8a -DCMAKE_BUILD_TYPE=Release `
      -DOPUS_BUILD_SHARED_LIBRARY=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_PROGRAMS=OFF `
      -DCMAKE_INSTALL_PREFIX="$opusPrefix" `
      -S "$opusSrc" -B "$libsDir\build-opus" | Out-Null
  & $cmake --build "$libsDir\build-opus" --target install | Out-Null
  if (-not (Test-Path "$opusPrefix\lib\libopus.a")) { throw "opus build incomplete" }
  Ok "opus installed"
}

# ---------------------------------------------------------------------------
Step "libsodium cross-compiled for ohos"
# Required, not optional: hbb_common -> sodiumoxide -> libsodium-sys, and libsodium is the
# protocol's crypto (secretbox/sign/base64) so it cannot be gated off. libsodium-sys has no
# prebuilt archive for this triple and falls back to its bundled mingw/win64 build, whose
# x86 objects lld cannot use; the module then fails to load on device with
# "sodium_base642bin: symbol not found".
$sodiumSrc = "$libsDir\libsodium-1.0.20"
if (Test-Path "$libsDir\prefix-sodium\lib\libsodium.a") {
  Skip "libsodium already built"
} else {
  if (-not (Test-Path "$sodiumSrc\src\libsodium\Makefile.am")) {
    New-Item -ItemType Directory -Force -Path $libsDir | Out-Null
    $stgz = "$libsDir\libsodium.tar.gz"
    Write-Host "   downloading libsodium source" -ForegroundColor DarkGray
    # The GitHub release asset is used rather than downloads.libsodium.org, which truncated
    # the archive in testing.
    Invoke-WebRequest -Uri "https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz" `
      -OutFile $stgz -TimeoutSec 300 -UseBasicParsing
    Remove-Item $sodiumSrc -Recurse -Force -ErrorAction SilentlyContinue
    tar -xzf $stgz -C $libsDir
    if (-not (Test-Path "$sodiumSrc\src\libsodium\Makefile.am")) { throw "libsodium extract failed" }
  }
  & pwsh -File (Join-Path $PSScriptRoot "build_libsodium_ohos.ps1") -NdkLink $NdkLink -WorkDir $libsDir
  if ($LASTEXITCODE -ne 0) { throw "libsodium build failed" }
}

# ---------------------------------------------------------------------------
Step "Stable junction for the cross-built libraries"
# .cargo/config.toml attaches libsodium by absolute path, so it needs a location that does
# not depend on the user profile name. Same reason the C:\ohos-ndk junction exists.
if (Test-Path "C:\ohos-libs") {
  Skip "C:\ohos-libs"
} else {
  New-Item -ItemType Junction -Path "C:\ohos-libs" -Target $libsDir | Out-Null
  Ok "C:\ohos-libs -> $libsDir"
}

# ---------------------------------------------------------------------------
Step "VCPKG_ROOT layout for opus"
# magnum-opus builds the path as $VCPKG_ROOT/installed/<arch>-<os>, so arm64-linux must
# exist and contain lib/ and include/.
$vcpkgLink = "$vcpkgRoot\installed\arm64-linux"
if (Test-Path $vcpkgLink) {
  Skip $vcpkgLink
} else {
  New-Item -ItemType Directory -Force -Path "$vcpkgRoot\installed" | Out-Null
  New-Item -ItemType Junction -Path $vcpkgLink -Target $opusPrefix | Out-Null
  Ok "$vcpkgLink -> $opusPrefix"
}

# ---------------------------------------------------------------------------
Step "Verifying by building the core"
& pwsh -File (Join-Path $PSScriptRoot "rust_ohos_build.ps1") -Check -Features flutter
if ($LASTEXITCODE -ne 0) { throw "core check failed; see output above" }

Write-Host ""
Write-Host "Toolchain ready. Next: pwsh -File flutter/ohos/build_bridge.ps1" -ForegroundColor Green
