# What was taken from omega-srep, and what was deliberately left

`YadeWira/omega-srep` began as a fork of the same upstream this tree vendors
(`Intensity/srep` at `48f4b97`). It accumulated real fixes before being rewritten
twice — C++ → Rust (`v2.1.2`) → Free Pascal (`v3.0.0` onwards) — with its own
formats (`OSR6`, `OSR7`) and no compatibility goal with upstream SREP.

So it is a source to mine, not a dependency. This file records what was taken and
why, and what was not taken and why, so the next person does not have to re-read
1000+ lines of changelog to find out.

## Carried over

These are corrections with no format change: the bytes an archive contains are the
same before and after, so adopting them costs no interoperability.

| Fix | Failure without it | Applied in |
|---|---|---|
| CRC32 inline-asm constraint `"rm"` → `"qm"` + `"cc"` clobber | **i386 does not compile at all.** `value` is a byte and `"rm"` lets GCC pick any general register, but only eax/ebx/ecx/edx have 8-bit sub-registers there. Reported as `unsupported size for integer register` at the enclosing function. | `contrib/patch_srep.py` (1) |
| `VHash::compute` stores through a `uint64_t*` cast on an unaligned buffer | Undefined behaviour (UBSAN). Compiles to the same store on x86, so no output change — a contract fix, not a bug fix. | `contrib/patch_srep.py` (2) |
| `#pragma GCC optimize ("no-strict-aliasing")` for i386 in `vmac.c` | **Cross-architecture corruption.** A win64-encoded `-dd1` stream fails its own checksum when decoded on i386, with no error, only wrong data. The arch `#if` chain never defines `ADD128`/`MUL64`/`PMUL64` for i386, so it falls through to the portable-C fallback, whose type punning `-O2`+ strict aliasing is entitled to break. x86-64 never reaches that code, which is why the bug is one-directional. | `contrib/patch_srep.py` (3) |
| `nh_16_func` operands declared read-write (`"+S"`/`"+D"`/`"+c"`) | **i686 SIGSEGV.** The asm advances esi/edi and decrements ecx but declared them read-only, so `-fipa-ra` could skip reloading ecx between the two back-to-back calls that `VMAC_TAG_LEN==128` always makes. ecx arrived as 0, the counter underflowed, and the MMX copy loop ran off the buffer. | `contrib/patch_srep.py` (4) |

All four were reproduced or bisected in omega-srep's own history; the reasoning is
repeated next to the patch so it survives without network access to that repo.

## Not carried over, and why

| Change | Why not |
|---|---|
| `-dup` mode (a second dedup layer with its own `ODUP` trailer) | A feature, not a fix. `ytool` already has dedup (`-dd`, `-dd<N>`), and this would be a second, incompatible one inside the same stream. |
| `--chunk-hash=gear`, `--seed=N`, `-bar`, `--verify`, `-i` | New options on the srep CLI. `ytool` drives srep through a fixed invocation it controls; adding CLI surface here would be dead weight unless `ytool` used it. (`-bar` exists in `ytool` itself, for `ytool`'s own progress.) |
| v5/v6/v7 formats, `OSR6`/`OSR7` magic, `.osr` extension | **A format break by design**, declared as such. Adopting it would make every existing `.pmp` unreadable — the same one-way break the omega-srep detour already cost once. |
| The Rust and Pascal rewrites | Different products with a clean-room spec. Nothing here needs them, and vendoring a rewrite would mean vendoring a second implementation of the same thing. |
| LTO/PGO build flags (`-flto`, PGO profiles) | Build-host tuning, not source. Could be adopted separately for speed; not attempted here because PGO needs a training corpus and a repeatable profile per target. |
| `-m0`/`-m1`/`-m2`/`-m3`/`-m4`/`-m5` method semantics | These are upstream's own methods; omega-srep kept them and so does this tree. See below for the one that changed on our side. |

## The one place our invocation differs from upstream

Not an omega-srep fix, but it belongs here because it is the reason the encode
call looks unusual: `ytool` encodes with `-m<N>f` (future-LZ) rather than `-m<N>`.
The bare form writes an index-LZ footer that the decoder reaches by **seeking** to
end-of-file, and `DecChunk` gives srep a stdin pipe, which cannot seek. Only
`-m1f` and `-m1o` decode from a pipe; `-m0`, `-m1`, `-m2` and `-m3` all fail with
`ERROR! Not found SREP compressed file footer in file -`. Future-LZ keeps the
footer inside the stream, is marginally smaller (no duplicated index), and costs a
scratch file — which `ytool` now names per worker with `-temp=`.
