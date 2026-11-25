ytool (open-source recreation of xtool by Razor12911) - Linux x86-64 build
============================================================================
ytool: binario principal (precomp/decode/extract/erase/execute/find/replace/generate).
*.so: plugins de codecs (packjpg, preflate, fast-lzma2, brunsli, packmp3, packpng).
srep64: deduplicacion externa (-dd#). Es Intensity/srep (github.com/Intensity/srep):
        SREP 3.93a beta, la implementacion de referencia (sin mantenimiento desde 2014),
        compilada con dos parches de asm inline que el upstream no trae: el clobber
        "rm"->"qm" del CRC32 en hashes.cpp y los operandos read-write de VMAC en vmac.c.
        Sin el segundo, el build de 32 bits falla su propio checksum en cruces de arq.

libpackpng.so es de https://github.com/YadeWira/packPNG (mismo autor): PNG/APNG/JNG
via preflate + WebP-lossless, ratio 45.7% vs el -mpng clasico (~100%, sin modelar
pixeles). Ver -mpackpng.

liblz4.so va incluida a proposito, y ytool la carga antes que la del sistema.
Entre lz4 1.9.4 y 1.10.0 cambio LZ4HC_CLEVEL_MIN (3 -> 2), asi que el nivel 2
comprime distinto segun la version instalada. Como el .pmp guarda el nivel y no
el stream original, codificar con una version y restaurar con otra puede dar
salida incorrecta. Con la lib incluida eso deja de depender de la distro.
Si borras liblz4.so, ytool cae a la del sistema y volves a quedar expuesto.

Requiere en el sistema (via dlopen, comunes en la mayoria de distros):
  libz, libzstd, liblzo2, libFLAC, libwavpack, liblzma, libstdc++

Uso:
  ./ytool precomp -mzlib+zstd input.bin output.pmp
  ./ytool precomp -mpackpng image.png output.pmp
  ./ytool decode output.pmp restored.bin

Repo: https://github.com/YadeWira/ytool
