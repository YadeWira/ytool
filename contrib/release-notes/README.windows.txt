ytool - Windows (x64 y x86), desde Windows 7
Recreacion open-source de xtool (Razor12911). https://github.com/YadeWira/ytool
==================================================================================

ytool.exe            el programa (precomp, decode, extract, erase, execute, find, replace, generate)
                     van dentro: zlib 1.4 (-mzlib, -mpng), lz4 1.11.1 (-mlz4*),
                     libdeflate 1.26 (-mlibdeflate) y lzlib 1.16 (-mlzip)
pja.dll              PJA 0.9.14: JPEG, JPEG-LS y JPEG 2000 (-mpja)
brunsli.dll          brunsli: JPEG, alternativa a PJA (-mbrunsli)
preflate_dll.dll     preflate: deflate de cualquier compresor (-mpreflate)
libzstd.dll          zstd 1.6.0 (-mzstd)
lzo2.dll             LZO (-mlzo1x, -mlzo1c, -mlzo2a)
libFLAC_dynamic.dll  FLAC (-mflac)
wavpackdll.dll       WavPack (-mwavpack)
fast-lzma2.dll       compresion final (-l#)
osrep.exe            OSREP 0.0.18 (MIT): dedup externa (-ddo)

Sin una DLL, su codec no hace nada: guarda los streams tal cual, sin error.
Las DLL solo importan DLL del sistema (KERNEL32, msvcrt, y user32/oleaut32 en pja).

x86 y x64 escriben los mismos bytes: un .ytp hecho en una se decodifica en la otra.

srep NO viene incluido (SREP 3.93a es "All rights reserved"). -dd1..-dd5 lo usan si
pones srep.exe junto a ytool.exe (builds: https://github.com/YadeWira/srep-builds),
o su libreria srep.dll (3.97+), que se usa antes que el programa; sin ninguno, ytool avisa y usa la dedup en memoria (-dd). -ddo usa OSREP, que viene incluido.
Oodle tampoco: es propietario; si tienes oo2core/oo2ext, ponla junto a ytool.exe.

Uso (todas las opciones: ytool.exe help precomp):
  ytool.exe precomp -mzlib+zstd+pja entrada salida.ytp
  ytool.exe decode salida.ytp restaurado
