# Cross-compile libsodium for HarmonyOS (aarch64-linux-ohos).
#
# Why this exists: hbb_common depends on sodiumoxide -> libsodium-sys, and libsodium is the
# protocol's crypto (secretbox, sign, base64). It cannot be feature-gated off. libsodium-sys
# 0.2.7 ships prebuilt archives only for desktop triples, and for an unknown target it falls
# back to its bundled Windows build -- the build output says so:
#
#     cargo:rustc-link-search=native=.../libsodium-sys-0.2.7/mingw/win64/
#
# Those objects are x86 (ssse3/avx2/avx512f), so lld cannot use them for aarch64. It reports
# "archive member ... is neither ET_REL nor LLVM bitcode" and leaves symbols like
# sodium_base642bin undefined. The module then fails to load on device with:
#
#     relocating failed: symbol not found. s=sodium_base642bin
#     [NMM] load module default/rustdesk_ohos failed
#
# libsodium publishes no cmake project and Windows here has no sh/make/perl, so autotools is
# not available. This script therefore compiles the sources directly, using the file list
# from libsodium's own src/libsodium/Makefile.am as the authority, and archives the result.
#
# Only the portable implementations are built -- no SIMD and no asm, matching the branches
# autotools selects for a non-x86 target (HAVE_AMD64_ASM and HAVE_AVX_ASM false). libsodium's
# per-algorithm dispatch files are written with #ifdef guards and fall back to the reference
# implementations, so omitting the SIMD variants is a supported configuration, not a
# degradation: crypto_aead/aes256gcm reports itself unavailable without hardware AES, exactly
# as it does on any target without AESNI.
#
# Usage:
#   pwsh -File flutter/ohos/build_libsodium_ohos.ps1
#
# Produces %USERPROFILE%\ohos-libs\prefix-sodium\lib\libsodium.a, which
# rust_ohos_build.ps1 points libsodium-sys at via SODIUM_LIB_DIR.

param(
  [string]$NdkLink = "C:\ohos-ndk",
  [string]$WorkDir = "$env:USERPROFILE\ohos-libs",
  [string]$Version = "1.0.20",
  # libsodium's own ABI version, from configure.ac (SODIUM_LIBRARY_VERSION_MAJOR/MINOR).
  [string]$AbiMajor = "26",
  [string]$AbiMinor = "2"
)

$ErrorActionPreference = "Stop"

$src  = Join-Path $WorkDir "libsodium-$Version"
$bld  = Join-Path $WorkDir "build-sodium"
$pre  = Join-Path $WorkDir "prefix-sodium"
$clang = Join-Path $NdkLink "llvm\bin\clang.exe"
$ar    = Join-Path $NdkLink "llvm\bin\llvm-ar.exe"
$sysroot = Join-Path $NdkLink "sysroot"

if (Test-Path "$pre\lib\libsodium.a") {
  Write-Host "libsodium already built at $pre" -ForegroundColor DarkGray
  exit 0
}

foreach ($tool in @($clang, $ar)) {
  if (-not (Test-Path $tool)) { throw "missing tool: $tool (is $NdkLink the OHOS NDK?)" }
}

if (-not (Test-Path "$src\src\libsodium\Makefile.am")) {
  throw "libsodium source not found at $src. See setup_ohos_toolchain.ps1 for the download step."
}

New-Item -ItemType Directory -Force -Path "$bld\obj", "$bld\include\sodium" | Out-Null

# ---------------------------------------------------------------------------
# Collect the source list from Makefile.am.
#
# The file wraps its lists over automake conditionals, so both the conditions and the
# if/else structure have to be evaluated. Getting this wrong is not a build error: a missing
# .c file simply leaves a symbol undefined, and the failure only appears on device as
# "relocating failed: symbol not found". That is exactly what happened with
# crypto_stream_salsa20_ref_implementation, which lives in the ELSE branch of
# `if HAVE_AMD64_ASM` -- a branch an x86 reading of the file skips but aarch64 needs.
#
# Parsing the real file rather than hardcoding a list keeps this correct across libsodium
# releases, so it is worth doing properly.
function Test-AutomakeCondition([string]$cond) {
  switch ($cond) {
    # aarch64 has native 128-bit integers, which selects the fe_51 ed25519 representation.
    'HAVE_TI_MODE'    { return $true }
    # Both are x86 assembly paths; their else branches carry the portable implementations.
    'HAVE_AMD64_ASM'  { return $false }
    'HAVE_AVX_ASM'    { return $false }
    '!HAVE_AMD64_ASM' { return $true }
    # Full library, not the trimmed MINIMAL build.
    '!MINIMAL'        { return $true }
    # Not WebAssembly.
    '!EMSCRIPTEN'     { return $true }
    default {
      Write-Host "   note: unhandled automake condition '$cond' treated as false" -ForegroundColor Yellow
      return $false
    }
  }
}

$makefile = Get-Content "$src\src\libsodium\Makefile.am"
$sources = New-Object System.Collections.Generic.List[string]

# librdrand_la_SOURCES is a separate archive, but `libsodium_la_LIBADD += librdrand.la`
# folds it into libsodium when not building for wasm, so its sources belong here too.
$wantedLists = 'libsodium_la_SOURCES', 'librdrand_la_SOURCES'

$inList = $false
$condStack = New-Object System.Collections.Generic.List[bool]

foreach ($line in $makefile) {
  $t = $line.TrimEnd()

  if ($t -match '^if\s+(.+)$') {
    $condStack.Add((Test-AutomakeCondition $Matches[1].Trim()))
    continue
  }
  if ($t -match '^else\s*$') {
    if ($condStack.Count -gt 0) { $condStack[$condStack.Count - 1] = -not $condStack[$condStack.Count - 1] }
    continue
  }
  if ($t -match '^endif\b') {
    if ($condStack.Count -gt 0) { $condStack.RemoveAt($condStack.Count - 1) }
    continue
  }

  if ($t -match '^([A-Za-z_][A-Za-z0-9_]*)\s*\+?=') {
    # Any assignment ends the previous list; only the ones we want start a new one.
    $inList = $wantedLists -contains $Matches[1]
    continue
  }

  if ($inList -and $t -match '^\s*(\S+\.c)\s*\\?\s*$') {
    $active = $true
    foreach ($b in $condStack) { if (-not $b) { $active = $false; break } }
    if ($active) { $sources.Add($Matches[1]) }
  }
}

if ($sources.Count -lt 50) {
  throw "parsed only $($sources.Count) sources from Makefile.am; the parser needs updating"
}

# Guard against the else-branch mistake that caused the salsa20 symbol failure: aarch64 must
# take the portable implementations, so these must be present.
foreach ($required in @(
  'crypto_stream/salsa20/ref/salsa20_ref.c',
  'randombytes/sysrandom/randombytes_sysrandom.c',
  'randombytes/internal/randombytes_internal_random.c'
)) {
  if (-not ($sources -contains $required)) {
    throw "expected source missing from the parse: $required"
  }
}

# Drop anything from an x86-only directory. These live in separate convenience libraries
# upstream, but guard anyway so a future upstream reshuffle cannot smuggle them in.
$archDirs = 'sse2', 'ssse3', 'sse41', 'avx2', 'avx512f', 'aesni', 'armcrypto', 'sandy2x', 'dolbeau', 'xmm6int'
$before = $sources.Count
$sources = $sources | Where-Object { $p = $_; -not ($archDirs | Where-Object { $p -match "(^|/)$_/" }) }
Write-Host "libsodium sources: $($sources.Count) (dropped $($before - $sources.Count) arch-specific)"

# ---------------------------------------------------------------------------
# version.h is generated by autotools from version.h.in; do the same substitution.
$versionIn = Get-Content "$src\src\libsodium\include\sodium\version.h.in" -Raw
$versionHeader = $versionIn.
  Replace('@VERSION@', $Version).
  Replace('@SODIUM_LIBRARY_VERSION_MAJOR@', $AbiMajor).
  Replace('@SODIUM_LIBRARY_VERSION_MINOR@', $AbiMinor).
  Replace('@SODIUM_LIBRARY_MINIMAL_DEF@', '')
Set-Content -Path "$bld\include\sodium\version.h" -Value $versionHeader -NoNewline

# ---------------------------------------------------------------------------
$targetArgs = @(
  "--target=aarch64-linux-ohos",
  "--sysroot=$sysroot",
  "-D__MUSL__",
  # aarch64 has native 128-bit integers, which selects the fe_51 field representation in
  # ed25519_ref10. autotools sets this via HAVE_TI_MODE.
  "-DHAVE_TI_MODE",
  "-DNATIVE_LITTLE_ENDIAN",
  "-O2", "-fPIC", "-std=c99",
  # libsodium's own sources include its headers unqualified ("core.h", not "sodium/core.h"),
  # so the include/sodium directories themselves must be on the path -- this is what
  # libsodium_la_CPPFLAGS does for the autotools build.
  "-I$bld\include\sodium",
  "-I$src\src\libsodium\include\sodium",
  "-I$src\src\libsodium\include\sodium\private",
  "-I$src\src\libsodium\include"
)

$i = 0
$failed = @()
foreach ($s in $sources) {
  $i++
  $obj = Join-Path $bld ("obj\{0:d3}_{1}" -f $i, ($s -replace '[\\/]', '_'))
  $obj = [System.IO.Path]::ChangeExtension($obj, '.o')
  $full = Join-Path "$src\src\libsodium" $s
  if (-not (Test-Path $full)) { $failed += "missing: $s"; continue }
  & $clang @targetArgs -c $full -o $obj 2>> "$bld\compile.log"
  if ($LASTEXITCODE -ne 0) { $failed += "compile failed: $s" }
}

if ($failed.Count -gt 0) {
  Write-Host "FAILED:" -ForegroundColor Red
  $failed | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
  Write-Host "see $bld\compile.log" -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Force -Path "$pre\lib", "$pre\include" | Out-Null
$objs = Get-ChildItem "$bld\obj" -Filter "*.o" | Select-Object -ExpandProperty FullName
& $ar rcs "$pre\lib\libsodium.a" @objs
if ($LASTEXITCODE -ne 0) { throw "ar failed" }

Copy-Item "$src\src\libsodium\include\sodium" "$pre\include\" -Recurse -Force
Copy-Item "$bld\include\sodium\version.h" "$pre\include\sodium\version.h" -Force

$mb = [math]::Round((Get-Item "$pre\lib\libsodium.a").Length / 1MB, 2)
Write-Host "libsodium.a ($mb MB) -> $pre\lib" -ForegroundColor Green

# The symbol that failed to resolve on device is the regression test for this whole exercise.
$hasSymbol = (& $NdkLink\llvm\bin\llvm-nm.exe --defined-only "$pre\lib\libsodium.a" 2>$null) -match 'T sodium_base642bin'
if ($hasSymbol) {
  Write-Host "verified: sodium_base642bin is defined in the archive" -ForegroundColor Green
} else {
  throw "sodium_base642bin is NOT in the archive; it would still fail to load on device"
}
