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
$fpc = "C:\fpc-win32\bin\i386-win32\fpc.exe"
& $fpc -Mdelphi -Sg -O2 -dABSOLUTEPASCAL -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio `
  -Fuimports -Fusources -Fucontrib\mORMot -Fucontrib\LZ4Delphi -Fucontrib\ZSTD4Delphi `
  -Fucontrib\XXHASH4Delphi -Fucontrib\ParseExpression -Fucontrib\LZMADelphi -Fucontrib\WinLibcShim `
  -oytool-x86.exe ytool.dpr
"EXIT=$LASTEXITCODE"
# FPC en Windows a veces ignora la extension del -o y deja el binario sin ella.
if (Test-Path .\ytool-x86) {
  Rename-Item .\ytool-x86 .\ytool-x86.exe -Force
}
