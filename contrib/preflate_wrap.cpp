// Wrapper C que expone decode/reencode con la firma que espera el plugin
// preflate_dll de xtool (imports/PreflateDLL.pas), puenteando a la API de
// vectores de preflate upstream.
#include <vector>
#include <cstring>
#include <cstdint>
#include "preflate_decoder.h"
#include "preflate_reencoder.h"

#define EXPORT extern "C" __attribute__((visibility("default")))

// decode: deflate (src) -> dst1 = datos crudos, dst2 = info de reconstruccion.
// *dst1Capacity / *dst2Capacity entran como capacidad y salen como tamano real.
EXPORT bool decode(const void* src, int srcSize, void* dst1, int* dst1Capacity,
                   void* dst2, int* dst2Capacity) {
  if (srcSize < 0) return false;
  std::vector<unsigned char> deflate_raw(
      (const unsigned char*)src, (const unsigned char*)src + srcSize);
  std::vector<unsigned char> unpacked, diff;
  if (!preflate_decode(unpacked, diff, deflate_raw)) return false;
  if ((int)unpacked.size() > *dst1Capacity) return false;
  if ((int)diff.size() > *dst2Capacity) return false;
  if (!unpacked.empty()) memcpy(dst1, unpacked.data(), unpacked.size());
  if (!diff.empty()) memcpy(dst2, diff.data(), diff.size());
  *dst1Capacity = (int)unpacked.size();
  *dst2Capacity = (int)diff.size();
  return true;
}

// reencode: src1 = datos crudos, src2 = info de reconstruccion -> dst = deflate
// original (reconstruccion bit-exacta). *dstCapacity entra capacidad, sale tamano.
EXPORT bool reencode(const void* src1, int src1Size, const void* src2,
                     int src2Size, void* dst, int* dstCapacity) {
  if (src1Size < 0 || src2Size < 0) return false;
  std::vector<unsigned char> unpacked(
      (const unsigned char*)src1, (const unsigned char*)src1 + src1Size);
  std::vector<unsigned char> diff(
      (const unsigned char*)src2, (const unsigned char*)src2 + src2Size);
  std::vector<unsigned char> deflate_raw;
  if (!preflate_reencode(deflate_raw, diff, unpacked)) return false;
  if ((int)deflate_raw.size() > *dstCapacity) return false;
  if (!deflate_raw.empty()) memcpy(dst, deflate_raw.data(), deflate_raw.size());
  *dstCapacity = (int)deflate_raw.size();
  return true;
}
