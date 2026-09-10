# Build/check the RustDesk Rust core for HarmonyOS (aarch64-unknown-linux-ohos).
#
# Usage (from the repository root):
#   pwsh -File flutter/ohos/rust_ohos_build.ps1 -Check -Package hbb_common
#   pwsh -File flutter/ohos/rust_ohos_build.ps1 -Release -Features flutter
#
# Requires:
#   - rustup toolchain stable-x86_64-pc-windows-gnu with target aarch64-unknown-linux-ohos
#   - DevEco Studio OHOS NDK (clang + sysroot)
#   - mingw-w64 binutils (dlltool) on PATH for the windows-gnu host
#   - prebuilt OpenSSL for ohos (ohos-rs/ohos-openssl prelude)

param(
  [switch]$Check,
  [switch]$Release,
  [string]$Package = "",
  [string]$Features = "flutter"
)

$ErrorActionPreference = "Stop"

$cargo    = "$env:USERPROFILE\.cargo\bin\cargo.exe"
$target   = "aarch64-unknown-linux-ohos"
# C:\ohos-ndk is a space-free junction to the DevEco OHOS native dir; CFLAGS cannot
# carry a --sysroot path containing spaces (clang would see it split into arguments).
$ndk      = "C:\ohos-ndk"
$llvm     = "$ndk\llvm\bin"
$sysroot  = "$ndk\sysroot"
$mingw    = "$env:USERPROFILE\mingw-tools\mingw64\bin"
$openssl  = "$env:USERPROFILE\ohos-openssl\ohos-openssl-main\prelude\arm64-v8a"

# mingw-w64 binutils (dlltool) is needed by the windows-gnu host toolchain, and its
# headers/libs are needed to link the host build scripts.
if (Test-Path $mingw) { $env:PATH = "$mingw;$env:PATH" }

# bindgen (kcp-sys and friends) needs libclang; the OHOS NDK ships one.
if (Test-Path "$llvm\libclang.dll") { $env:LIBCLANG_PATH = $llvm }

# ...and it needs the target sysroot on its own command line, otherwise it cannot even
# find stddef.h. libclang does not reliably discover its own resource directory (the one
# holding stddef.h/stdarg.h) when loaded through clang-sys, so pass it explicitly too
# rather than depending on discovery. bindgen reads the per-target variable first.
$clangRes = Get-ChildItem "$ndk\llvm\lib\clang" -Directory -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName
$bindgenArgs = "--target=aarch64-linux-ohos --sysroot=$sysroot"
if ($clangRes) { $bindgenArgs += " -resource-dir `"$clangRes`" -isystem `"$clangRes\include`"" }
# The clang driver turns --sysroot into -internal-externc-isystem entries for the libc
# headers, but libclang parses in-process and does not do that, so stdlib.h and friends
# are not found unless they are named here.
foreach ($inc in @("$sysroot\usr\include", "$sysroot\usr\include\aarch64-linux-ohos")) {
  if (Test-Path $inc) { $bindgenArgs += " -isystem `"$inc`"" }
}
$env:BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_ohos = $bindgenArgs
$env:BINDGEN_EXTRA_CLANG_ARGS = $bindgenArgs

# magnum-opus (Opus audio) locates libopus through VCPKG_ROOT. Its build.rs keys the
# pkg-config alternative on cfg(target_os = "linux"), and in a build script that is the
# HOST, not the target -- so on a Windows host that branch is not even compiled and the
# pkg-config feature cannot help. It wants $VCPKG_ROOT/installed/<arch>-<os>/{lib,include},
# so C:\ohos-vcpkg-root/installed/arm64-linux is a junction to the cross-built opus.
$env:VCPKG_ROOT = "C:\ohos-vcpkg-root"

# pkgconf is shipped from MSYS2 in the mingw bin directory added to PATH above; keep it
# available for any dependency that does consult pkg-config.
if (Test-Path "$mingw\pkgconf.exe") { $env:PKG_CONFIG = "$mingw\pkgconf.exe" }
$ohosLibs = "$env:USERPROFILE\ohos-libs\prefix"
if (Test-Path "$ohosLibs\lib\pkgconfig") { $env:PKG_CONFIG_PATH = "$ohosLibs\lib\pkgconfig" }
$env:PKG_CONFIG_ALLOW_CROSS = "1"

# C/C++ cross compiler + archiver for the ohos target (used by build scripts).
$env:CC_aarch64_unknown_linux_ohos  = "$llvm\clang.exe"
$env:CXX_aarch64_unknown_linux_ohos = "$llvm\clang++.exe"
$env:AR_aarch64_unknown_linux_ohos  = "$llvm\llvm-ar.exe"
$env:CFLAGS_aarch64_unknown_linux_ohos   = "--target=aarch64-linux-ohos --sysroot=$sysroot -D__MUSL__"
$env:CXXFLAGS_aarch64_unknown_linux_ohos = "--target=aarch64-linux-ohos --sysroot=$sysroot -D__MUSL__"

# Prebuilt OpenSSL for ohos (openssl-sys looks up <TRIPLE>_OPENSSL_DIR).
if (Test-Path $openssl) {
  $env:AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR = $openssl
}

$cargoArgs = @()
if ($Check)   { $cargoArgs += "check" } else { $cargoArgs += "build" }
if ($Release) { $cargoArgs += "--release" }
$cargoArgs += @("--target", $target, "--lib")
if ($Package) { $cargoArgs += @("-p", $Package) }
if ($Features) { $cargoArgs += @("--features", $Features) }

Write-Host "cargo $($cargoArgs -join ' ')" -ForegroundColor Cyan
& $cargo @cargoArgs
exit $LASTEXITCODE
