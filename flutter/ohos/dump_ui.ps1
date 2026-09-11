# Dump the on-device UI tree and list text nodes with bounds, optionally tapping a control.
#
# ArkTS exceptions do not appear in hilog, and layout problems are only visible as geometry,
# so reading the tree is the main way to verify the UI on device. Kept as a script because
# every ad-hoc version of this has had the same two problems: ad-hoc regexes over the JSON
# break whenever the attribute order changes, and PowerShell's $script: scoping inside a
# nested function silently loses results.
#
# Usage:
#   pwsh -File flutter/ohos/dump_ui.ps1                     # list all text nodes
#   pwsh -File flutter/ohos/dump_ui.ps1 -Filter "连接"      # only matching nodes
#   pwsh -File flutter/ohos/dump_ui.ps1 -Tap "连接"         # tap the first node with this text
#   pwsh -File flutter/ohos/dump_ui.ps1 -Types TextInput    # only these component types
#   pwsh -File flutter/ohos/dump_ui.ps1 -Bundle <name>      # only that app's window
#
# Use -Bundle when checking our own layout. The default dump merges every window, so a system
# panel or status-bar overlay can appear as if it were part of the app -- which is how a stray
# "设置" in the status bar band was briefly mistaken for our content bleeding upward.

param(
  [string]$Filter = "",
  [string]$Tap = "",
  [string]$Types = "",
  [string]$Bundle = "",
  [switch]$Raw
)

$hdc = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
$remote = "/data/local/tmp/dump_ui.json"
$local = Join-Path $env:TEMP "dump_ui.json"

function Get-Nodes {
  $bundleArg = if ($Bundle) { " -b $Bundle" } else { "" }
  & $hdc shell "uitest dumpLayout -p $remote$bundleArg" 2>&1 | Out-Null
  Remove-Item $local -ErrorAction SilentlyContinue
  & $hdc file recv $remote $local 2>&1 | Out-Null
  if (-not (Test-Path $local)) { throw "no layout dump produced" }

  $root = Get-Content $local -Raw | ConvertFrom-Json
  $out = New-Object System.Collections.ArrayList
  $stack = New-Object System.Collections.Stack
  $stack.Push($root)
  while ($stack.Count -gt 0) {
    $n = $stack.Pop()
    $a = $n.attributes
    if ($a) {
      $text = "$($a.text)"
      $type = "$($a.type)"
      $bounds = "$($a.bounds)"
      if (($text -and $text.Trim() -ne "") -or $Types) {
        [void]$out.Add([pscustomobject]@{ Text = $text; Type = $type; Bounds = $bounds })
      }
    }
    if ($n.children) { foreach ($c in $n.children) { $stack.Push($c) } }
  }
  return $out
}

function Get-Center([string]$bounds) {
  if ($bounds -match '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
    return @(
      [int](([int]$Matches[1] + [int]$Matches[3]) / 2),
      [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    )
  }
  return $null
}

$nodes = Get-Nodes
if ($Raw) { $nodes | Format-Table -AutoSize | Out-String -Width 200; exit 0 }

if ($Tap) {
  $target = $nodes | Where-Object { $_.Text -eq $Tap } | Select-Object -First 1
  if (-not $target) { Write-Host "no node with text '$Tap'" -ForegroundColor Red; exit 1 }
  $c = Get-Center $target.Bounds
  if (-not $c) { Write-Host "unparsable bounds: $($target.Bounds)" -ForegroundColor Red; exit 1 }
  Write-Host "tapping '$Tap' at $($c[0]),$($c[1])  [$($target.Bounds)]" -ForegroundColor Cyan
  & $hdc shell "uitest uiInput click $($c[0]) $($c[1])" 2>&1 | Select-Object -First 1
  exit 0
}

$shown = $nodes
if ($Filter)   { $shown = $shown | Where-Object { $_.Text -match $Filter } }
if ($Types)    { $shown = $shown | Where-Object { $_.Type -match $Types } }
$shown | ForEach-Object { "{0,-46} {1,-14} {2}" -f $_.Text, $_.Type, $_.Bounds }
