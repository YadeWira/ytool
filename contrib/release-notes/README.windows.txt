ytool - Windows x86-64 build (open-source recreation of xtool by Razor12911)
=============================================================================
ytool.exe: binario principal (precomp/decode/extract/erase/execute/find/replace/generate).
srep.exe NO viene incluido. La deduplicacion externa (-dd<N>) necesita SREP 3.93a
          (Bulat Ziganshin, "All rights reserved": no se puede redistribuir). Si lo
          tienes, pon srep.exe junto a ytool.exe. Builds personales y sus scripts:
          https://github.com/YadeWira/srep-builds . La dedup en memoria (-dd) no lo necesita.

DLLs incluidas (todas cross-compiladas con mingw-w64 desde fuente abierta,
ver contrib/build-plugins-windows.sh):
  zlib1.dll            - zlib 1.4 (unidad ZLib de FPC)
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
  libzstd.dll          - zstd 1.6.0 (necesaria para -mzstd)

lz4 y zstd estan de las dos formas: objetos nativos dentro de ytool.exe para usos
internos, y liblz4.dll / libzstd.dll para los codecs -mlz4* y -mzstd. Sin esas DLL
esos codecs quedan MUERTOS -- procesan 0 streams y el .pmp sale mas grande que la
entrada, sin ningun error.

Limitacion del build x86 (32-bit) con -mlz4*: un .lz4 comprimido en MODO RAPIDO
(el default del CLI, sin -N) por un lz4 de 64 bits no se puede reproducir desde
32 bits, salvo cuando usa bloques de 64KB independientes. lz4 elige un hash
distinto segun el tamano de palabra (lz4.c:808), asi que el match finder del
camino rapido emite otros bytes. Esos streams se guardan literales: el
round-trip sigue siendo bit-exacto, solo comprime menos. Los niveles 3..12
(camino HC) no estan afectados y enganchan igual en x86 y x64. Medido sobre una
matriz de tamano de bloque x nivel x dependencia de bloques en Windows real.

La version de lz4 esta pinneada a proposito (1.11.1). Cada version comprime
distinto en varios niveles (1.11 cambia el modo rapido y los niveles 1, 2 y 10-12
respecto de 1.10); como el .pmp guarda el nivel y no el stream original, mezclar
versiones entre codificar y restaurar puede dar salida incorrecta. Un .lz4 escrito
por lz4 1.10 en modo rapido (-1, el default del CLI) o en -12 se guarda literal.

NO incluido: jojpeg (sin fuente abierta conocida), oodle (propietario, requiere que
el usuario aporte su propia oo2core/oo2ext DLL).

Verificado: round-trip bit-exacto en la VM Windows para CADA codec de esta lista
(packjpg, brunsli, packmp3, flac, wavpack, lzo1x, preflate, fast-lzma2 final,
dedup en memoria -dd, reassign -r, packpng).

Uso:
  ytool.exe precomp -mzlib+zstd input.bin output.pmp
  ytool.exe precomp -mpackpng image.png output.pmp
  ytool.exe precomp -mzlib -dd1 input.bin output.pmp   (dedup externo, requiere tu srep.exe)
  ytool.exe decode output.pmp restored.bin

Repo: https://github.com/YadeWira/ytool
