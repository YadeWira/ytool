ytool - Linux x86-64
Recreacion open-source de xtool (Razor12911). https://github.com/YadeWira/ytool
==================================================================================

ytool        el programa (precomp, decode, extract, erase, execute, find, replace, generate)
libpja.so    PJA 0.9.14: JPEG, JPEG-LS y JPEG 2000 (-mpja)
libbrunsli.so  brunsli: JPEG, alternativa a PJA (-mbrunsli)
libpreflate.so preflate: deflate de cualquier compresor (-mpreflate)
liblz4.so    lz4 1.11.1 (-mlz4, -mlz4hc, -mlz4f)
libzstd.so   zstd 1.6.0 (-mzstd)
libfast-lzma2.so  compresion final (-l#)

liblz4.so y libzstd.so van incluidas a proposito: el .pmp guarda el nivel, no el
stream, y cada version de lz4/zstd comprime distinto en algunos niveles. ytool las
carga antes que las del sistema; si las borras, usa las de la distro y un .pmp puede
no restaurarse en otra maquina.

Del sistema (dlopen): libz, liblzo2, libFLAC, libwavpack.

srep NO viene incluido (SREP 3.93a es "All rights reserved"). -dd1..-dd5 lo usan si
pones srep64 junto a ytool (builds: https://github.com/YadeWira/srep-builds); sin el,
ytool avisa y usa la dedup en memoria (-dd).

Uso:
  ./ytool precomp -mzlib+zstd+pja entrada salida.pmp
  ./ytool decode salida.pmp restaurado
