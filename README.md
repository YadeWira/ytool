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
on **FPC 3.2.2 (`{$mode delphi}`)**, Linux and Windows, x86-64. Every claim below has been verified by an
actual bit-exact round-trip (`decode(precomp(x)) == x`, byte-compared) on the platform(s) listed — not just
"it compiles".

### Codecs

| Codec | Library | Linux | Windows |
|---|---|---|---|
| zlib / deflate | zlib | ✅ | ✅ (built into the binary) |
| preflate | [deus-libri/preflate](https://github.com/deus-libri/preflate) | ✅ | ✅ |
| PNG | zlib + preflate | ✅ | ✅ |
| PNG/APNG/JNG/MNG (alt, `-mpackpng`) | [packPNG](https://github.com/YadeWira/packPNG) (preflate + WebP-lossless) | ✅ | ✅ |
| JPEG | [packJPG](https://github.com/YadeWira/packJPG) (our own fork, LGPLv3) | ✅ | ✅ |
| JPEG (alt) | [brunsli](https://github.com/google/brunsli) | ✅ | ✅ |
| FLAC / WAV | [xiph/flac](https://github.com/xiph/flac) | ✅ | ✅ |
| WavPack / WAV | [dbry/WavPack](https://github.com/dbry/WavPack) | ✅ | ✅ |
| MP3 | [packJPG/packMP3](https://github.com/packjpg/packMP3) | ✅ | ✅ |
| LZ4 | liblz4 | ✅ | ✅ (built into the binary) |
| Zstandard | libzstd | ✅ | ✅ (built into the binary) |
| LZO | [Oberhumer lzo](https://www.oberhumer.com/opensource/lzo/) | ✅ | ✅ |
| raw LZMA1 (`-mlzma`) | LZMA SDK (Igor Pavlov, public domain) | ✅ | ✅ |
| fast-lzma2 (final stage, `-l#`) | [conor42/fast-lzma2](https://github.com/conor42/fast-lzma2) | ✅ | ✅ |
| dedup, in-memory (`-dd`) | — | ✅ | ✅ |
| dedup, external (`-dd<N>`) | [Intensity/srep](https://github.com/Intensity/srep) | ✅ | ✅ |
| Oodle | proprietary | 🔒 loader ready, needs *your own* `oo2core`/`oo2ext` library — see below | same |

**Genuinely closed, no open build possible:** TAK (no open-source encoder exists, anywhere — only a
reverse-engineered decoder) and `jojpeg` (no known public source at all). Oodle's *codec* is the same story
(proprietary bitstream, no legally-redistributable open encoder reproduces it) — but the *loader* is open and
included; if you legally have an `oo2core`/`oo2ext` DLL/.so, drop it next to the binary or point `-oodle<path>`
at it and the codec activates.

Prebuilt binaries (Linux x64 tarball, Windows x64 zip, Windows x86 zip — all three with every
buildable plugin library included) are on the [Releases page](https://github.com/YadeWira/ytool/releases).

### Changelog coverage — inherited/recreated from xtool's own published notes (post-0.7.9, up to 0.9.7)

These recreate upstream Razor12911's *own announced* changes, not new design of ours:

- 0.8.0 / 0.8.3 — deduplication performance (decode up to **4.7×** faster; encode array-growth fixed)
- 0.8.2 — `ceil`/`floor` in the expression parser
- 0.8.5 — `-X` (extract only unprocessed streams)
- 0.8.6 / 0.9.1 — reassign-stream fixes (recursion guard on the transfer path, uninitialized-variable fix)
- 0.9.0 — lzo hardening (buffer sizing, error-code handling)
- 0.9.1 — removed the `recompress stream` feature
- 0.9.2 — three low-memory levels (`-lm1`/`-lm2`/`-lm3`)
- 0.9.6 — stream-coverage telemetry (%), `-oodl#` multi-library loader
- 0.9.7 — reassign stream moved from `-a` to `-r`

Declared **not applicable** to an open build (would need proprietary multi-DLL infrastructure with no open
equivalent): the `-mzstd=zstd147`-style library-variant pinning syntax.

### Beyond the changelog — our own fixes, found during this port (not upstream features)

Found and fixed while building/testing this port, not from any xtool release note:

- Removed two dead CLI commands (`patch`, `archive`) that were listed in `--help` but never actually wired to
  any handler — running them silently did nothing.
- Fixed `WriteLine` on Windows: it called `WriteConsole()` directly, which silently produces zero output when
  stdout/stderr isn't a real console (any redirect, pipe, or non-interactive SSH session) — the process would
  exit 0 having "worked" while emitting nothing.
- `WavPack` codec is new (xtool's own changelog only ever mentioned wavpack as an *external plugin transfer
  target*, 0.8.6 — we built it as a first-class codec instead, since no open TAK encoder exists to pair with it).
- Ported `srep` (external dedup, `-dd<N>`) to Windows: its Win32 threading backend was missing from the
  [Intensity/srep](https://github.com/Intensity/srep) fork (only Unix was kept); adapted from the public-domain
  LZMA SDK (Igor Pavlov), same underlying API. See `contrib/srep-win32/`.
- New codec `-mpackpng` (PNG/APNG/JNG/MNG via [packPNG](https://github.com/YadeWira/packPNG), preflate +
  WebP-lossless) — coexists with the classic zlib-based PNG codec, ~45% smaller on real-world images since it
  models pixels instead of just re-encoding the deflate stream. MNG (which ends at `MEND`, not `IEND`) is
  covered too: its embedded PNG/JNG sub-images each end in their own `IEND`, but since MNG's chunk layout is
  flat, the container-size walker just ignores `IEND` in MNG mode and stops only at the real `MEND`.
- New command `analyze` — **exclusive to `ytool`, no xtool equivalent.** Runs a real compression trial per
  codec against a file and recommends a `-m` combination based on actual measured ratio, not just stream
  detection. See [CLI Reference](https://github.com/YadeWira/ytool/wiki/CLI-Reference#analyze).
- Fixed a typo'd conditional-compilation symbol (`CPU64BITS`, never a real FPC symbol — the correct one is
  `CPU64`) that had silently taken the 32-bit branch on **every 64-bit build**, Linux and Windows alike, for
  the whole life of this port: the memory limit was capped at 1.5GB instead of the intended 64-bit ceiling,
  the `-p` I/O-cache option was force-disabled, and `srep64` was never selected over the fallback path. Fixed
  across `common/Utils.pas`, `precompressor/PrecompMain.pas`, `imports/OodleDLL.pas`.
- `ytool` also builds and runs natively on **Windows x86 (32-bit, i386-win32)**, all 11 codecs included —
  verified under WOW64 on Windows 7 SP1 x64 with a real bit-exact round-trip against the 64-bit build (encode
  on 64-bit, decode on 32-bit) for 10 of them. The one exception, `-mflac`, has a narrow one-directional
  cross-architecture limitation (same-architecture round-trips always work) — see
  [Known Issues & Limitations](https://github.com/YadeWira/ytool/wiki/Known-Issues-and-Limitations#-mflac-one-directional-32-bit64-bit-cross-architecture-incompatibility).
  Prebuilt binary on the [Releases page](https://github.com/YadeWira/ytool/releases); see
  `contrib/winbuild-x86.ps1` and
  [Build System Internals](https://github.com/YadeWira/ytool/wiki/Build-System-Internals) to build it yourself.

### Known limitation, not deeply verified

`ytool` also ships xtool's companion binary-patching toolkit: `generate` / `find` / `erase` / `replace` /
`extract` / `execute`. The `find` → `extract` chain was tested end-to-end and is bit-exact. `erase` and
`generate` run and produce output but weren't verified beyond that. `replace` showed **inconsistent exit
codes across identical invocations** in testing (likely a latent concurrency issue in that legacy code path)
— treat it as unverified until someone investigates further.

## Building

### Linux

Requirements: FPC 3.2.2+, a C compiler (clang++ or g++), `git`, `cmake` (for brunsli).

```bash
# 1. native objects (lz4/zstd/xxhash linked into the binary)
bash contrib/build-native-linux.sh

# 2. optional plugins (srep, packjpg, preflate, fast-lzma2, brunsli, packmp3) as .so/exe
bash contrib/build-plugins-linux.sh

# 3. the ytool binary
fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
  -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
  -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -oytool ytool.dpr
```

System libraries loaded via `dlopen` fallback if the bundled name isn't found: `libz`, `libzstd`, `liblz4`,
`liblzo2`, `libFLAC`, `libwavpack`.

### Windows

Everything is cross-compiled **from Linux** with mingw-w64, then the FPC binary itself is compiled on
Windows (FPC/Lazarus has no Linux→Windows cross-compiler for this codebase's dependency set):

```bash
# on Linux:
bash contrib/build-native-windows.sh    # native lz4/zstd/xxhash objects (mingw-w64)
bash contrib/build-plugins-windows.sh   # 8 plugin DLLs + srep.exe (mingw-w64 + cmake)
# copy the source tree + the .dll files to a Windows machine with FPC/Lazarus 3.2.2, then:
```
```powershell
# on Windows:
pwsh -File contrib\winbuild.ps1
```

Requires `x86_64-w64-mingw32-gcc`/`g++` and `cmake` on the Linux side.

## Usage

```bash
./ytool precomp -mzlib+zstd input.bin output.pmp    # precompress with zlib and zstd detectors
./ytool decode output.pmp restored.bin               # bit-exact restore
cmp input.bin restored.bin                           # always identical
```

Run `./ytool precomp` with no arguments for the full flag reference.

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
