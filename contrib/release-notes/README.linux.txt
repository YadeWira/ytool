ytool - Linux (x86-64 y x86)
Recreacion open-source de xtool (Razor12911). https://github.com/YadeWira/ytool
==================================================================================

ytool        el programa (precomp, decode, extract, erase, execute, find, replace, generate)
libpja.so    PJA 0.9.14: JPEG, JPEG-LS y JPEG 2000 (-mpja)
libbrunsli.so  brunsli: JPEG, alternativa a PJA (-mbrunsli)
libpreflate.so preflate: deflate de cualquier compresor (-mpreflate)
libzstd.so   zstd 1.6.0 (-mzstd)
libfast-lzma2.so  compresion final (-l#)
libFLAC.so   FLAC (-mflac)
libwavpack.so WavPack (-mwavpack)
osrep        OSREP 0.0.18 (MIT): dedup externa (-ddo)

libzstd.so va incluida a proposito: el .ytp guarda el nivel, no el stream, y cada
version de zstd comprime distinto en algunos niveles. ytool la carga antes que la del
sistema; si la borras, usa la de la distro y un .ytp puede no restaurarse en otra
maquina. Van dentro de ytool, por la misma razon: zlib 1.4 (-mzlib, -mpng), lz4
1.11.1 (-mlz4*), libdeflate 1.26 (-mlibdeflate), lzlib 1.16 (-mlzip) y LZO 2.10
(-mlzo1x, -mlzo1c, -mlzo2a).

No usa ninguna biblioteca de codecs del sistema: las que faltan arriba van dentro.

srep NO viene incluido (SREP 3.93a es "All rights reserved"). -dd1..-dd5 lo usan si
pones srep64 junto a ytool (builds: https://github.com/YadeWira/srep-builds), o su
libreria libsrep.so (3.97+), que se usa antes que el programa; sin ninguno,
ytool avisa y usa la dedup en memoria (-dd). -ddo usa OSREP, que viene incluido.

Uso (todas las opciones: ./ytool help precomp):
  ./ytool precomp -mzlib+zstd+pja entrada salida.ytp
  ./ytool decode salida.ytp restaurado
