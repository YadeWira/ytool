#!/usr/bin/env python3
"""Generates a synthetic, reproducible corpus for ytool's regression tests.

Covers edge cases and data with real streams (zlib/deflate) at various levels,
sizes that cross the 16MB chunk boundary, incompressible data, and mixes. Deterministic
(fixed seed) so ratios are comparable across runs.

Usage:  python3 tests/gen_corpus.py <output_dir>
"""
import os
import shutil
import subprocess
import sys
import tempfile
import zlib
import lzma
import struct

SEED = 0xC0FFEE


def rng_bytes(n, seed):
    """Simple, portable PRNG (xorshift64) -> deterministic pseudo-random bytes."""
    out = bytearray(n)
    x = seed & 0xFFFFFFFFFFFFFFFF
    i = 0
    while i < n:
        x ^= (x << 13) & 0xFFFFFFFFFFFFFFFF
        x ^= x >> 7
        x ^= (x << 17) & 0xFFFFFFFFFFFFFFFF
        out[i:i + 8] = struct.pack('<Q', x)[:min(8, n - i)]
        i += 8
    return bytes(out)


def write(d, name, data):
    p = os.path.join(d, name)
    with open(p, 'wb') as f:
        f.write(data)
    return p


def png_chunk(tag, data):
    return (struct.pack('>I', len(data)) + tag + data
            + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))


def make_png(w, h, seed):
    """Minimal valid PNG (IHDR+IDAT+IEND, RGB 8bpc, no filter) for -mpng."""
    raw = bytearray()
    x = seed & 0xFFFFFFFF
    for y in range(h):
        raw.append(0)  # filter type 0 (None) per scanline
        for _ in range(w * 3):
            x = (x * 1103515245 + 12345) & 0xFFFFFFFF
            raw.append((x >> 24) & 0xFF)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    return (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', ihdr)
            + png_chunk(b'IDAT', idat) + png_chunk(b'IEND', b''))


def make_png_photo(w, h, seed):
    """PNG with real spatial structure (gradient + pattern), not noise, for
    -mpackpng: a real image codec (WebP-lossless) only wins over data with
    correlation; pure noise (like make_png) defeats it the same as any
    image compressor, giving a trivial fallback with no real coverage.
    61_png_min.bin (make_png) is left untouched, it's used for -mpng."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (None) per scanline
        for xi in range(w):
            r = (xi * 255) // max(w - 1, 1)
            g = (y * 255) // max(h - 1, 1)
            b = ((xi + y + seed) % 32) * 8
            raw += bytes((r, g, b))
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    return (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', ihdr)
            + png_chunk(b'IDAT', idat) + png_chunk(b'IEND', b''))


def make_lz4f(seed):
    """Real LZ4 frame (magic 0x184D2204) via the python 'lz4' module, if available."""
    try:
        import lz4.frame
    except ImportError:
        return None
    text = (b'lz4 frame payload %d ' % seed) * 4000
    return lz4.frame.compress(text)


def make_lzma_alone(seed):
    """Real raw LZMA1 stream (FORMAT_ALONE, 13-byte header) via the stdlib
    'lzma' module -- unknown-size/end-marker variant, same as what the "xz
    --format=lzma" CLI produces by default, for -mlzma."""
    text = (b'lzma alone stream payload %d, ' % seed) * 400
    return lzma.compress(text, format=lzma.FORMAT_ALONE)


def make_jpeg(seed):
    """Real baseline JPEG (not progressive) via Pillow, if available."""
    try:
        from PIL import Image
    except ImportError:
        return None
    img = Image.new('RGB', (32, 32))
    px = img.load()
    x = seed
    for y in range(32):
        for xi in range(32):
            x = (x * 1103515245 + 12345) & 0xFFFFFFFF
            px[xi, y] = ((x >> 24) & 0xFF, (x >> 16) & 0xFF, (x >> 8) & 0xFF)
    with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tf:
        img.save(tf.name, format='JPEG', quality=75, progressive=False,
                  optimize=False)
        path = tf.name
    try:
        with open(path, 'rb') as f:
            return f.read()
    finally:
        os.unlink(path)


def make_mp3(seed):
    """Real CBR MP3 via 'lame' (external CLI), if available."""
    lame = shutil.which('lame')
    if not lame:
        return None
    ch, rate, nframes = 2, 44100, 40000
    y = seed & 0xFFFFFFFF
    pcm = bytearray()
    for _ in range(nframes * ch):
        y ^= (y << 7) & 0xFFFFFFFF
        y ^= y >> 9
        pcm += struct.pack('<h', (y % 20000) - 10000)
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as wf, \
         tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as mf:
        wav_path, mp3_path = wf.name, mf.name
    try:
        block_align = ch * 2
        wav = (b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVE'
               + b'fmt ' + struct.pack('<IHHIIHH', 16, 1, ch, rate,
                                        rate * block_align, block_align, 16)
               + b'data' + struct.pack('<I', len(pcm)) + bytes(pcm))
        with open(wav_path, 'wb') as f:
            f.write(wav)
        r = subprocess.run([lame, '--quiet', '--cbr', '-b', '128',
                             '--noreplaygain', wav_path, mp3_path],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        if r.returncode != 0 or not os.path.exists(mp3_path):
            return None
        with open(mp3_path, 'rb') as f:
            return f.read()
    finally:
        for p in (wav_path, mp3_path):
            if os.path.exists(p):
                os.unlink(p)


def main():
    if len(sys.argv) < 2:
        print('uso: gen_corpus.py <dir_salida>', file=sys.stderr)
        sys.exit(2)
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)

    base_text = (b'The quick brown fox jumps over the lazy dog. '
                 b'Lorem ipsum dolor sit amet. ') * 3000

    # --- edge cases ---
    write(d, '01_empty.bin', b'')
    write(d, '02_one_byte.bin', b'\x42')
    write(d, '03_tiny_text.bin', b'hello world\n')

    # --- incompressible (should find no streams; pure reversibility) ---
    write(d, '10_random_2m.bin', rng_bytes(2_000_000, SEED))

    # --- highly compressible (plain text, no streams but useful for ratio) ---
    write(d, '11_text_8m.bin', base_text[:8_000_000] if len(base_text) >= 8_000_000
          else base_text * (8_000_000 // len(base_text) + 1))

    # --- real zlib/deflate streams at various levels, interleaved with noise ---
    blob = bytearray()
    for i, lvl in enumerate([1, 3, 6, 9, 6, 1]):
        blob += zlib.compress(base_text[: 50000 + i * 20000], lvl)
        blob += rng_bytes(500, SEED + i)
    write(d, '20_zlib_streams.bin', bytes(blob))

    # --- many small zlib streams (stresses the scanner/counter) ---
    many = bytearray()
    for i in range(200):
        many += zlib.compress(("payload-%d " % i).encode() * (100 + i), (i % 9) + 1)
        many += rng_bytes(64, SEED + 1000 + i)
    write(d, '21_zlib_many.bin', bytes(many))

    # --- DUPLICATE streams: exercises dedup (-dd): N distinct x R copies ---
    # each identical copy of the same zlib stream -> StoreDD deduplicates them. Covers the
    # DD path on encode (DDInfo1/DDList1/DDInfo2) and on decode (DDList2 + dup cache).
    dup = bytearray()
    for i in range(30):
        s = zlib.compress(base_text[: 4000 + i * 137], 6)
        for _ in range(3):
            dup += s
            dup += rng_bytes(48, SEED + 5000 + i)  # separator noise (same per i)
    write(d, '23_dup_streams.bin', bytes(dup))

    # --- raw deflate (no zlib header) interleaved ---
    raw = bytearray()
    co = zlib.compressobj(9, zlib.DEFLATED, -15)  # negative wbits = raw deflate
    raw += co.compress(base_text[:80000]) + co.flush()
    raw += rng_bytes(400, SEED + 7)
    write(d, '22_raw_deflate.bin', bytes(raw))

    # --- crosses the 16MB chunk: zlib streams scattered across ~20MB ---
    big = bytearray()
    while len(big) < 20_000_000:
        big += zlib.compress(base_text[:30000], 6)
        big += rng_bytes(40000, SEED + len(big))
    write(d, '30_over_chunk_20m.bin', bytes(big))

    # --- WAV PCM (RIFF): exercises the audio codecs (flac/wavpack detect RIFF,
    #     decode to PCM and recompress lossless; restore reproduces the exact WAV) ---
    ch, bits, rate, nframes = 2, 16, 44100, 40000
    block_align = ch * bits // 8
    byte_rate = rate * block_align
    pcm = bytearray()
    y = 0x1234
    for _ in range(nframes * ch):
        y ^= (y << 7) & 0xFFFFFFFF
        y ^= y >> 9
        pcm += struct.pack('<h', (y % 20000) - 10000)
    wav = (b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVE'
           + b'fmt ' + struct.pack('<IHHIIHH', 16, 1, ch, rate, byte_rate,
                                    block_align, bits)
           + b'data' + struct.pack('<I', len(pcm)) + bytes(pcm))
    write(d, '60_wav_pcm.bin', wav)

    # --- minimal PNG (IHDR/IDAT/IEND): exercises the -mpng codec (detects the
    #     PNG container, not just raw deflate already covered by 20_zlib_streams.bin) ---
    write(d, '61_png_min.bin', make_png(24, 24, SEED))

    # --- PNG with real spatial structure (gradient): genuinely exercises -mpackpng
    #     (packPNG/WebP-lossless) -- pure noise like make_png() doesn't
    #     work, no image codec wins over uncorrelated data ---
    write(d, '62_png_photo.bin', make_png_photo(48, 48, SEED))

    # --- raw LZMA1 stream (stdlib 'lzma', always available): exercises
    #     -mlzma, embedded between noise so it must be detected, not just
    #     handed the whole file ---
    write(d, '63_lzma_alone.bin', rng_bytes(64, SEED) + make_lzma_alone(SEED)
          + rng_bytes(64, SEED + 1))

    # --- The following 3 are OPTIONAL: they require an external tool
    #     present on the machine generating the corpus (not at ytool runtime).
    #     If missing, the file simply isn't written and the corresponding method
    #     (-mlz4f/-mpackjpg+-mbrunsli/-mpackmp3 in regression.sh) still runs but
    #     without finding the real stream -> trivial reversibility, codec coverage = 0
    #     for that run (same criterion already used with 50_lzo1x.bin/gcc+liblzo2).
    lz4f = make_lz4f(SEED)
    if lz4f is not None:
        write(d, '70_lz4f.bin', lz4f)
    else:
        print('aviso: modulo python "lz4" no disponible, se omite 70_lz4f.bin '
              '(sin cobertura real de -mlz4f)', file=sys.stderr)

    jpeg = make_jpeg(SEED)
    if jpeg is not None:
        write(d, '71_jpeg_min.bin', jpeg)
    else:
        print('aviso: Pillow (PIL) no disponible, se omite 71_jpeg_min.bin '
              '(sin cobertura real de -mpackjpg/-mbrunsli)', file=sys.stderr)

    mp3 = make_mp3(SEED)
    if mp3 is not None:
        write(d, '72_mp3_min.bin', mp3)
    else:
        print('aviso: "lame" no disponible, se omite 72_mp3_min.bin '
              '(sin cobertura real de -mpackmp3)', file=sys.stderr)

    files = sorted(os.listdir(d))
    print('corpus generado en %s: %d archivos' % (d, len(files)))
    for f in files:
        print('  %-26s %10d' % (f, os.path.getsize(os.path.join(d, f))))


if __name__ == '__main__':
    main()
