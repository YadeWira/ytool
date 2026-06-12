#!/usr/bin/env python3
"""Genera un corpus sintetico y reproducible para las pruebas de regresion de ytool.

Cubre casos limite y datos con streams reales (zlib/deflate) a distintos niveles,
tamanos que cruzan el chunk de 16MB, datos incompresibles, y mezclas. Determinista
(semilla fija) para que los ratios sean comparables entre corridas.

Uso:  python3 tests/gen_corpus.py <dir_salida>
"""
import os
import sys
import zlib
import struct

SEED = 0xC0FFEE


def rng_bytes(n, seed):
    """PRNG simple y portable (xorshift64) -> bytes pseudo-aleatorios deterministas."""
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


def main():
    if len(sys.argv) < 2:
        print('uso: gen_corpus.py <dir_salida>', file=sys.stderr)
        sys.exit(2)
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)

    base_text = (b'The quick brown fox jumps over the lazy dog. '
                 b'Lorem ipsum dolor sit amet. ') * 3000

    # --- casos limite ---
    write(d, '01_empty.bin', b'')
    write(d, '02_one_byte.bin', b'\x42')
    write(d, '03_tiny_text.bin', b'hello world\n')

    # --- incompresible (no debe encontrar streams; reversibilidad pura) ---
    write(d, '10_random_2m.bin', rng_bytes(2_000_000, SEED))

    # --- altamente compresible (texto plano, sin streams pero util para ratio) ---
    write(d, '11_text_8m.bin', base_text[:8_000_000] if len(base_text) >= 8_000_000
          else base_text * (8_000_000 // len(base_text) + 1))

    # --- streams zlib/deflate reales a varios niveles, intercalados con ruido ---
    blob = bytearray()
    for i, lvl in enumerate([1, 3, 6, 9, 6, 1]):
        blob += zlib.compress(base_text[: 50000 + i * 20000], lvl)
        blob += rng_bytes(500, SEED + i)
    write(d, '20_zlib_streams.bin', bytes(blob))

    # --- muchos streams zlib pequenos (estresa el scanner/contador) ---
    many = bytearray()
    for i in range(200):
        many += zlib.compress(("payload-%d " % i).encode() * (100 + i), (i % 9) + 1)
        many += rng_bytes(64, SEED + 1000 + i)
    write(d, '21_zlib_many.bin', bytes(many))

    # --- raw deflate (sin cabecera zlib) intercalado ---
    raw = bytearray()
    co = zlib.compressobj(9, zlib.DEFLATED, -15)  # wbits negativos = raw deflate
    raw += co.compress(base_text[:80000]) + co.flush()
    raw += rng_bytes(400, SEED + 7)
    write(d, '22_raw_deflate.bin', bytes(raw))

    # --- cruza el chunk de 16MB: zlib streams dispersos en ~20MB ---
    big = bytearray()
    while len(big) < 20_000_000:
        big += zlib.compress(base_text[:30000], 6)
        big += rng_bytes(40000, SEED + len(big))
    write(d, '30_over_chunk_20m.bin', bytes(big))

    files = sorted(os.listdir(d))
    print('corpus generado en %s: %d archivos' % (d, len(files)))
    for f in files:
        print('  %-26s %10d' % (f, os.path.getsize(os.path.join(d, f))))


if __name__ == '__main__':
    main()
