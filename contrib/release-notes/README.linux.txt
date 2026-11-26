ytool (open-source recreation of xtool by Razor12911) - Linux x86-64 build
============================================================================
ytool: binario principal (precomp/decode/extract/erase/execute/find/replace/generate).
*.so: plugins de codecs (pja, preflate, fast-lzma2, brunsli, packmp3, packpng,
     liblz4, libzstd 1.6.0).
srep64 NO viene incluido. La deduplicacion externa (-dd#) necesita SREP 3.93a
        (Bulat Ziganshin, "All rights reserved": no se puede redistribuir). Si lo
        tienes, pon srep64 junto a este binario. Builds personales y sus scripts:
        https://github.com/YadeWira/srep-builds . La dedup en memoria (-dd) no lo necesita.

libpackpng.so es de https://github.com/YadeWira/packPNG (mismo autor): PNG/APNG/JNG
via preflate + WebP-lossless, ratio 45.7% vs el -mpng clasico (~100%, sin modelar
pixeles). Ver -mpackpng.

liblz4.so (lz4 1.11.1) va incluida a proposito, y ytool la carga antes que la
del sistema. Cada version de lz4 comprime distinto en varios niveles (entre 1.9.4
y 1.10.0 cambio LZ4HC_CLEVEL_MIN; 1.11 cambia el modo rapido y los niveles 1, 2 y
10-12). Como el .pmp guarda el nivel y no
el stream original, codificar con una version y restaurar con otra puede dar
salida incorrecta. Con la lib incluida eso deja de depender de la distro.
Si borras liblz4.so, ytool cae a la del sistema y volves a quedar expuesto.
Lo mismo vale para libzstd.so (zstd 1.6.0): sin ella -mzstd usa la libzstd de la
distro, y una distinta de 1.5.7/1.6.0 reproduce otros bytes.

Requiere en el sistema (via dlopen, comunes en la mayoria de distros):
  libz, liblzo2, libFLAC, libwavpack, liblzma, libstdc++

Uso:
  ./ytool precomp -mzlib+zstd input.bin output.pmp
  ./ytool precomp -mpackpng image.png output.pmp
  ./ytool decode output.pmp restored.bin

Repo: https://github.com/YadeWira/ytool
