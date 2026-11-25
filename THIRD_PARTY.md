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
| lz4 (`lib/`) | built by `contrib/build-native-*.sh` from github.com/lz4/lz4 | Yann Collet | BSD 2-Clause |
| Zstandard | idem, github.com/facebook/zstd (v1.5.2) | Facebook, Inc. (now Meta) | BSD 3-Clause (dual GPL-2.0; used under BSD) |
| xxHash | idem, github.com/Cyan4973/xxHash | Yann Collet | BSD 2-Clause |
| LZMA SDK | `contrib/LZMADelphi/` | Igor Pavlov | Public domain |
| mORMot (8 units) | `contrib/mORMot/` | Arnaud Bouchez / Synopse | MPL 1.1 / GPL 2.0+ / LGPL 2.1+ tri-licence (per file headers) |
| LZ4Delphi, ZSTD4Delphi, XXHASH4Delphi, LIBC | `contrib/` | YWtheGod (github.com/YWtheGod) | **None declared** (no licence file in the upstream repositories) |
| ParseExpression | `contrib/ParseExpression/` | Egbert van Nes | "Freeware with source" (its `readme.txt`) |
| Win32 threading backend | `contrib/srep-win32/` | adapted from the LZMA SDK (Igor Pavlov) | Public domain |

## Plugins (separate libraries, loaded at run time, not linked)

| Component | Source | Author | Terms |
|---|---|---|---|
| zlib | github.com/madler/zlib | Jean-loup Gailly, Mark Adler | zlib licence |
| preflate | `contrib/preflate/`, github.com/deus-libri/preflate | Dirk Steinke | Apache 2.0 |
| fast-lzma2 | github.com/conor42/fast-lzma2 | Conor McCarthy | BSD 3-Clause (dual GPL-2.0; used under BSD) |
| brunsli | github.com/google/brunsli | Google LLC | MIT |
| packJPG | github.com/YadeWira/packJPG (fork) | HTW Aalen University and Matthias Stirner; fork by YadeWira | LGPL 3.0 |
| packMP3 | github.com/YadeWira/packMP3 (fork) | Ratisbon University and Matthias Stirner; fork by YadeWira | LGPL 3.0 |
| libFLAC | github.com/xiph/flac | Josh Coalson, Xiph.Org Foundation | BSD 3-Clause (Xiph) for libFLAC |
| WavPack | github.com/dbry/WavPack | David Bryant | BSD 3-Clause |
| LZO | oberhumer.com, lzo-2.10 | Markus F.X.J. Oberhumer | **GPL 2.0**. The shipped `lzo2` library is GPL: whoever redistributes it must also offer its source (the unmodified 2.10 tarball). |

## External helper (a separate program)

| Component | Where | Author | Terms |
|---|---|---|---|
| SREP 3.93a beta | `vendor/srep/`, built only by `contrib/build-srep.sh` | Bulat Ziganshin | **"Copyright (C) 2009-2014 Bulat Ziganshin. All rights reserved."** The eight files in `vendor/srep/Compression/SREP/` carry that header and add: *"Mail Bulat.Ziganshin@gmail.com if you have any questions or want to buy a commercial license for the source code."* No licence grants redistribution or modification. |

SREP's support code in the same tree has its own, permissive terms: VMAC/VHASH
(Ted Krovetz, Wei Dai) and the LZMA SDK threading code are public domain, and
the LibTomCrypt ciphers and hashes are "free for all purposes".

ytool runs SREP as an external process (`-dd<N>`); it is not linked into
ytool, and ytool builds and runs without it.
