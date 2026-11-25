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

Upstream ships no licence file and no licence header (the same situation as omega-srep,
whose changelog records the decision to proceed while declaring none). This vendor copy
inherits that status: it is redistributed as source, unmodified except for the patches,
and `ytool` loads it as a separate executable — not linked into the binary — so the
question of combining it with `ytool`'s MIT code does not arise at link time.
