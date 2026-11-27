ytool - Linux (x86-64 y x86)
Recreacion open-source de xtool (Razor12911). https://github.com/YadeWira/ytool
==================================================================================

ytool        el programa (precomp, decode, extract, erase, execute, find, replace, generate)
libpja.so    PJA 0.9.14: JPEG, JPEG-LS y JPEG 2000 (-mpja)
libbrunsli.so  brunsli: JPEG, alternativa a PJA (-mbrunsli)
libpreflate.so preflate: deflate de cualquier compresor (-mpreflate)
liblz4.so    lz4 1.11.1 (-mlz4, -mlz4hc, -mlz4f)
libzstd.so   zstd 1.6.0 (-mzstd)
libfast-lzma2.so  compresion final (-l#)
libdeflate.so libdeflate 1.26: deflate que zlib no reproduce (-mlibdeflate)
liblz.so     lzlib 1.16: miembros lzip, .lz (-mlzip)
osrep        OSREP 0.0.18 (MIT): dedup externa (-ddo)

liblz4.so y libzstd.so van incluidas a proposito: el .ytp guarda el nivel, no el
stream, y cada version de lz4/zstd comprime distinto en algunos niveles. ytool las
carga antes que las del sistema; si las borras, usa las de la distro y un .ytp puede
no restaurarse en otra maquina.

Del sistema: libz (hace falta para arrancar), y por dlopen liblzo2, libFLAC y
libwavpack. En el paquete x86 tienen que ser las de 32 bits (en Debian/Ubuntu sobre
un sistema de 64 bits: lib32z1; sin las otras de 32 bits, esos codecs quedan
desactivados, ytool help precomp los marca con *).

srep NO viene incluido (SREP 3.93a es "All rights reserved"). -dd1..-dd5 lo usan si
pones srep64 junto a ytool (builds: https://github.com/YadeWira/srep-builds), o su
libreria libsrep.so (3.97+), que se usa antes que el programa; sin ninguno,
ytool avisa y usa la dedup en memoria (-dd). -ddo usa OSREP, que viene incluido.

Uso (todas las opciones: ./ytool help precomp):
  ./ytool precomp -mzlib+zstd+pja entrada salida.ytp
  ./ytool decode salida.ytp restaurado
