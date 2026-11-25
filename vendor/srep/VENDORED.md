# Vendored srep

`vendor/srep/` is [Intensity/srep](https://github.com/Intensity/srep) at commit
`48f4b97a1c6db91b4d2dcc0b96539d639e5fb899` — SREP 3.93a beta, October 11 2014, by
Bulat Ziganshin. It is the reference implementation of the LZ77 preprocessor that
`ytool` uses for external deduplication (`-dd<N>`).

Vendored rather than cloned at build time so that:

- the exact source that produced a shipped `srep64`/`srep.exe` is in the repo, not
  behind a network fetch of a repository that has been frozen since 2014;
- the local patches below are visible as a diff, instead of being `sed` expressions
  applied to an unknown base at build time;
- it can be modified to fit `ytool` rather than only driven through its CLI.

## Why not omega-srep

`YadeWira/omega-srep` was used for a while (pinned to `v1.0.5`) because Intensity/srep
is unmaintained and had a real cross-architecture bug. That bug turned out to live in
*this* source — VMAC's portable 128-bit fallback for i386 — so returning here with the
fix applied is more honest than depending on a fork for it. omega-srep has since been
rewritten twice (C++ → Rust → Free Pascal) and now defines its own formats (`OSR6`,
`OSR7`, `.osr`) with **no compatibility goal** with upstream SREP. Its improvements are
therefore a source to mine, not a drop-in replacement.

## Patches carried here

Each patch in this directory corresponds to a real, reproducible failure. They are
applied at build time from `contrib/`, not by editing these files in place, so a
rebuild from an untouched checkout is reproducible. The rationale for each lives next
to the code that applies it; see `contrib/build-plugins-linux.sh` and
`contrib/patch_srep_*.py`.

## Licensing

This section used to say upstream ships "no licence header". That was wrong.
Upstream ships no licence *file*, but the eight SREP sources in
`Compression/SREP/` (`srep.cpp`, `compress*.cpp`, `decompress.cpp`, `hashes.cpp`,
`hash_table.cpp`, `io.cpp`) all begin with:

    // Copyright (C) 2009-2014 Bulat Ziganshin. All rights reserved.
    // Mail Bulat.Ziganshin@gmail.com if you have any questions or want to buy a
    // commercial license for the source code.

That is a reservation of rights, not a grant. No licence permits redistributing or
modifying this code; the author offers a commercial one. omega-srep reached the
same reading: its `NOTICE` says its pre-3.0.0 history "contain[s] a derivative of
SREP 3.93a (Bulat Ziganshin, 'All rights reserved') and [is] NOT covered by" its MIT
licence, which is why OSREP was written clean-room.

The support code bundled with it has permissive terms of its own: VMAC/VHASH and the
LZMA SDK threading code are public domain, LibTomCrypt is "free for all purposes".

Also contrary to what this file says above, the tree is not byte-for-byte upstream:
patches 1-3 of `contrib/patch_srep.py` are already present in place
(`hashes.cpp`, `vmac.c`). See `THIRD_PARTY.md` at the repository root.
