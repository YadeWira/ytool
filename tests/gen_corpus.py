#!/usr/bin/env python3
"""Genera un corpus sintetico y reproducible para las pruebas de regresion de ytool.

Cubre casos limite y datos con streams reales (zlib/deflate) a distintos niveles,
tamanos que cruzan el chunk de 16MB, datos incompresibles, y mezclas. Determinista
(semilla fija) para que los ratios sean comparables entre corridas.

Uso:  python3 tests/gen_corpus.py <dir_salida>
"""
import os
import shutil
import subprocess
import sys
import tempfile
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


def png_chunk(tag, data):
    return (struct.pack('>I', len(data)) + tag + data
            + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))


def make_png(w, h, seed):
    """PNG minimo valido (IHDR+IDAT+IEND, RGB 8bpc, sin filtro) para -mpng."""
    raw = bytearray()
    x = seed & 0xFFFFFFFF
    for y in range(h):
        raw.append(0)  # filter type 0 (None) por scanline
        for _ in range(w * 3):
            x = (x * 1103515245 + 12345) & 0xFFFFFFFF
            raw.append((x >> 24) & 0xFF)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    return (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', ihdr)
            + png_chunk(b'IDAT', idat) + png_chunk(b'IEND', b''))


def make_png_photo(w, h, seed):
    """PNG con estructura espacial real (gradiente + patron), no ruido, para
    -mpackpng: un codec de imagen real (WebP-lossless) solo gana sobre datos
    con correlacion; ruido puro (como make_png) lo derrota igual que a
    cualquier compresor de imagenes, dando fallback trivial sin cobertura
    real. 61_png_min.bin (make_png) sigue sin tocarse, sirve para -mpng."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (None) por scanline
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
    """Frame LZ4 real (magic 0x184D2204) via el modulo python 'lz4', si esta disponible."""
    try:
        import lz4.frame
    except ImportError:
        return None
    text = (b'lz4 frame payload %d ' % seed) * 4000
    return lz4.frame.compress(text)


def make_jpeg(seed):
    """JPEG baseline real (no progresivo) via Pillow, si esta disponible."""
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
    """MP3 CBR real via 'lame' (CLI externa), si esta disponible."""
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

    # --- PNG minimo (IHDR/IDAT/IEND): ejercita el codec -mpng (detecta el
    #     contenedor PNG, no solo el deflate crudo que ya cubre 20_zlib_streams.bin) ---
    write(d, '61_png_min.bin', make_png(24, 24, SEED))

    # --- PNG con estructura espacial real (gradiente): ejercita -mpackpng
    #     (packPNG/WebP-lossless) de verdad -- ruido puro como make_png() no
    #     sirve, ningun codec de imagen gana sobre datos sin correlacion ---
    write(d, '62_png_photo.bin', make_png_photo(48, 48, SEED))

    # --- Los siguientes 3 son OPCIONALES: requieren una herramienta externa
    #     presente en la maquina que genera el corpus (no en runtime de ytool).
    #     Si falta, simplemente no se escribe el archivo y el metodo correspondiente
    #     (-mlz4f/-mpackjpg+-mbrunsli/-mpackmp3 en regression.sh) corre igual pero
    #     sin encontrar el stream real -> reversible trivial, cobertura de codec = 0
    #     para esa corrida (mismo criterio ya usado con 50_lzo1x.bin/gcc+liblzo2).
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
