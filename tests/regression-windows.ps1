# ytool Windows regression suite: verifies bit-exact REVERSIBILITY
# (decode(precomp(x))==x) for a real Windows build (win64 or win32, run
# directly or under WOW64), with every plugin DLL actually loaded -- the
# PowerShell sibling of tests/regression.sh (which only covers Linux).
#
# Unlike regression.sh, this doesn't build ytool itself -- point it at an
# already-built .exe (and its directory, which must already have whatever
# plugin DLLs/zlib1.dll/osrep.exe are meant to be tested). Packaging those is
# contrib/build-plugins-windows.sh / build-plugins-windows-x86.sh's job.
#
# Usage:
#   pwsh -File tests\regression-windows.ps1 -Exe C:\path\to\ytool.exe
#   pwsh -File tests\regression-windows.ps1 -Exe C:\path\to\ytool.exe -CorpusDir C:\path\to\corpus
#
# Cross-architecture mode (encode with one build, decode with another --
# this is exactly what caught the -mflac cross-arch bug during the i386-win32
# port; keep exercising it whenever both builds are available):
#   pwsh -File tests\regression-windows.ps1 -Exe C:\path\to\ytool64.exe -DecodeExe C:\path\to\ytool86.exe
#
# CorpusDir: if omitted, tries `python3 tests\gen_corpus.py <tmp>` (works if
# Python happens to be on the box); if that's not available either, point
# -CorpusDir at a directory populated by hand (e.g. scp'd over from a Linux
# box that already ran `python3 tests/gen_corpus.py`, plus tests/lzo_gen.c's
# output for -mlzo1x if you want that codec covered -- see gen_corpus's own
# comments for exactly which optional files need which tool).
#
# Exits with a non-zero code if any round-trip is not bit-exact.

param(
  [Parameter(Mandatory=$true)][string]$Exe,
  [string]$DecodeExe = "",
  [string]$CorpusDir = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Exe)) {
  Write-Host "binary does not exist: $Exe"
  exit 3
}
$EncodeExe = $Exe
if ($DecodeExe -eq "") { $DecodeExe = $Exe }
if (-not (Test-Path $DecodeExe)) {
  Write-Host "decode binary does not exist: $DecodeExe"
  exit 3
}

$Work = Join-Path $env:TEMP ("ytool-regression-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Work | Out-Null
try {
  if ($CorpusDir -eq "") {
    $CorpusDir = Join-Path $Work "corpus"
    New-Item -ItemType Directory -Path $CorpusDir | Out-Null
    # Note: on a stock Windows install, `python3`/`python` often resolve on
    # PATH to the Microsoft Store app-execution-alias stub, not a real
    # interpreter -- it exits non-zero with "Python was not found; run
    # without arguments to install from the Microsoft Store...". Treat any
    # failure the same as "not found" rather than a hard error, since the
    # -CorpusDir fallback below is the real path most Windows boxes need.
    $py = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
    $pyWorks = $false
    if ($py) {
      & $py.Path --version *> $null
      $pyWorks = ($LASTEXITCODE -eq 0)
    }
    if ($pyWorks) {
      & $py.Path (Join-Path $PSScriptRoot "gen_corpus.py") $CorpusDir
      if ($LASTEXITCODE -ne 0) { Write-Host "gen_corpus.py FAILED"; exit 3 }
    } else {
      Write-Host "No working python3/python found and -CorpusDir not given -- nothing to test."
      Write-Host "Generate a corpus with 'python3 tests/gen_corpus.py <dir>' on any machine"
      Write-Host "with Python, copy it here, and pass -CorpusDir <dir>."
      exit 3
    }
  } elseif (-not (Test-Path $CorpusDir)) {
    Write-Host "CorpusDir does not exist: $CorpusDir"
    exit 3
  }

  # Same METHODS matrix as tests/regression.sh -- see that script's own
  # comments for what each one exercises and why some degrade gracefully to
  # "0 streams, trivially reversible" when an optional file/tool is missing.
  $Methods = @(
    "", "-mzlib", "-mzlib+zstd", "-mzlib -dd", "-mzlib -dd1", "-mzlib -r zstd",
    "-mzlib -r xor", "-mzlib -r aes", "-mzlib -r rc4", "-mlzo1x", "-mwavpack",
    "-mflac", "-mpng", "-mpackpng", "-mpreflate", "-mreflate", "-mlz4f",
    "-mpackjpg", "-mbrunsli", "-mpackmp3", "-mlzma"
  )

  $pass = 0; $fail = 0
  "{0,-26} {1,-14} {2,10} {3,10} {4,8}  {5}" -f "FILE", "METHOD", "IN", "PMP", "RATIO", "RESULT"
  Get-ChildItem $CorpusDir -File | ForEach-Object {
    $f = $_.FullName
    $bn = $_.Name
    $insz = $_.Length
    foreach ($m in $Methods) {
      $pmp = Join-Path $Work "out.pmp"
      $outf = Join-Path $Work "out.bin"
      Remove-Item $pmp, $outf -ErrorAction SilentlyContinue
      $mArgs = if ($m -eq "") { @() } else { $m -split " " }
      # PowerShell native-command quirk, confirmed empirically: splatting an
      # array combined with EXTRA bare positional arguments in the same call
      # (`& $exe @mArgs $f $pmp`) silently drops/mangles them for some array
      # lengths -- it only reliably works when the splatted array is the
      # WHOLE argument list. Build one combined array instead of splatting
      # $mArgs alongside bare $f/$pmp.
      $precompArgs = @("precomp") + $mArgs + @($f, $pmp)
      & $EncodeExe @precompArgs *> $null
      & $DecodeExe decode $pmp $outf *> $null
      $pmpsz = if (Test-Path $pmp) { (Get-Item $pmp).Length } else { 0 }
      $same = $false
      if (Test-Path $outf) {
        $h1 = (Get-FileHash $f -Algorithm SHA256).Hash
        $h2 = (Get-FileHash $outf -Algorithm SHA256).Hash
        $same = ($h1 -eq $h2)
      }
      if ($same) { $res = "OK"; $pass++ } else { $res = "*** FAIL ***"; $fail++ }
      $ratio = if ($insz -gt 0 -and $pmpsz -gt 0) { "{0:N3}" -f ($pmpsz / $insz) } else { "-" }
      $label = if ($m -eq "") { "<literal>" } else { $m }
      "{0,-26} {1,-14} {2,10} {3,10} {4,8}  {5}" -f $bn, $label, $insz, $pmpsz, $ratio, $res
    }
  }

  Write-Host "-- summary: $pass OK, $fail FAIL --"
  if ($fail -eq 0) {
    Write-Host "REGRESSION: PASS (bit-exact reversibility across the corpus)"
    exit 0
  } else {
    Write-Host "REGRESSION: FAIL ($fail non-reversible round-trips)"
    exit 1
  }
} finally {
  Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}
