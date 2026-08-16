# Compila ytool en Windows para i386-win32 (32-bit, Win7 SP1 x86 target).
# Correr desde la raiz del repo via PowerShell 7:
#   pwsh -NoProfile -File contrib\winbuild-x86.ps1
#
# Requiere un FPC 3.2.2 nativo i386-win32 aparte del win64 de Lazarus (no
# existe un paquete "cross" oficial en la direccion win64->win32 para esta
# version): instalar el standalone fpc-3.2.2.i386-win32.exe de sourceforge
# en una ruta separada (ej. C:\fpc-win32), independiente de C:\lazarus\fpc.
# Ajustar $fpc si quedo en otro lado.
#
# -dABSOLUTEPASCAL: evita que contrib/mORMot/SynCrypto.pas intente linkear
# static\i386-win32\sha512-x86.o (el unico .obj disponible es un objeto
# Delphi/OMF legado, incompatible con el linker de FPC -- "Illegal COFF
# Magic"); con este define, SynCrypto usa su fallback SHA512 puro Pascal.
#
# contrib\WinLibcShim provee memset/memcpy/malloc/etc y los helpers de
# aritmetica de 64-bit (__udivdi3 etc) que el RTL de FPC no trae en i386 pero
# que los objetos C de zstd/xxhash/lz4 llaman internamente -- ver los
# comentarios de ese unit y de build-native-windows-x86.sh para el detalle.
#
# Sale con codigo != 0 si la compilacion falla o si no produjo un binario
# nuevo -- ver winbuild.ps1 para por que eso importa (un binario rancio de
# este mismo mecanismo llego a un release publicado).
$ErrorActionPreference = "Stop"
$fpc = "C:\fpc-win32\bin\i386-win32\fpc.exe"

if (-not (Test-Path $fpc)) { Write-Error "no existe el compilador: $fpc"; exit 1 }
if (-not (Test-Path .\ytool.dpr)) { Write-Error "correr desde la raiz del repo (no se ve ytool.dpr)"; exit 1 }

Remove-Item .\ytool-x86, .\ytool-x86.exe -ErrorAction SilentlyContinue

& $fpc -Mdelphi -Sg -O2 -dABSOLUTEPASCAL -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio `
  -Fuimports -Fusources -Fucontrib\mORMot -Fucontrib\LZ4Delphi -Fucontrib\ZSTD4Delphi `
  -Fucontrib\XXHASH4Delphi -Fucontrib\ParseExpression -Fucontrib\LZMADelphi -Fucontrib\WinLibcShim `
  -oytool-x86.exe ytool.dpr
if ($LASTEXITCODE -ne 0) { Write-Error "fpc fallo con codigo $LASTEXITCODE"; exit $LASTEXITCODE }

# FPC en Windows a veces ignora la extension del -o y deja el binario sin ella.
if ((Test-Path .\ytool-x86) -and (-not (Test-Path .\ytool-x86.exe))) {
  Rename-Item .\ytool-x86 .\ytool-x86.exe
}

if (-not (Test-Path .\ytool-x86.exe)) { Write-Error "la compilacion no produjo ytool-x86.exe"; exit 1 }

$exe = Get-Item .\ytool-x86.exe
$src = Get-Item .\ytool.dpr
if ($exe.LastWriteTime -lt $src.LastWriteTime) {
  Write-Error "ytool-x86.exe ($($exe.LastWriteTime)) es mas viejo que ytool.dpr ($($src.LastWriteTime)) -- binario rancio"
  exit 1
}

Write-Output "OK -> ytool-x86.exe  $($exe.Length) bytes  $($exe.LastWriteTime)"
