/* Test helper for tests/regression.sh: a toy run-length codec used as a plugin
   codec (INI + ytool.ini) in its three forms: stdin/stdout, files, and the
   persistent <library> protocol. */
/* rle c|d [in out]: toy run-length codec. c: (count 1..255, byte) pairs.
   stdin->stdout with one arg, file->file with three. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#ifdef _WIN32
#include <io.h>
#endif
/* "L c|d": the persistent "library" protocol ytool/xtool speak for <library>
   codecs: per request Int32 insize, Int32 outsize, insize bytes; reply Int32
   size, then that many bytes. */
static int lib(int compress) {
  for (;;) {
    int in, out;
    if (fread(&in, 4, 1, stdin) != 1 || fread(&out, 4, 1, stdin) != 1) return 0;
    unsigned char *b = malloc(in > 0 ? in : 1), *o = malloc(compress ? 2 * (size_t)in + 2 : (size_t)out + 1);
    if (fread(b, 1, in, stdin) != (size_t)in) return 5;
    int n = 0;
    if (compress) { int i = 0; while (i < in) { int j = i; while (j < in && b[j] == b[i] && j - i < 255) j++; o[n++] = j - i; o[n++] = b[i]; i = j; } }
    else { for (int i = 0; i + 1 < in; i += 2) for (int k = 0; k < b[i]; k++) { if (n >= out) { n = -1; break; } o[n++] = b[i + 1]; } }
    fwrite(&n, 4, 1, stdout); if (n > 0) fwrite(o, 1, n, stdout); fflush(stdout);
    free(b); free(o);
  }
}
int main(int c, char **v) {
  if (c < 2) return 2;
  if (v[1][0] == 'L') {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);
#endif
    return lib(v[2][0] == 'c');
  }
  FILE *in = stdin, *out = stdout;
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);
#endif
  if (c == 4) { in = fopen(v[2], "rb"); out = fopen(v[3], "wb"); if (!in || !out) return 3; }
  int ch;
  if (v[1][0] == 'c') {
    int prev = -1, n = 0;
    while ((ch = fgetc(in)) != EOF) {
      if (ch == prev && n < 255) { n++; continue; }
      if (n) { fputc(n, out); fputc(prev, out); }
      prev = ch; n = 1;
    }
    if (n) { fputc(n, out); fputc(prev, out); }
  } else {
    int n;
    while ((n = fgetc(in)) != EOF) { ch = fgetc(in); if (ch == EOF) return 4; while (n--) fputc(ch, out); }
  }
  if (c == 4) { fclose(in); fclose(out); }
  return 0;
}
