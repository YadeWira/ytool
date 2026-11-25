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
- 0.9.6 — stream-coverage telemetry (%); `-oodl#` only partly (see the table below)
- 0.9.9 — zlib scanner: a zlib stream starting at byte 0 of a block was skipped (a `Pos >= 3` guard inherited
  from 0.7.9, where `Pos >= 2` is the first valid position). 21_zlib_many.bin now gives 200 / 200, as 0.9.9 does
- 0.9.7 — reassign stream moved from `-a` to `-r`
- 0.9.9 — `-pa` (patch all streams): lifts the condition that made the patch fallback unreachable in a
  normal scan. `DIFF_TOLERANCE` (`-df#`) still decides whether a patch is accepted.
- 0.9.9 — `-lz4` and `-zstd` repeatable: each occurrence adds a candidate library, tried in order until one
  loads. (Upstream ships several versions of each and loads them *simultaneously*; ours is fallback
  ordering only, since the changelog does not say which and there is no source past 0.7.9 to read.)

#### What 0.9.9 actually ships, read out of the binary

`xtool_099_hotifx.7z` (password `123`) was unpacked so this port could be audited against the real thing
instead of against the release notes. Two facts that the notes alone did not give:

- **`brute` is a top-level subcommand**, listed in `Available commands` next to `decode`, `precomp` and
  the legacy toolkit — not a `precomp` flag. It prints nothing: not with no arguments, not with `-h`,
  not with an input file (all three tried under Wine through a pty, which *does* show every other
  command's help, since 0.9.9 writes through `WriteConsole` and a plain redirect captures nothing).
  What it does is therefore unknown beyond its name.
- **The full codec list is `-mzlib+png+lz4f+zstd+kraken+mermaid+leviathan+gdeflate+flac+wwise+brunsli+mp3+ogg+bink`**,
  and there is a second internal list (`lz4hc`, `lz4f`, `lzo1x`, `lzo2a`, `lzo1c`, `zstd`, then the Oodle
  family `lzna`/`kraken`/`mermaid`/`selkie`/`hydra`/`leviathan`). `packjpg` and `jojpeg` are absent,
  matching the 0.9.9 note "removed packjpg and jojpeg".

Pending from 0.9.9, in the order they would matter:

| Item | State here | Why |
|---|---|---|
| `-cfg<codec>` precompression config | **not implemented** | Sub-key names are recoverable from the binary (`-cfgzlib`, `-cfglz4ac`/`-cfglz4af`/`-cfglz4`, `-cfgzstdwl`/`-cfgzstd`, `-cfgoodle`/`-cfgoodleds`, plus the autocomplete strings `Possible parameters:` / `No possible parameters match`), but what each one *means* is not: 0.9.9 prints no help for them. They do change behaviour — measured, `-mzlib -cfgzlib` on a file where plain `-mzlib` processes 6 / 6 reports `Streams: 0 / 0` — so finding out needs reverse engineering, not guessing. |
| `ogg` scanner (`vorbis`, `opus`) | **not implemented** | Needs a Vorbis/Opus re-encoder; no open one is wired up. |
| `bink` scanner | **not implemented** | No open Bink encoder exists (Bink 2 audio is a proprietary RAD codec). |
| `wwise` scanner | **not implemented** | Needs the Wwise Vorbis/Opus/[ADPCM] re-encoders, proprietary. |
| `-oodle#` multiple libraries | **partial** | `-oodle<path>` can be repeated, and the candidates are tried in order until one loads; that one library is then used for every stream. 0.9.6/0.9.9 instead fall through to the next library *per stream* when one fails. Not measurable here without a real Oodle library. |
| `packjpg` / `jojpeg` removal | **not done** | We still ship `-mpackjpg` as a working codec. 0.9.9 dropped it; we have an open fork (`YadeWira/packJPG`) that works, so dropping it would lose a working codec for changelog fidelity. `jojpeg` has never been buildable (no public source). |
| `mp3` as a *scanner* | **different design** | 0.9.9 scans MP3; we replace MP3 streams through `packMP3` (`-mpackmp3`), which is stronger. Not an omission. |

Its `gdeflate` scanner is **not** pending: gdeflate is DirectStorage-specific (0.9.9 ships `dstorage.dll`
alongside it) and was deliberately removed from this port as dead code with no cross-platform meaning — see
[Known Issues](https://github.com/YadeWira/ytool/wiki/Known-Issues-and-Limitations#gdeflate-removed).

Declared **not applicable** to an open build (would need proprietary multi-DLL infrastructure with no open
equivalent): the `-mzstd=zstd147`-style library-variant pinning syntax.

#### CLI flag differences from 0.9.9, verified against both binaries

Every row was checked by running both binaries on the same input (0.9.9_hotfix5 under Wine), not by
reading release notes:

| 0.9.9 | `ytool` | Consequence |
|---|---|---|
| `-pf#` (prefetch) | parses as `-p#` | `-pf32mb` is accepted and **silently ignored** — `-p` matches by prefix, the trailing `f32mb` fails the "must start with a digit" guard and the cache stays 0. The number is lost with no warning. |
| `-lm#` (0–3) | `-lm#`, same range | Parses the same, but only `-lm3` measurably lowers memory: peak RSS on a 20 MB input (`-c64mb -t4`) was 55.7 MB without it, 53.2 / 55.3 / 30.3 MB with `-lm1` / `-lm2` / `-lm3`. The help prints `-lm` with no level. |
| `-r#` separated by `;` | `-r#` separated by `;` | Parses the same; semantics differ. `-rzlib=zlib` gives 0 / 149 streams in 0.9.9 and 135 / 149 here. |
| `-x#`, `-X#` | same | Byte-identical to 0.9.9: `-x` 149 / 149 files on a real 1.5 MB zip, `-X` the same 14 files (149 − 135 processed). Until 2026-11-25 `-X` extracted on every *failed level attempt*, so a stream that failed at one level and succeeded at another was extracted too (24 files there instead of 14); `tests/regression.sh` now checks it on `24_zlib_mixed.bin`. |
| `brute` subcommand | absent | Not implemented; its semantics are unknown (see above). |

Renaming `-p` to `-pf` is a one-line change, but it would break every existing command line that uses
`-p`, so it is left as a documented divergence until someone decides which way to go.


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
- External dedup (`-mzlib -dd1`) has moved twice and settled. It started on
  [Intensity/srep](https://github.com/Intensity/srep), moved to
  [omega-srep](https://github.com/YadeWira/omega-srep) to escape a real cross-architecture bug, and has now
  **returned to Intensity/srep** — the reference implementation — with that bug fixed at its source instead.
  The defect was VMAC's generic 128-bit `ADD128`/`PMUL64` fallback on i686, whose type-punning GCC's `-O2`+
  strict-aliasing optimisations are entitled to break; the fix routes the modified operands through
  read-write constraints (`contrib/patch_srep_vmac.py`), so it is a correction to that source, not a
  compiler workaround. The same fix was applied to omega-srep while it was pinned.

  > **What the return to `Intensity/srep` actually took**, all measured against the 2014 binary (`48f4b97`):
  >
  > - **The encode method changed, and that is the real fix — not the decode flag.** The bare `-m<N>` form
  >   writes an index-LZ footer that the decoder reaches by **seeking** to end-of-file. `DecChunk` feeds
  >   srep through a stdin pipe, which cannot seek, so every `-dd1` decode failed with
  >   `ERROR! Not found SREP compressed file footer in file -` (exit 4). Switching the encode to
  >   `-m<N>f` (future-LZ) puts the footer in the stream instead. Measured across the whole
  >   matrix: every `f` and `o` variant (`-m0f` … `-m5o`) decodes from a pipe, and only the
  >   suffix-less `-mN` forms fail. Future-LZ is also
  >   marginally smaller (123,592 vs 123,620 bytes on a 360 KB input) because the index is not
  >   duplicated, and costs a scratch file, since re-reading its input makes stdin compression write
  >   `srep-data.tmp` into the working directory (`-temp=` relocates it).
  > - **An earlier claim here is retracted.** It said the only change needed was inserting `-d` on
  >   decode. That measurement was real — without `-d` the 2014 binary treats the two filenames as
  >   input/output, *compresses* the already-compressed file and exits 0 emitting 100.04% of its input —
  >   but it was the wrong conclusion: ytool already passed `-d` on its decode path, and the failure was
  >   the seek, one layer below.
  > - **Both inline-asm patches are back.** The `"rm"`→`"qm"` register-clobber fix in `hashes.cpp` (which
  >   on i386 is not even a miscompile but a hard failure: only eax/ebx/ecx/edx have 8-bit sub-registers
  >   there) and the VMAC fix above. Every build script applies both, idempotently.
  > - **The Windows threading backend is back.** Intensity/srep kept only the Unix half;
  >   `contrib/srep-win32/` (adapted from the public-domain LZMA SDK) is restored from `054c42e` and
  >   copied into the clone before each Windows build.
  >
  > **Both format changes are one-way.** omega-srep wrote `OSRP` magic and a `.osr` payload; Intensity/srep
  > writes `SREP`. A `.pmp` carrying an omega-srep `-dd1` sub-stream cannot be decoded by this build, and
  > one made by this build cannot be decoded by a binary from the omega-srep era.


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

### Repository layout

197 files live under `contrib/`, and every one of them is either a build input or a build script.
Most third-party *sources* are not vendored: `contrib/pin-repo.sh` clones them on demand into
`contrib/.csrc/`, which is gitignored and reaches 580 MB with every pinned repo checked out.
The exception is `vendor/srep/` — see below.

| Path | What it is | Versioned? |
|---|---|---|
| `common/`, `compat/`, `precompressor/`, `imports/`, `io/`, `sources/` | ytool's own Pascal source | yes |
| `contrib/mORMot/` | **11 files**, not the whole Synopse framework: `SynCommons`, `SynCrypto`, `SynLZ`, `SynTable` and the four FPC units they need, plus 3 `.inc` | yes |
| `contrib/LZ4Delphi/`, `ZSTD4Delphi/`, `XXHASH4Delphi/`, `LZMADelphi/`, `LIBC/`, `WinLibcShim/` | Pascal bindings plus the prebuilt C objects their `{$L}` directives link | yes — these objects are build **inputs** |
| `contrib/ParseExpression/` | expression parser (`-df` tolerance, `-c` sizes) | yes |
| `contrib/preflate/` | preflate C++ source, built into `libpreflate.so` | yes |
| `contrib/mingw-shims/` | a one-line `ShObjIdl.h` redirect for cross-compiling the srep helper with mingw-w64 | yes |
| `vendor/srep/` | **Intensity/srep 3.93a beta, vendored in full** (52 files, 3.6 MB). The one dependency whose source is in the repo rather than cloned: it is frozen since 2014, it carries four local patches `ytool` needs, and it is the only one `ytool` may want to modify rather than just call | yes — the patches are a visible diff against upstream, not a `sed` at build time |
| `contrib/.csrc/` | lz4, zstd, packJPG, packMP3, packPNG, brunsli, FLAC, WavPack, lzo, preflate, fast-lzma2 checkouts | **no** — cloned by the build scripts |

The mORMot tree was trimmed from 976 files to the 11 the binary actually compiles against. That was
verified by building both trees: the resulting binaries are byte-identical. Do not re-add the samples,
`SQLite3/`, `SyNode/` or `SynCrossPlatform/` — none of them are reachable from `ytool.dpr`.

### Linux

Requirements: FPC 3.2.2+, a C compiler (clang++ or g++), `git`, `cmake` (for brunsli).

Steps 1 and 3 are both **required**: the binary will not link without step 1, because four C
objects it references (`lz4delphi.linux.x64.o`, `xxhash4delphi.linux.x64.o`,
`zstd4delphi.linux.x64.o`, `lzmadelphi.linux.x64.o`) are generated, not committed — they are
covered by the `*.o` ignore rule and a fresh clone does not have them. Step 2 is optional: a
binary built without it still runs, but the plugin-only codecs stay unavailable and the lz4
codecs fall back to the distro's library.

```bash
# 1. native objects (lz4/zstd/xxhash/lzma, linked into the binary) — REQUIRED
bash contrib/build-native-linux.sh

# 2. plugins (liblz4, packjpg, preflate, fast-lzma2, brunsli, packmp3) as .so
bash contrib/build-plugins-linux.sh

# 3. the ytool binary
mkdir -p .fpcout
fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
  -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
  -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -Fucontrib/LZMADelphi \
  -oytool ytool.dpr
```

**srep is built separately, and only if you want it.** It is the helper behind `-dd<N>` (external
dedup); ytool builds and runs without it, and `-dd` (in-memory dedup) does not need it. Its source,
SREP 3.93a beta (Intensity/srep `48f4b97`, October 2014), lives in `vendor/srep/`:

```bash
bash contrib/build-srep.sh            # srep64        (also: win64 -> srep.exe, win32 -> srep-x86.exe, all)
```

`mkdir -p .fpcout` is not cosmetic: `-FU.fpcout` makes FPC write its unit files there,
and a fresh clone has no such directory, so the compile dies with
`Can't create object file: .fpcout/IOUtils.o (error code: 2)`. `tests/regression.sh`
already creates it.

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
bash contrib/build-plugins-windows.sh   # 8 plugin DLLs (mingw-w64 + cmake)
bash contrib/build-srep.sh win64        # optional: srep.exe for -dd<N>
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
