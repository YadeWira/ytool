/* Single-threaded amalgamation of the public-domain LZMA SDK (Igor Pavlov)
   exposing LzmaCompress/LzmaUncompress, compiled as a static object linked
   directly into ytool (same pattern as LZ4Delphi/ZSTD4Delphi). */
#define _7ZIP_ST

/* Alloc.c's g_Alloc (the only allocator any entry point below passes in) is
   the plain malloc/free one, always available regardless of platform. Its
   BigAlloc/MidAlloc/BigFree/MidFree (VirtualAlloc-based, gated only by
   #ifdef _WIN32, no separate opt-out) are dead code here -- nothing in
   LzFind.c/LzmaEnc.c calls them, only the ISzAlloc interface we point at
   g_Alloc -- but still compiled in on Windows, pulling in a kernel32 import
   FPC's {$L}-linked-object model can't resolve (undefined __imp_VirtualAlloc/
   __imp_VirtualFree at final link). Redirecting them to malloc/free via
   macros (rather than patching the vendored file, or undefining _WIN32,
   which breaks mingw's own headers) drops that dependency entirely; they're
   unreachable anyway, so the discarded extra arguments don't matter. */
#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>
/* windows.h's own VirtualAlloc/VirtualFree prototypes are already parsed by
   this point (its include guard makes Alloc.c's later #include a no-op),
   so redefining them as macros here only rewrites the later CALL sites in
   Alloc.c's function bodies, not any declaration. */
#define VirtualAlloc(addr, size, alloctype, protect) malloc(size)
#define VirtualFree(addr, size, freetype) free(addr)
#endif
#include "Alloc.c"

#include "LzFind.c"
#include "LzmaDec.c"
#include "LzmaEnc.c"
#include "LzmaLib.c"

/* Ytool addition: LzmaCompress hardcodes writeEndMark=0, so it can never
   reproduce an "unknown size, end-marker-terminated" stream (what "xz
   --format=lzma" produces by default). Same as LzmaCompress otherwise. */
int LzmaCompressEx(unsigned char *dest, size_t *destLen, const unsigned char *src,
    size_t srcLen, unsigned char *outProps, size_t *outPropsSize,
    int level, unsigned dictSize, int lc, int lp, int pb, int fb,
    int numThreads, int writeEndMark)
{
  CLzmaEncProps props;
  LzmaEncProps_Init(&props);
  props.level = level;
  props.dictSize = dictSize;
  props.lc = lc;
  props.lp = lp;
  props.pb = pb;
  props.fb = fb;
  props.numThreads = numThreads;

  return LzmaEncode(dest, destLen, src, srcLen, &props, outProps, outPropsSize,
      writeEndMark, NULL, &g_Alloc, &g_Alloc);
}

/* Ytool addition: LzmaUncompress can't report whether decoding stopped
   because it hit the stream's own end-of-data marker or just ran out of
   the caller's output buffer -- needed to detect "unknown size" raw LZMA
   streams (what the "xz --format=lzma" CLI actually produces; it doesn't
   write the uncompressed size in the header at all). Requires the real
   end marker to be present (LZMA_FINISH_END), unlike LzmaUncompress's
   LZMA_FINISH_ANY. */
int LzmaDecodeToEndMark(unsigned char *dest, size_t *destLen,
    const unsigned char *src, size_t *srcLen,
    const unsigned char *props, size_t propsSize)
{
  ELzmaStatus status;
  SRes res = LzmaDecode(dest, destLen, src, srcLen, props, (unsigned)propsSize,
      LZMA_FINISH_END, &status, &g_Alloc);
  if (res != SZ_OK)
    return res;
  if (status != LZMA_STATUS_FINISHED_WITH_MARK)
    return SZ_ERROR_DATA;
  return SZ_OK;
}
