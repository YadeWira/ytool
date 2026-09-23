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

**How the ✅ marks below were earned, because the obvious method is not enough.** A bit-exact round-trip
(`decode(precomp(x)) == x`) proves the tool is *reversible*. It does **not** prove a codec works: when a
codec fails to reproduce a stream, `ytool` stores that stream literally, and a literal store is perfectly
reversible. A codec that does nothing at all passes every round-trip test. That is not hypothetical — with
all six plugin libraries deleted the regression suite used to report `399 OK, 0 FAIL`, and `-mzstd` shipped
dead, detecting every CLI-written frame and processing none, under a ✅ earned by round-trip alone.

So each ✅ now also requires *engagement*: the suite asserts a minimum number of streams actually processed
per codec, and packaged releases are checked by comparing each codec's output size against the size a
literal store would produce. See [Testing](#testing).

> **Container format change (`XTP1`).** `.pmp` files now carry a digest of every stream, and decoding
> verifies each restored stream against it. Before this, the decoder accepted a restored stream by
> comparing its **size** and nothing else: 40 of 40 single-byte corruptions of a `.pmp` decoded with exit 0
> and produced wrong data. The magic moved from `XTL0` to `XTP1`, so **`.pmp` files written by this version
> cannot be read by earlier builds**, and earlier builds' files cannot be read by this one — an older build
> refuses the file with exit 1 and leaves no output behind, rather than misreading it. Coverage is limited to
> streams: bytes that pass through literally (all of a file in which no codec matched) are still not
> verified. See [the format page](https://github.com/YadeWira/ytool/wiki/Precomp-File-Format).

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
| MP3 | [YadeWira/packMP3](https://github.com/YadeWira/packMP3) (successor fork, LGPLv3) | ✅ | ✅ |
| LZ4 (`lz4f`) | liblz4, pinned to `0774d05` | ✅ (`liblz4.so`, shipped) | ✅ (`liblz4.dll`) |
| LZ4 raw blocks (`lz4`, `lz4hc`) | liblz4 | ⚠️ detects nothing — see below | same |
| Zstandard | libzstd | ✅ ¹ | ✅ ¹ |
| LZO (`lzo1x`) | [Oberhumer lzo](https://www.oberhumer.com/opensource/lzo/) | ✅ ² | ✅ ² |
| raw LZMA1 (`-mlzma`) | LZMA SDK (Igor Pavlov, public domain) | ✅ | ✅ |
| fast-lzma2 (final stage, `-l#`) | [conor42/fast-lzma2](https://github.com/conor42/fast-lzma2) | ✅ | ✅ |
| dedup, in-memory (`-dd`) | — | ✅ | ✅ |
| dedup, external (`-dd<N>`) | [omega-srep](https://github.com/YadeWira/omega-srep) | ✅ | ✅ |
| Oodle | proprietary | 🔒 loader ready, needs *your own* `oo2core`/`oo2ext` library — see below | same |

**Genuinely closed, no open build possible:** TAK (no open-source encoder exists, anywhere — only a
reverse-engineered decoder), `jojpeg` (no known public source at all) and `reflate` (`-mreflate`, needs `RAW2HIF_DLL.DLL` / `HIF2RAW_DLL.DLL`, no known public source; without them the codec is disabled and reports 0 / 0 on the same deflate streams where `-mzlib` and `-mpreflate` report 6 / 6). Oodle's *codec* is the same story
(proprietary bitstream, no legally-redistributable open encoder reproduces it) — but the *loader* is open and
included; if you legally have an `oo2core`/`oo2ext` DLL/.so, drop it next to the binary or point `-oodle<path>`
at it and the codec activates.

¹ **Zstandard** was dead until recently: `Scan1` never read the frame header and re-encoded with the
library's defaults, which omit the content checksum the `zstd` CLI writes by default, so every CLI-written
frame fell back to a literal store. Fixed by recording the frame descriptor. Two cases still store
literally, both safe and both documented in `PrecompZSTD.pas`: frames written from a pipe (no content-size
field), and some one-shot-versus-chunked divergences at levels 5–15 unless `-mzstd:b128` selects the
streaming path. libzstd is loaded dynamically, not linked in.

² **LZO** reproduces only the `lzo1x_999` family, because its level search iterates
`lzo1x_999_compress_level`. Data from the fast `lzo1x_1` is detected and stored literally.

**LZ4 raw blocks** (`-mlz4`, `-mlz4hc`) report `0 / 0` — not even detection — on raw blocks produced by the
lz4 library, at every size tried and with a first token byte inside the range the heuristic keys on. Open
and not yet diagnosed. Framed LZ4 (`-mlz4f`) is unaffected.

**Linux ships its own `liblz4.so`** and loads it ahead of the system library. Previously the distro's
`liblz4.so.1` was used, and lz4 1.9.4 and 1.10.0 emit different bytes at the same level (`LZ4HC_CLEVEL_MIN`
moved from 3 to 2), so a `.pmp` made on one machine could fail to restore on another.

Prebuilt binaries (Linux x64 tarball, Windows x64 zip, Windows x86 zip — all three with every
buildable plugin library included) are on the [Releases page](https://github.com/YadeWira/ytool/releases).

> **Windows x86 (32-bit) note**: upstream xtool's own author has reported repeated false-positive
> malware flags from antivirus/Patreon scanners specifically on 32-bit Windows binaries (same for the
> original xtool's `.cls` files). No functional issue is known — it's a false positive — but if you're
> repackaging `ytool` for wider public distribution, prefer the Windows x64 build where possible.

### Changelog coverage — inherited/recreated from xtool's own published notes (post-0.7.9, up to 0.9.9)

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
- 0.9.9 — `-pa` (patch all streams): lifts the condition that made the patch fallback unreachable in a
  normal scan. `DIFF_TOLERANCE` (`-df#`) still decides whether a patch is accepted.
- 0.9.9 — `-lz4` and `-zstd` repeatable: each occurrence adds a candidate library, tried in order until one
  loads. (Upstream ships several versions of each and loads them *simultaneously*; ours is fallback
  ordering only, since the changelog does not say which and there is no source past 0.7.9 to read.)

Pending from 0.9.9: `-cfg<codec>` (the flag names and sub-keys were read out of the 0.9.9 binary, but its
output cannot be captured even on real Windows, so what the sub-keys mean is inferred from their names, not
documented), and the `bink` / `wwise` / `ogg` scanners. Its `gdeflate` scanner is **not** pending: gdeflate is
DirectStorage-specific (0.9.9 ships `dstorage.dll` alongside it) and was deliberately removed from this port
as dead code with no cross-platform meaning — see
[Known Issues](https://github.com/YadeWira/ytool/wiki/Known-Issues-and-Limitations#gdeflate-removed).

Declared **not applicable** to an open build (would need proprietary multi-DLL infrastructure with no open
equivalent): the `-mzstd=zstd147`-style library-variant pinning syntax.

### Beyond the changelog — our own fixes, found during this port (not upstream features)

Found and fixed while building/testing this port, not from any xtool release note:

- Removed two dead CLI commands (`patch`, `archive`) that were listed in `--help` but never actually wired to
  any handler — running them silently did nothing.
- Fixed `WriteLine` on Windows: it called `WriteConsole()` directly, which silently produces zero output when
  stdout/stderr isn't a real console (any redirect, pipe, or non-interactive SSH session) — the process would
  exit 0 having "worked" while emitting nothing. **Only `WriteLine` was fixed.** The live status block
  (`Streams:`, `Size:`) still calls `WriteConsole` directly (`PrecompMain.pas`), so on Windows it is lost
  under any redirect: the banner survives, the stream counts do not. Upstream 0.9.9 reworked stats printing
  for what looks like the same reason.
- `WavPack` codec is new (xtool's own changelog only ever mentioned wavpack as an *external plugin transfer
  target*, 0.8.6 — we built it as a first-class codec instead, since no open TAK encoder exists to pair with it).
- Ported `srep` (external dedup, `-dd<N>`) to Windows: its Win32 threading backend was missing from the
  [Intensity/srep](https://github.com/Intensity/srep) fork (only Unix was kept); adapted from the public-domain
  LZMA SDK (Igor Pavlov), same underlying API. (Superseded — see the
  [omega-srep migration](https://github.com/YadeWira/ytool/wiki/Known-Issues-and-Limitations#-mzlib--dd1-external-dedup-via-srep-cross-architecture-failures-newly-found)
  below; the port itself is no longer needed since the new dependency ships its own Windows backend.)
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
  on 64-bit, decode on 32-bit) for every codec, genuinely compressing (not just reversible) in every case.
  (`-mflac` initially shipped broken on 32-bit — its DLL depended on a mingw runtime DLL not present on stock
  Windows, so `LoadLibrary` failed and the encoder never ran — fixed with `-static-libgcc`; see
  [Known Issues & Limitations](https://github.com/YadeWira/ytool/wiki/Known-Issues-and-Limitations#fixed-since-this-page-was-first-written).)
  Prebuilt binary on the [Releases page](https://github.com/YadeWira/ytool/releases); see
  `contrib/winbuild-x86.ps1` and
  [Build System Internals](https://github.com/YadeWira/ytool/wiki/Build-System-Internals) to build it yourself.
- External dedup (`-mzlib -dd1`) migrated from [Intensity/srep](https://github.com/Intensity/srep) (frozen
  upstream, unmaintained since 2014) to [omega-srep](https://github.com/YadeWira/omega-srep): actively
  maintained by the same author, with 3 real bugs already found and fixed upstream during this migration.
  **Breaking change**: omega-srep's on-disk format is a deliberate clean break (`.osr` extension,
  `OSRP` magic bytes instead of `SREP`) — any `.pmp` made with `-dd1` before this migration can no longer be
  decoded.
  **The cross-architecture bug is now genuinely fixed**, in omega-srep itself: isolated to a minimal repro
  entirely outside ytool (a win32 `srep`/omega-srep build rejecting valid win64-encoded content with its own
  internal checksum-mismatch error), root-caused by omega-srep's maintainer to VMAC's generic 128-bit
  `ADD128`/`PMUL64` fallback on i686, whose type-punning GCC's `-O2`+ strict-aliasing
  optimisations are entitled to break -- the defect is in that source, not in GCC (fixed with a targeted `#pragma GCC optimize("no-strict-aliasing")`, no
  performance cost on other paths). Verified end-to-end: the original failing case now round-trips bit-exact,
  and the full cross-architecture regression matrix (357/357) passes with no `-dd1` failures anywhere. See
  [Known Issues & Limitations](https://github.com/YadeWira/ytool/wiki/Known-Issues-and-Limitations#fixed-since-this-page-was-first-written)
  for the full investigation history.
- Also fixed: `common/Threading.pas`'s `TTask.FStatus` had no synchronization at all between the main thread
  and worker threads (plus a dead-code bug that meant a worker's error message never actually got cleared),
  and `find`/`erase`/`replace` swallowed worker errors instead of propagating them — the likely cause of a
  previously-reported bug where `replace` returned inconsistent exit codes with no error message. Fixed with a
  real `TCriticalSection` and by letting the exception reach `ytool.dpr`'s top-level handler, which is the only
  place that sets `ExitCode`.

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
# 1. native objects (lz4/zstd/xxhash linked into the binary, for the internal cache)
bash contrib/build-native-linux.sh

# 2. plugins (liblz4, srep, packjpg, preflate, fast-lzma2, brunsli, packmp3) as .so/exe
bash contrib/build-plugins-linux.sh

# 3. the ytool binary
fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
  -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
  -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -oytool ytool.dpr
```

System libraries loaded via `dlopen` fallback if the bundled name isn't found: `libz`, `libzstd`, `liblz4`,
`liblzo2`, `libFLAC`, `libwavpack`. For lz4 and zstd the fallback is the *last* resort: the codecs that
reconstruct streams are sensitive to the library version, so a bare binary relying on the distro's copy is
at the mercy of whatever version the decoding machine has installed.

**Every dependency is pinned, and the pin is enforced.** All build scripts fetch through
`contrib/pin-repo.sh`, which checks the checkout against the requested revision, corrects it when they
differ, and fails when the result is still wrong. The previous pattern, `[ -d "$dir" ] || git clone
--branch <ver>`, skipped the clone whenever the directory already existed, so a pin only applied to a fresh
checkout: it left packJPG on an old version after the pin moved, and built a published `liblz4.dll` from
lz4 1.10.0 while its script asked for 1.9.4.

### Packaging a release

```bash
contrib/package-release.sh <outdir> [--win-bin <dir-with-ytool.exe-and-ytool-x86.exe>]
```

It refuses to produce an archive when any of these fails, one check per defect that has actually shipped:
each artifact newer than the newest source; the regression suite green in **strict** mode (every codec
must process streams); every Windows DLL importing only libraries Windows ships (a `-posix` build once
imported `libwinpthread-1.dll` and the codec loaded nowhere); an explicit manifest, so a missing DLL
aborts; single-level archive nesting; the README's version claims matching the binaries; and each codec in
the extracted archive measured against the size a literal store would produce. Windows engagement is the
one check it cannot automate — see the note in [Testing](#testing).

### Windows

Everything is cross-compiled **from Linux** with mingw-w64, then the FPC binary itself is compiled on
Windows (FPC/Lazarus has no Linux→Windows cross-compiler for this codebase's dependency set):

```bash
# on Linux:
bash contrib/build-native-windows.sh    # native lz4/zstd/xxhash objects (mingw-w64)
bash contrib/build-plugins-windows.sh   # 8 plugin DLLs + osrep.exe (mingw-w64 + cmake)
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

### On the `.pmp` extension

`.pmp` is only a convention used in this README and in the test scripts —
`ytool` does not hardcode, require or validate any extension, and writes
whatever output path you give it. It detects its own containers by magic
bytes, not by filename.

The convention is this project's own, and not something inherited from
`xtool`: the original 2022 source import (`098e8c4`) does not contain the
string anywhere in the tree, and `.pmp` first appears here in `a17215f`
(2026-06-12), the commit that added the regression suite. Which means it was
adopted while packMP3 was still writing `.pmp` itself -- the rename described
below landed thirteen days later. Why those three letters were chosen is not
recorded anywhere in the history.

Worth stating explicitly because the name is not unique: **packMP3 also wrote
`.pmp` files, up to and including v1.x**. It renamed its own archives to
`.pm3` in commit `f5cf864` (2026-06-25), first shipped in v2.0 — a rename
only, the container magic was untouched. Traces of the old name survive all
over packMP3 today: the `pmplib_*` library API that `ytool` calls, internal
identifiers like `pmp_magic` / `pmp_ext` / `pmpfilename`, and runtime strings
such as `Compressed to PMP in memory`. None of those refer to this format.

So a `.pmp` on disk may be either a `ytool` container or a pre-2.0 packMP3
archive, and the two are unrelated: a `ytool` container is a whole file's
worth of precompressed streams plus the recipe to rebuild them, and it may
itself *contain* MP3 streams that were processed through packMP3.

Nothing actually dispatches on the name, in either direction. packMP3 does
still list `.pmp` among the extensions it accepts, but that list has a single
caller -- the directory walker behind its `-r` recursion -- and it sits inside
`#if !defined(BUILD_LIB)`, so it does not exist at all in the library build
that `ytool` links against. A file named on the command line, and every call
`ytool` makes through `pmplib_*`, is identified purely by content. Confirmed
by reading packMP3's sources and its git history together with its
maintainer.

## Testing

```bash
tests/regression.sh          # build + synthetic corpus, all round-trips must be bit-exact
NO_BUILD=1 tests/regression.sh
FULL=1 tests/regression.sh   # + a slice of a large real-world corpus, if present
```

The regression suite covers every codec above plus dedup (`-dd`) and reassign (`-r`) paths — any change that
breaks `decode(precomp(x)) == x` fails the suite.

**Round-trips are necessary and not sufficient.** Each codec also has a minimum number of streams it must
actually process (`CODEC_EXPECT` in `tests/regression.sh`), and the suite reports `*** CODEC MUERTO ***`
when one processes none. Pipeline stages are checked the same way (`STAGE_EXPECT`). Without those two, a
codec that silently stores everything literally passes.

The test material matters as much as the assertion. Library bindings choose conservative defaults and
command-line tools choose useful ones, and the two diverge systematically: the python `lz4.frame` and
`zstandard` modules write frames **without** a content checksum, the `lz4` and `zstd` CLIs write them
**with** one. A corpus built on the modules' defaults exercised exactly the case that already worked and
passed against codecs that were broken for every real file. The generators use CLI-equivalent settings for
that reason, and a payload chosen to discriminate between compression strategies — a repeated literal
collapses to the same bytes at every level and cannot tell a working level search from a broken one.

**The engagement assertion does not run on Windows.** `ytool`'s status output there goes straight to the
console (see the `WriteLine` note above) and survives neither PowerShell nor `cmd.exe` redirection, so
stream counts cannot be read over SSH. Windows engagement is checked by comparing `.pmp` sizes instead.

## License

MIT, © 2016-2023 Razor12911 (original xtool author), continued as `ytool`. See `LICENSE`.

`ytool` is an independent community continuation, not affiliated with or endorsed by the original author.
