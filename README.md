# ytool

Open-source recreation of **xtool** — the data precompressor by [Razor12911](https://github.com/Razor12911) —
migrated from Delphi/Windows to **Free Pascal (FPC)**, running natively on **Linux and Windows**.

xtool's last open-source release was **0.7.9** (`ES_R54`, MIT license). The author has kept it closed-source
since, publishing only version notes. `ytool` starts from that last open snapshot, strips the
Delphi/Windows-only dependencies (GUI, CLS, native Delphi APIs), and recreates the intent of the published
changelog **up to 0.9.7** using open-source libraries — while preserving the one invariant that matters for a
precompressor:

> **`decode(precomp(x)) == x`, always, bit-exact.**

Every codec falls back to storing a stream literally if it can't prove a reversible round-trip. Nothing is
allowed to trade reversibility for a smaller file.

## What it does

`xtool`/`ytool` is a *precompressor*: it scans a file for embedded compressed/encoded streams (zlib, JPEG,
FLAC/WAV, MP3, LZ4, etc.), decompresses them to their raw form, and re-compresses that raw form with a
stronger general-purpose compressor (LZMA2 via fast-lzma2). Because the raw form is more compressible than the
original compressed stream, the final archive ends up smaller than just running a compressor over the
original file — and `decode` reverses the whole pipeline back to the exact original bytes.

## Status

Migrated in full: build, native reversibility, dynamic codec loading, and the encode/decode pipeline all run
on **FPC 3.2.2 (`{$mode delphi}`)**, Linux and Windows, x86-64.

### Codecs operational on Linux

| Codec | Library | Notes |
|---|---|---|
| zlib / deflate | zlib | raw deflate + zlib-header detection |
| preflate | [deus-libri/preflate](https://github.com/deus-libri/preflate) | reconstructs deflate from any encoder |
| PNG | zlib + preflate | reassembles multi-chunk `IDAT` streams |
| JPEG | [packJPG](https://github.com/packjpg/packJPG) | |
| JPEG (alt) | [brunsli](https://github.com/google/brunsli) | |
| FLAC / WAV | libFLAC | lossless audio |
| WavPack / WAV | [libwavpack](https://github.com/dbry/WavPack) | lossless audio |
| MP3 | [packJPG/packMP3](https://github.com/packjpg/packMP3) | MPEG-1/2 Layer III |
| LZ4 | liblz4 | |
| Zstandard | libzstd | |
| LZO | liblzo2 | lzo1x / lzo1c / lzo2a |
| fast-lzma2 | [conor42/fast-lzma2](https://github.com/conor42/fast-lzma2) | final-stage compressor |
| dedup | [Intensity/srep](https://github.com/Intensity/srep) | external deduplication (`-dd#`) |

**Closed / not implementable in an open build:** Oodle (proprietary; loader exists, activates if you supply
your own `oo2core`/`oo2ext` library) and TAK (no open-source encoder exists anywhere).

### Changelog coverage (post-0.7.9, recreated from upstream's published notes)

- 0.8.2 — `ceil`/`floor` in the expression parser
- 0.8.5 — `-X` (extract only unprocessed streams)
- 0.8.6 / 0.9.1 — reassign-stream fixes (recursion guard, uninitialized-read fix)
- 0.8.0 / 0.8.3 — deduplication performance (decode up to **4.7x** faster; encode array growth fixed)
- 0.9.0 — lzo hardening (buffer sizing, error-code handling)
- 0.9.1 — removed the `recompress stream` feature
- 0.9.2 — three low-memory levels (`-lm1`/`-lm2`/`-lm3`)
- 0.9.6 — stream-coverage telemetry (%), `-oodl#` multi-library loader
- 0.9.7 — reassign stream moved from `-a` to `-r`

Not recreated: anything requiring proprietary libraries the project can't ship (Oodle's own codec, TAK), or
upstream syntax that's meaningless without them (`-mzstd=zstd147`-style library-variant pinning).

## Building (Linux)

Requirements: FPC 3.2.2+, a C compiler (clang++ or g++), `git`, `cmake` (for brunsli).

```bash
# 1. native objects (lz4/zstd/xxhash linked into the binary)
bash contrib/build-native-linux.sh

# 2. optional plugins (srep, packjpg, preflate, fast-lzma2, brunsli, packmp3) as .so/exe
bash contrib/build-plugins-linux.sh

# 3. the xtool binary
fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
  -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
  -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -oxtool xtool.dpr
```

System libraries loaded via `dlopen` fallback if the bundled name isn't found: `libz`, `libzstd`, `liblz4`,
`liblzo2`, `libFLAC`, `libwavpack`.

Windows build: see `contrib/build-native-windows.sh` and `winbuild.ps1` (cross-compiled/tested against a
Windows 10 VM; same FPC flags).

## Usage

```bash
./xtool precomp -mzlib+zstd input.bin output.pmp    # precompress with zlib and zstd detectors
./xtool decode output.pmp restored.bin               # bit-exact restore
cmp input.bin restored.bin                           # always identical
```

Run `./xtool precomp` with no arguments for the full flag reference.

## Testing

```bash
tests/regression.sh          # build + synthetic corpus, all round-trips must be bit-exact
NO_BUILD=1 tests/regression.sh
FULL=1 tests/regression.sh   # + a slice of a large real-world corpus, if present
```

The regression suite covers every codec above plus dedup (`-dd`) and reassign (`-r`) paths — any change that
breaks `decode(precomp(x)) == x` fails the suite.

## License

MIT, © 2016-2023 Razor12911 (original xtool author), continued as `ytool`. See `LICENSE`.

`ytool` is an independent community continuation, not affiliated with or endorsed by the original author.
