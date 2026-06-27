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

    # --- streams DUPLICADOS: ejercita el dedup (-dd): N distintos x R copias ---
    # cada copia identica del mismo stream zlib -> StoreDD las deduplica. Cubre el
    # path DD de encode (DDInfo1/DDList1/DDInfo2) y de decode (DDList2 + cache de dups).
    dup = bytearray()
    for i in range(30):
        s = zlib.compress(base_text[: 4000 + i * 137], 6)
        for _ in range(3):
            dup += s
            dup += rng_bytes(48, SEED + 5000 + i)  # ruido separador (igual por i)
    write(d, '23_dup_streams.bin', bytes(dup))

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

    # --- WAV PCM (RIFF): ejercita los codecs de audio (flac/wavpack detectan RIFF,
    #     decodifican a PCM y recomprimen lossless; restore reproduce el WAV exacto) ---
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

    files = sorted(os.listdir(d))
    print('corpus generado en %s: %d archivos' % (d, len(files)))
    for f in files:
        print('  %-26s %10d' % (f, os.path.getsize(os.path.join(d, f))))


if __name__ == '__main__':
    main()
