# ytool's own fixes to srep

These are *not* from omega-srep. They were found by measuring this tree, and each
one addresses a limitation that made `-dd<N>` unusable, untrustworthy or
irreproducible. They are applied by `contrib/patch_srep.py`; this file explains why
each exists.

For the fixes that *were* taken from omega-srep, see `OMEGA-IMPROVEMENTS.md`.

## 1. `-m5` crashed on some inputs (heap-buffer-overflow)

**Symptom.** `srep -m5` / `-m5f` segfaulted (SIGSEGV) or aborted (SIGABRT) with no
message at all, on inputs of a few megabytes, while working fine on others. `-m0`
through `-m4` were unaffected.

**Reproduced.** Any 3.3 MB input containing two overlapping duplicated ranges. The
exit code was 139 or 134 depending on how the heap happened to be laid out.

**Root cause.** ASan located it precisely:

```
heap-buffer-overflow WRITE of size 4
  SliceHash::prepare_buffer   Compression/SREP/hash_table.cpp:68
  BG_COMPRESSION_THREAD::run  Compression/SREP/io.cpp:154
```

Two independent overruns in one loop:

- **a)** The outer loop runs while `p < buf+size`, but the inner loop always advances
  `slices_in_block * slice_size` = `L` bytes and writes one entry per iteration. When
  `size` is not a multiple of `L` the last iteration starts inside the buffer and
  writes an entry for a chunk that does not exist — and reads `hash(p, slice_size)`
  past the end to compute it.
- **b)** `h` is indexed by `chunk = offset/L`, an absolute file position, but it is
  allocated for `filesize/L` entries only. In future-LZ the reader runs ahead of what
  has been consumed, so `offset + size` can exceed `filesize`. Measured on a
  3,300,000-byte input with `-m5`: the loop wanted entry **45056** of **12890**.

**Fix.** Both bounds are enforced: the inner loop stops when the slice would leave the
buffer, and the write is skipped when the index would leave `h`. A chunk that does not
fit is simply not hashed. That can only cost a *missed* match check — `check()`
already returns true ("maybe large enough") when it has no hash — so correctness is
unaffected and this cannot make a wrong match be accepted.

**Verified.** The crashing input now round-trips; ASan reports nothing; `-m0`..`-m5`
all pass on four inputs that previously varied in behaviour.

## 2. Output was not reproducible (no way to fix the hash seed)

**Symptom.** Two identical runs of the same command on the same input produce
different bytes. Correct for a keyed hash — the VMAC key comes from
`systemRandomData()` plus `time()` — and hostile to everything else: a `.pmp`
cannot be reproduced, two builds cannot be diffed, and no test can pin an archive
by hash.

**Fix.** `SREP_SEED_HEX`, an environment variable holding 32 hex-encoded bytes (the
VMAC key length). When set and well-formed, it is used as the key instead of entropy.
An environment variable rather than a CLI flag because srep parses all its options in
one long prefix-matching `if`-chain, where a new prefix can shadow an existing option
— that class of bug already cost omega-srep a release (`-vmfile=` was swallowed by
`-v`).

**Why this is not a security weakening.** The seed is stored in the archive header
regardless; whoever decodes already has it. This exposes nothing new.

**Wired into ytool** as `-seed<64 hex chars>`, validated there rather than in srep,
because srep silently falls back to a random seed when the value is malformed — the
user would believe their build is reproducible when it is not. The value is passed
to the child through `TProcess.Environment`, so srep's argument parser is untouched.

**Verified.** Two `ytool precomp -mzlib -dd3 -seed<hex>` runs on the same input
produce byte-identical `.pmp` files that round-trip. With the seed fixed, a 64-bit
and a 32-bit build of srep produce **byte-identical** archives — which also proves
the CDC chunking is architecture-independent in the methods ytool uses.

## Limitation that remains, and is not fixable from here

`-m1`, `-m2` and the other suffixes-less methods write an **index-LZ** footer (format
v4) that the decoder reaches by `file_seek` to end-of-file. `ytool` decodes through a
stdin pipe, which cannot seek, so those formats cannot be used by this project. The
`f` (future-LZ, v3) and `o` (I/O-LZ, v1/v2) suffixes are sequential and work fine;
`ytool` uses `f`.

This is a format property, not a bug: index-LZ trades a seek for a smaller index. Fixing
it would mean either changing `DecChunk` to decode from a temporary file instead of a
pipe, or adding a sequential variant of the v4 footer to srep. Both are larger changes
than the ones above, and neither is needed: `-m5f` is the best ratio of the set.

## What the numbers say about method choice

Measured on a 16 MB slice of real binaries (`/usr/bin/*` concatenated):

| Method | Output | Ratio | Time | Memory |
|---|---|---|---|---|
| `-m1f` | 7,942,344 | 47.3% | 0.04 s | 33 MB |
| `-m3f` | 6,231,112 | 37.1% | 0.05 s | 18 MB |
| `-m4f` | 6,007,254 | 35.8% | 0.05 s | 17 MB |
| `-m5f` | 5,903,476 | 35.2% | 0.06 s | 18 MB |

`-m5f` is ~26% smaller than `-m1f` and uses *less* memory in the same time. `ytool`'s
`-dd<N>` already selects the method directly (`-dd5` = `srep -m5f`), so the default
matters more than the range.
