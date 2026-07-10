/* Single-threaded amalgamation of the public-domain LZMA SDK (Igor Pavlov)
   exposing LzmaCompress/LzmaUncompress, compiled as a static object linked
   directly into ytool (same pattern as LZ4Delphi/ZSTD4Delphi). */
#define _7ZIP_ST
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
