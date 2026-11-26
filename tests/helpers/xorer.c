/* Test helper for tests/regression.sh: a program for "ytool execute". */
/* xorer [in out]: XOR every byte with 0x5A. stdin->stdout with no args,
   file->file with two. Self-inverse, so the same command decodes. */
#include <stdio.h>
#include <fcntl.h>
#ifdef _WIN32
#include <io.h>
#endif
int main(int c, char **v) {
  FILE *in = stdin, *out = stdout;
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);
#endif
  if (c == 3) { in = fopen(v[1], "rb"); out = fopen(v[2], "wb"); if (!in || !out) return 2; }
  unsigned char b[65536]; size_t n;
  while ((n = fread(b, 1, sizeof b, in)) > 0) { for (size_t i = 0; i < n; i++) b[i] ^= 0x5A; fwrite(b, 1, n, out); }
  if (c == 3) { fclose(in); fclose(out); }
  return 0;
}
