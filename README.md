# ytool

Open-source recreation of **xtool**, the data precompressor by [Razor12911](https://github.com/Razor12911),
in Free Pascal, for **Linux and Windows** (x64 and x86).

A precompressor finds the compressed streams inside a file (deflate, JPEG, zstd, lz4…), unpacks them, and
stores them in a form a general compressor handles better. `decode` rebuilds the original **byte for byte**:
`decode(precomp(x)) == x` is the one rule nothing may break, so a stream ytool cannot rebuild exactly is
stored as it is.

xtool's source stopped at 0.7.9 (MIT). ytool starts from there and recreates the published changelog up to
**0.9.9** with open-source libraries. Details: [wiki](https://github.com/YadeWira/ytool/wiki).

## Download

Linux x64, Linux x86, Windows x64 and Windows x86 builds, with every codec library included, are on the
[Releases](https://github.com/YadeWira/ytool/releases) page.

## Usage

```bash
ytool precomp -mzlib+zstd+pja input output.ytp   # find and unpack streams
ytool decode output.ytp restored                 # the original, byte for byte
```

Common options: `-m<codecs>` (joined with `+`), `-t#` threads, `-l#` final LZMA2 compression, `-dd`
deduplication, `-v` verbose. `ytool help precomp` (or `ytool precomp -h`) lists them all, by group,
with the codecs whose library was found; the
[CLI reference](https://github.com/YadeWira/ytool/wiki/CLI-Reference) explains each.

On a terminal, precomp and decode show one progress line (bar, speed, time left, streams) and then a
summary. Redirected to a file or a pipe they print only the summary, as plain text; `-bar` prints
`PROGRESS done total` lines for programs. Colours follow `NO_COLOR`; Windows 7 has none.

## Codecs

| Streams | `-m` | Library |
|---|---|---|
| deflate (zlib, raw) | `zlib`, `libdeflate`, `preflate` | zlib (1.4 in the Windows builds), [libdeflate](https://github.com/ebiggers/libdeflate) 1.26, preflate |
| PNG | `png` | zlib + preflate |
| JPEG, JPEG-LS, JPEG 2000 | `pja` | [PJA](https://github.com/YadeWira/PJA) 0.9.14 |
| JPEG | `brunsli` | brunsli |
| LZ4 frames / raw blocks | `lz4f` / `lz4`, `lz4hc` | lz4 1.11.1 (raw blocks need their size: `-mlz4:s64kb`) |
| Zstandard | `zstd` | zstd 1.6.0 |
| LZO | `lzo1x`, `lzo1c`, `lzo2a` | LZO 2.10 |
| raw LZMA | `lzma` | LZMA SDK 26.06 |
| lzip (`.lz`, plzip, tarlz) | `lzip` | [lzlib](https://www.nongnu.org/lzip/lzlib.html) 1.16 (rebuilds lzip 1.22-1.26) |
| WAV | `flac`, `wavpack` | libFLAC, WavPack |
| Oodle | `kraken`, `mermaid`, … | proprietary: bring your own `oo2core` |
| duplicates | `-dd` | in memory; `-dd1`…`-dd5` use srep, not included ¹; `-ddo` uses OSREP, included ² |
| final stage | `-l#` | fast-lzma2 1.2.0 ([ultra-fast-lzma2](https://github.com/YadeWira/ultra-fast-lzma2)) |

### Coming soon: the new pack family

[PJA](https://github.com/YadeWira/PJA) is the first of a family of recompressors with the same rule (the
original comes back byte for byte, and nothing is written unless it verified). The others join ytool as
each one reaches a stable release:

| | Streams | Successor of |
|---|---|---|
| [PMPA](https://github.com/YadeWira/PMPA) | MPEG audio (MP1, MP2, MP3) | packMP3, packMP2 |
| [PPA](https://github.com/YadeWira/PPA) | PNG, APNG, MNG, JNG | packPNG |
| [PRA](https://github.com/YadeWira/PRA) | raster images (PNM, BMP, TIFF, PSD, HDR…) | packPNM |
| [PAIA](https://github.com/YadeWira/PAIA) | animated images (GIF, WebP, FLI/FLC, ANI…) | — |
| [POA](https://github.com/YadeWira/POA) | Ogg (Vorbis, Opus, FLAC, Speex, Theora) | — |
| [PDA](https://github.com/YadeWira/PDA) | documents (PDF, Office, OpenDocument, EPUB, CHM…) | — |

packJPG, packPNG and packMP3 were retired in 0.9.9a in favour of this family.

¹ SREP's sources are "All rights reserved", so ytool does not ship it. Put `srep64`/`srep.exe` next to
ytool to use `-dd1`…`-dd5` ([personal builds](https://github.com/YadeWira/srep-builds), 3.94 or later:
3.93a can write archives that do not decompress, and ytool warns about it), or its library,
`libsrep.so`/`srep.dll` (3.97 or later), which runs srep inside ytool and is used first when both are
there; the archives are the same either way. Without either, ytool says so and uses `-dd`. If srep fails,
precomp and decode fail with srep's own message.

² **`-ddo`**: [OSREP](https://github.com/YadeWira/omega-srep) (MIT) as the external deduplicator, its
parameters in `-osp<params>` (joined with `:`, each passed with a `-`: `-ospm3:l64`). The packages
include OSREP 0.0.18 (`osrep` / `osrep.exe` next to ytool). Its format v7 (`-m6`, the default) is
frozen, so `.ytp` files made with it keep decoding. Measured on 870 MB: the size of srep's `-dd5`,
with a slower encode.

## Differences from xtool 0.9.9

- **Own container format.** ytool's files are not xtool's and the two do not read each other's.
- **Missing:** the `mp3` scanner (until PMPA is stable), the `ogg`, `bink` and `wwise` scanners, `gdeflate`,
  `-cfgoodle`, and the brute mode (`-b`) for Oodle. `-cfgzlib:st<n>` (the deflate strategy), `-cfgzstd`
  (all 13 of 0.9.9's keys), `-cfglz4` (acceleration, block size, favorDecSpeed…), `-b` for lz4, lz4f and
  zstd (the same candidates and lines as 0.9.9, minutes faster), and zipcrypto are there. How 0.9.9's `-b` and `-cfg` work, read from its binary:
  [xtool 0.9.9 brute and cfg](https://github.com/YadeWira/ytool/wiki/xtool-0.9.9-brute-and-cfg).
- **Prefetch** is `-p#` (0.9.9 renamed it `-pf#`).
- **`-rA=B`** works as in 0.9.9 (streams A detects are processed with B instead). A `-r<codec>` with no
  `=` does nothing in 0.9.9; in ytool it is a codec to retry failed streams with. Reassigning to `zlib`
  searches levels, where 0.9.9 loses every such stream.
- 0.9.9 loads several versions of a library at once; ytool loads one per library.

The flag-by-flag comparison, measured against the 0.9.9 binary:
[CLI reference](https://github.com/YadeWira/ytool/wiki/CLI-Reference); the longer notes that used to be in
this README: [Project Notes](https://github.com/YadeWira/ytool/wiki/Project-Notes).

## Building

Linux, with FPC 3.2.2, gcc/g++, git, cmake and 7z:

```bash
bash contrib/build-native-linux.sh     # C objects linked into the binary (required)
bash contrib/build-plugins-linux.sh    # codec libraries (.so)
mkdir -p .fpcout
fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
  -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
  -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -Fucontrib/LZMADelphi -Fucontrib/ZLibStatic \
  -oytool ytool.dpr
```

Linux x86: `contrib/build-linux-x86.sh`, on an x86-64 host with FPC 3.2.2 for i386-linux and
gcc-multilib (the script says what it needs).

Windows: the C objects and DLLs are cross-compiled from Linux (`build-native-windows*.sh`,
`build-plugins-windows*.sh`), and `ytool.exe` is compiled on Windows (`contrib/winbuild.ps1`,
`winbuild-x86.ps1`). Every dependency is pinned and the pin is checked. Details:
[Installation and Building](https://github.com/YadeWira/ytool/wiki/Installation-and-Building).

## Testing

```bash
tests/regression.sh            # builds, generates a corpus, checks every round-trip
NO_BUILD=1 tests/regression.sh
```

Every case must come back byte for byte, and every codec must actually process streams: a codec that
silently stores everything as it is still round-trips, so the suite counts what each one processed.

## License

MIT (`LICENSE`): © 2016-2023 Razor12911, © 2026 Yade E. Bravo (YadeWira). Third-party components keep their
own terms: [`THIRD_PARTY.md`](THIRD_PARTY.md).

ytool is an independent continuation, not affiliated with or endorsed by xtool's author.
