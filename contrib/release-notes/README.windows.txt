ytool - Windows (x64 y x86)
Recreacion open-source de xtool (Razor12911). https://github.com/YadeWira/ytool
==================================================================================

ytool.exe            el programa (precomp, decode, extract, erase, execute, find, replace, generate)
pja.dll              PJA 0.9.14: JPEG, JPEG-LS y JPEG 2000 (-mpja)
brunsli.dll          brunsli: JPEG, alternativa a PJA (-mbrunsli)
preflate_dll.dll     preflate: deflate de cualquier compresor (-mpreflate)
liblz4.dll           lz4 1.11.1 (-mlz4, -mlz4hc, -mlz4f)
libzstd.dll          zstd 1.6.0 (-mzstd)
lzo2.dll             LZO (-mlzo1x, -mlzo1c, -mlzo2a)
libFLAC_dynamic.dll  FLAC (-mflac)
wavpackdll.dll       WavPack (-mwavpack)
fast-lzma2.dll       compresion final (-l#)
zlib1.dll            zlib 1.4, necesaria para arrancar

Sin una DLL, su codec no hace nada: guarda los streams tal cual, sin error.
Las DLL solo importan DLL del sistema (KERNEL32, msvcrt, y user32/oleaut32 en pja).

x86 (32 bits): un .lz4 en modo rapido con bloques enlazados, escrito por un lz4 de
64 bits, no se puede reproducir en 32 bits (lz4 usa otro hash segun el tamano de
palabra). Al comprimir en x86 se guarda tal cual; y un .pmp hecho en 64 bits que
contiene uno de esos streams no se decodifica en x86: sale con error (exit 1) y no
escribe nada, nunca datos incorrectos. Para mover archivos entre maquinas, usa x64.

srep NO viene incluido (SREP 3.93a es "All rights reserved"). -dd1..-dd5 lo usan si
pones srep.exe junto a ytool.exe (builds: https://github.com/YadeWira/srep-builds);
sin el, ytool avisa y usa la dedup en memoria (-dd).
Oodle tampoco: es propietario; si tienes oo2core/oo2ext, ponla junto a ytool.exe.

Uso:
  ytool.exe precomp -mzlib+zstd+pja entrada salida.pmp
  ytool.exe decode salida.pmp restaurado
