# Third-party components

`LICENSE` (MIT) covers ytool's own code: xtool by Razor12911 and the work added
in this port. The components below are other people's work. Each keeps its own
author and terms, and nothing in this repository relicenses them.

What each entry says about its terms was read from the component's own files
(its `LICENSE`/`COPYING` or its source headers) on 2026-11-25, not assumed.
"None declared" means exactly that: no licence file and no licence header was
found, and no grant of rights should be read into the silence.

## Compiled into the ytool binary

| Component | Where | Author | Terms |
|---|---|---|---|
| lz4 (`lib/`) | built by `contrib/build-native-*.sh` and `build-plugins-*.sh` from github.com/lz4/lz4 (1.11.1) | Yann Collet | BSD 2-Clause |
| Zstandard | idem, github.com/facebook/zstd (v1.5.2 objects; `libzstd` plugin v1.6.0, shipped beside the binary) | Facebook, Inc. (now Meta) | BSD 3-Clause (dual GPL-2.0; used under BSD) |
| xxHash | idem, github.com/Cyan4973/xxHash | Yann Collet | BSD 2-Clause |
| LZMA SDK | `contrib/LZMADelphi/` | Igor Pavlov | Public domain |
| mORMot (8 units) | `contrib/mORMot/` | Arnaud Bouchez / Synopse | MPL 1.1 / GPL 2.0+ / LGPL 2.1+ tri-licence (per file headers) |
| LZ4Delphi, ZSTD4Delphi, XXHASH4Delphi, LIBC | `contrib/` | YWtheGod (github.com/YWtheGod) | **None declared** (no licence file in the upstream repositories) |
| ParseExpression | `contrib/ParseExpression/` | Egbert van Nes | "Freeware with source" (its `readme.txt`) |

## Plugins (separate libraries, loaded at run time, not linked)

| Component | Source | Author | Terms |
|---|---|---|---|
| zlib | github.com/madler/zlib (1.4 in the Windows packages; Linux uses the system libz) | Jean-loup Gailly, Mark Adler | zlib licence |
| preflate | `contrib/preflate/`, github.com/deus-libri/preflate | Dirk Steinke | Apache 2.0 |
| fast-lzma2 1.2.0 | github.com/YadeWira/ultra-fast-lzma2 (its `fast-lzma2/` folder), maintained fork of github.com/conor42/fast-lzma2 | Conor McCarthy; fork by YadeWira | BSD 3-Clause (dual GPL-2.0; used under BSD) |
| brunsli | github.com/google/brunsli | Google LLC | MIT |
| PJA (`libpja`, released binary) | github.com/YadeWira/PJA | Yade E. Bravo (YadeWira) | MIT. Its `NOTICE`: the arithmetic-coded JPEG coder follows libjpeg (IJG); JPEG-LS follows CharLS 2.4.2 (BSD 3-Clause) |
| packMP3 | github.com/YadeWira/packMP3 (fork) | Ratisbon University and Matthias Stirner; fork by YadeWira | LGPL 3.0 |
| libFLAC | github.com/xiph/flac | Josh Coalson, Xiph.Org Foundation | BSD 3-Clause (Xiph) for libFLAC |
| WavPack | github.com/dbry/WavPack | David Bryant | BSD 3-Clause |
| LZO | oberhumer.com, lzo-2.10 | Markus F.X.J. Oberhumer | **GPL 2.0**. The shipped `lzo2` library is GPL: whoever redistributes it must also offer its source (the unmodified 2.10 tarball). |

## Not included: SREP

`-dd<N>` (external dedup) runs **SREP 3.93a beta** by Bulat Ziganshin as a
separate program. Its sources say "Copyright (C) 2009-2014 Bulat Ziganshin. All
rights reserved." and offer a commercial licence; no licence grants
redistribution or modification. So this repository does not contain SREP's
source or binaries (it did until 2026-11-25). Personal builds are kept, with
that notice, in [YadeWira/srep-builds](https://github.com/YadeWira/srep-builds).
ytool builds and runs without it.
