ytool - Windows x86-64 build (open-source recreation of xtool by Razor12911)
=============================================================================
ytool.exe: binario principal (precomp/decode/extract/erase/execute/find/replace/generate).
srep.exe: helper de deduplicacion externa (-dd<N>), invocado por ytool.exe como proceso hijo.
          Es Intensity/srep (github.com/Intensity/srep) SREP 3.93a beta, la implementacion
          de referencia. Compilado con dos parches que el upstream no trae: el clobber
          "rm"->"qm" del CRC32 en hashes.cpp (en i386 el "rm" original ni siquiera compila)
          y los operandos read-write de VMAC en vmac.c, que arreglan un miscompile real de
          GCC/strict-aliasing en el fallback de 128 bits que rompia el checksum interno
          cross-arquitectura. El backend de threading Win32 (contrib/srep-win32/) tambien es
          nuestro: el fork upstream solo conservo la mitad Unix.
          Ver la pagina de Known Issues & Limitations del wiki.

DLLs incluidas (todas cross-compiladas con mingw-w64 desde fuente abierta,
ver contrib/build-plugins-windows.sh):
  zlib1.dll            - zlib (unidad ZLib de FPC)
  lzo2.dll             - LZO (Oberhumer, lzo1x/lzo1c/lzo2a)
  packjpg_dll.dll      - packJPG (JPEG)
  brunsli.dll          - brunsli (JPEG, alternativa a packjpg)
  packmp3_dll.dll      - packMP3 (MP3)
  libFLAC_dynamic.dll  - FLAC (WAV lossless)
  wavpackdll.dll       - WavPack (WAV lossless, alternativa a FLAC)
  preflate_dll.dll     - preflate (mejora la reconstruccion de deflate)
  fast-lzma2.dll       - compresor final interno (-l#)
  packpng.dll          - packPNG (PNG/APNG/JNG, preflate + WebP-lossless), de
                          https://github.com/YadeWira/packPNG (mismo autor);
                          ratio 45.7% vs el -mpng clasico (~100%, no modela pixeles)

  liblz4.dll           - lz4 (necesaria para -mlz4 / -mlz4hc / -mlz4f)

zstd va compilado DENTRO de ytool.exe (objetos nativos, sin DLL). lz4 esta de las
dos formas: objetos nativos para el cache interno de prefetch (-p#), y liblz4.dll
para los codecs -mlz4*. Sin esa DLL esos tres codecs quedan MUERTOS -- procesan 0
streams y el .pmp sale mas grande que la entrada, sin ningun error.

Limitacion del build x86 (32-bit) con -mlz4*: un .lz4 comprimido en MODO RAPIDO
(el default del CLI, sin -N) por un lz4 de 64 bits no se puede reproducir desde
32 bits, salvo cuando usa bloques de 64KB independientes. lz4 elige un hash
distinto segun el tamano de palabra (lz4.c:808), asi que el match finder del
camino rapido emite otros bytes. Esos streams se guardan literales: el
round-trip sigue siendo bit-exacto, solo comprime menos. Los niveles 3..12
(camino HC) no estan afectados y enganchan igual en x86 y x64. Medido sobre una
matriz de tamano de bloque x nivel x dependencia de bloques en Windows real.

La version de lz4 esta pinneada a proposito (commit 0774d05, 1.10.0). Entre 1.9.4
y 1.10.0 cambio LZ4HC_CLEVEL_MIN (3 -> 2), asi que el nivel 2 comprime distinto
segun la version; como el .pmp guarda el nivel y no el stream original, mezclar
versiones entre codificar y restaurar puede dar salida incorrecta.

NO incluido: jojpeg (sin fuente abierta conocida), oodle (propietario, requiere que
el usuario aporte su propia oo2core/oo2ext DLL).

Verificado: round-trip bit-exacto en la VM Windows para CADA codec de esta lista
(packjpg, brunsli, packmp3, flac, wavpack, lzo1x, preflate, fast-lzma2 final,
dedup en memoria -dd, dedup EXTERNO -dd<N> via srep.exe, reassign -r, packpng).

Uso:
  ytool.exe precomp -mzlib+zstd input.bin output.pmp
  ytool.exe precomp -mpackpng image.png output.pmp
  ytool.exe precomp -mzlib -dd1 input.bin output.pmp   (dedup externo, srep.exe)
  ytool.exe decode output.pmp restored.bin

Repo: https://github.com/YadeWira/ytool
