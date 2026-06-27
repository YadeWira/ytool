/* tests/lzo_gen.c — genera un stream lzo1x DETERMINISTA que el scanner de ytool
 * (PrecompLZO.GetLZO1XSI) detecta de forma fiable.
 *
 * Requisitos que satisface el stream producido (ver GetLZO1XSI):
 *   - primer word != 0           (PWord(InBuff)^ = 0 -> exit)
 *   - termina en $11 $00 $00     (end-marker lzo1x; BinarySearch lo localiza)
 *   - tamano comprimido > 256    (MinSize; si no, Result nunca se pone True)
 *
 * Usa lzo1x_999_compress de liblzo2 (la MISMA familia 999 que reproduce
 * LZOProcess via lzo1x_999_compress_level con busqueda de nivel l1..l9), de modo
 * que la reproduccion bit-exacta del re-encode es alcanzable.
 *
 * Build (cabeceras no requeridas; enlazamos contra liblzo2.so.2):
 *   gcc -O2 tests/lzo_gen.c -o tests/lzo_gen -l:liblzo2.so.2
 *
 * Uso:  tests/lzo_gen <raw_len> <salida.lzo>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef unsigned long lzo_uint;
extern int lzo1x_999_compress(const unsigned char *src, lzo_uint src_len,
                              unsigned char *dst, lzo_uint *dst_len, void *wrkmem);
extern int lzo1x_decompress_safe(const unsigned char *src, lzo_uint src_len,
                                 unsigned char *dst, lzo_uint *dst_len, void *wrkmem);

/* LZO1X_999_MEM_COMPRESS = 14 * 16384 * sizeof(lzo_uint) ; holgado */
#define WRK (14 * 16384 * 8)

static uint64_t xs;
static unsigned char nb(void) { xs ^= xs << 13; xs ^= xs >> 7; xs ^= xs << 17; return (unsigned char)xs; }

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "uso: lzo_gen <raw_len> <salida.lzo>\n"); return 2; }
    int rawlen = atoi(argv[1]);
    if (rawlen < 1024) rawlen = 1024;  /* asegura comp > 256 */
    unsigned char *raw = malloc(rawlen);
    xs = 0xC0FFEEULL;  /* semilla fija -> determinista */
    /* texto semi-repetitivo: lzo encuentra matches pero el stream es de tamano util */
    const char *w[] = {"the ", "quick ", "brown ", "fox ", "jumps ", "lazy ", "dog ", "lorem "};
    int p = 0;
    while (p < rawlen) {
        const char *s = w[nb() & 7]; int l = strlen(s);
        if (p + l > rawlen) l = rawlen - p;
        memcpy(raw + p, s, l); p += l;
    }
    unsigned char *out = malloc((size_t)rawlen * 2 + 512);
    lzo_uint outlen = (lzo_uint)rawlen * 2 + 512;
    void *wrk = malloc(WRK);
    if (lzo1x_999_compress(raw, rawlen, out, &outlen, wrk) != 0) { fprintf(stderr, "compress fail\n"); return 1; }
    /* aserciones del contrato del scanner */
    if (out[0] == 0 && out[1] == 0) { fprintf(stderr, "ERR: primer word = 0\n"); return 1; }
    if (!(out[outlen-3]==0x11 && out[outlen-2]==0x00 && out[outlen-1]==0x00)) { fprintf(stderr, "ERR: sin end-marker\n"); return 1; }
    if (outlen <= 256) { fprintf(stderr, "ERR: comp <= 256\n"); return 1; }
    FILE *f = fopen(argv[2], "wb"); if (!f) { perror("fopen"); return 1; }
    fwrite(out, 1, outlen, f); fclose(f);
    fprintf(stderr, "lzo_gen: raw=%d comp=%lu (first2=%02x%02x last3=%02x%02x%02x)\n",
            rawlen, outlen, out[0], out[1], out[outlen-3], out[outlen-2], out[outlen-1]);
    return 0;
}
