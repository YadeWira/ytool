# Compila ytool en Windows (FPC/Lazarus win64). Correr desde la raiz del repo
# (fuente ya presente en C:\...\ytool) via PowerShell 7:
#   pwsh -NoProfile -File contrib\winbuild.ps1
# Ajustar $fpc si la instalacion de Lazarus/FPC esta en otra ruta.
$fpc = "C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe"
& $fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio `
  -Fuimports -Fusources -Fucontrib\mORMot -Fucontrib\LZ4Delphi -Fucontrib\ZSTD4Delphi `
  -Fucontrib\XXHASH4Delphi -Fucontrib\ParseExpression -Fucontrib\LZMADelphi `
  -oytool.exe ytool.dpr
"EXIT=$LASTEXITCODE"
# FPC en Windows a veces ignora la extension del -o y deja el binario sin ella.
if (Test-Path .\ytool) {
  Rename-Item .\ytool .\ytool.exe -Force
}
