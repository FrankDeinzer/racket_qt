# Windows-Gegenstueck zu behavior-matrix.sh (docs/COVERAGE.md, HACKING §81):
# examples/behavior-matrix-probe.rkt je Sektion nativ (win32) und mit PLT_QT=1 ausfuehren und die
# Protokolle diffen.  Jede Sektion ein eigener Prozess mit Timeout (Absturz/Haenger bleibt der Sektion
# zuordenbar).  Zeilen mit "...#px" (Pixelwerte) und "...#info" (nur Information) werden nicht verglichen;
# bekannte Abweichungen: tests/sweep/behavior-matrix-known.txt (gegen gtk triagiert -- ein Diff gegen
# win32 kann auch eine win32-Eigenart sein und ist einzeln zu bewerten).
# Aufruf: powershell -File tests/sweep/behavior-matrix.ps1 [sektion ...]   (ohne Argument: alle)
# Ausgabe: tests/sweep/out/behavior-matrix-<sektion>.{win32,qt}; Exit 1 bei Abweichung.
# Umgebung: RACKET (Default C:\Program Files\Racket\racket.exe), QT_BIN (Default C:\Qt\6.11.0\msvc2022_64\bin),
# TIMEOUT_S (Default 90).  Die Fenster erscheinen kurz auf dem Bildschirm.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Sections)
$ErrorActionPreference = 'Stop'
$root   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out    = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Force $out | Out-Null
$racket = if ($env:RACKET)     { $env:RACKET }     else { 'C:\Program Files\Racket\racket.exe' }
$qtBin  = if ($env:QT_BIN)     { $env:QT_BIN }     else { 'C:\Qt\6.11.0\msvc2022_64\bin' }
$tmo    = if ($env:TIMEOUT_S)  { [int]$env:TIMEOUT_S } else { 90 }
$known  = @(Get-Content (Join-Path $PSScriptRoot 'behavior-matrix-known.txt') | Where-Object { $_ })
$probe  = 'examples\behavior-matrix-probe.rkt'

if (-not $Sections) { $Sections = @(& $racket (Join-Path $root $probe) list | Where-Object { $_ }) }

function Run-Section($s, $mode) {
  $o = Join-Path $out "raw-$s.$mode.out"; $e = Join-Path $out "raw-$s.$mode.err"
  if ($mode -eq 'qt') { $env:PLT_QT = '1'; $env:PATH = "$qtBin;" + $env:PATH_ORIG } else { Remove-Item Env:PLT_QT -ErrorAction SilentlyContinue; $env:PATH = $env:PATH_ORIG }
  $p = Start-Process -FilePath $racket -ArgumentList @($probe, $s) -WorkingDirectory $root -NoNewWindow -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
  $null = $p.Handle  # Handle cachen, sonst ist ExitCode nach dem Ende $null
  if (-not $p.WaitForExit($tmo * 1000)) { $p.Kill(); $p.WaitForExit(); $rc = "TIMEOUT" } else { $p.WaitForExit(); $rc = $p.ExitCode }
  $lines = @(Get-Content $o, $e -ErrorAction SilentlyContinue) + "rc=$rc"
  $lines | Where-Object {
    $l = $_
    ($l -notmatch '#px') -and ($l -notmatch '#info') -and -not ($known | Where-Object { $l.Contains($_) })
  } | Set-Content (Join-Path $out "behavior-matrix-$s.$mode") -Encoding utf8
}

$env:PATH_ORIG = $env:PATH
$bad = 0
foreach ($s in $Sections) {
  Run-Section $s 'win32'; Run-Section $s 'qt'
  $a = Get-Content (Join-Path $out "behavior-matrix-$s.win32"); $b = Get-Content (Join-Path $out "behavior-matrix-$s.qt")
  $d = Compare-Object @($a) @($b)
  if (-not $d) { "OK    $s" }
  else { "DIFF  $s"; $d | ForEach-Object { '      ' + $(if ($_.SideIndicator -eq '<=') { 'win32> ' } else { 'qt   > ' }) + $_.InputObject }; $bad = 1 }
}
$env:PATH = $env:PATH_ORIG
exit $bad
