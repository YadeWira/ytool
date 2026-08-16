# Compila ytool en Windows (FPC/Lazarus win64). Correr desde la raiz del repo
# (fuente ya presente en C:\...\ytool) via PowerShell 7:
#   pwsh -NoProfile -File contrib\winbuild.ps1
# Ajustar $fpc si la instalacion de Lazarus/FPC esta en otra ruta.
#
# Sale con codigo != 0 si la compilacion falla o si no produjo un binario
# nuevo. Esto no es ceremonia: una version anterior de este script imprimia
# "EXIT=$LASTEXITCODE" como expresion suelta y salia 0 pase lo que pase, sin
# borrar el binario previo -- asi que una compilacion fallida dejaba el .exe
# de la semana pasada en su lugar y el script informaba exito. Ese binario
# viejo llego a un release publicado.
$ErrorActionPreference = "Stop"
$fpc = "C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe"

if (-not (Test-Path $fpc)) { Write-Error "no existe el compilador: $fpc"; exit 1 }
if (-not (Test-Path .\ytool.dpr)) { Write-Error "correr desde la raiz del repo (no se ve ytool.dpr)"; exit 1 }

# Borrar AMBAS salidas primero. Sin esto no hay forma de distinguir "compilo"
# de "quedo lo de antes", y ademas evita que el rename de mas abajo tenga que
# elegir entre dos archivos.
Remove-Item .\ytool, .\ytool.exe -ErrorAction SilentlyContinue

& $fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio `
  -Fuimports -Fusources -Fucontrib\mORMot -Fucontrib\LZ4Delphi -Fucontrib\ZSTD4Delphi `
  -Fucontrib\XXHASH4Delphi -Fucontrib\ParseExpression -Fucontrib\LZMADelphi `
  -oytool.exe ytool.dpr
if ($LASTEXITCODE -ne 0) { Write-Error "fpc fallo con codigo $LASTEXITCODE"; exit $LASTEXITCODE }

# FPC en Windows a veces ignora la extension del -o y deja el binario sin ella.
# El rename va condicionado a que ytool.exe NO exista: sin esa guarda, un
# archivo llamado "ytool" que no sea nuestra salida (por ejemplo el binario
# ELF de Linux, que se llama igual y viaja si el arbol se copia por scp)
# pisaria el .exe recien compilado.
if ((Test-Path .\ytool) -and (-not (Test-Path .\ytool.exe))) {
  Rename-Item .\ytool .\ytool.exe
}

if (-not (Test-Path .\ytool.exe)) { Write-Error "la compilacion no produjo ytool.exe"; exit 1 }

# El binario tiene que ser mas nuevo que la fuente. Atrapa el caso exacto que
# se nos escapo: compilador que "termina bien" pero deja el .exe de antes.
$exe = Get-Item .\ytool.exe
$src = Get-Item .\ytool.dpr
if ($exe.LastWriteTime -lt $src.LastWriteTime) {
  Write-Error "ytool.exe ($($exe.LastWriteTime)) es mas viejo que ytool.dpr ($($src.LastWriteTime)) -- binario rancio"
  exit 1
}

Write-Output "OK -> ytool.exe  $($exe.Length) bytes  $($exe.LastWriteTime)"
