// Wrapper C que expone la API brunsli_* que espera el plugin brunsli.dll de ytool
// (imports/BrunsliDLL.pas), puenteando a la API C++ de Google brunsli.
#include <cstdint>
#include <cstddef>
#include "brunsli/jpeg_data.h"
#include "brunsli/jpeg_data_reader.h"
#include "brunsli/jpeg_data_writer.h"
#include "brunsli/brunsli_encode.h"
#include "brunsli/brunsli_decode.h"
#include "brunsli/status.h"

using brunsli::JPEGData;
using brunsli::JPEGOutput;

#define EXPORT extern "C" __attribute__((visibility("default")))

EXPORT void* brunsli_alloc_JPEGData() { return new JPEGData(); }
EXPORT void  brunsli_free_JPEGData(void* p) { delete reinterpret_cast<JPEGData*>(p); }

// lee un JPEG en el JPEGData (mode JPEG_READ_ALL). Devuelve 1/0.
EXPORT int brunsli_ReadJpeg(void* p, void* data, int len) {
  return brunsli::ReadJpeg((const uint8_t*)data, (size_t)len,
                           brunsli::JPEG_READ_ALL,
                           reinterpret_cast<JPEGData*>(p)) ? 1 : 0;
}

EXPORT int brunsli_GetMaximumEncodedSize(void* p) {
  return (int)brunsli::GetMaximumBrunsliEncodedSize(*reinterpret_cast<JPEGData*>(p));
}

// codifica el JPEGData a brunsli en data (capacidad len). Devuelve el tamano real, 0 si falla.
EXPORT int brunsli_EncodeJpeg(void* p, void* data, int len) {
  size_t l = (size_t)len;
  if (!brunsli::BrunsliEncodeJpeg(*reinterpret_cast<JPEGData*>(p),
                                  (uint8_t*)data, &l))
    return 0;
  return (int)l;
}

// decodifica un stream brunsli en el JPEGData. Devuelve BrunsliStatus (BRUNSLI_OK=0).
EXPORT int brunsli_DecodeJpeg(void* p, void* data, int len) {
  return (int)brunsli::BrunsliDecodeJpeg((const uint8_t*)data, (size_t)len,
                                         reinterpret_cast<JPEGData*>(p));
}

// JPEGOutput envuelve un callback (data,buf,len)->size_t. Lo asigna en heap.
EXPORT void* brunsli_alloc_JPEGOutput(brunsli::JPEGOutputHook cb, void* data) {
  return new JPEGOutput(cb, data);
}
EXPORT void brunsli_free_JPEGOutput(void* p) { delete reinterpret_cast<JPEGOutput*>(p); }

// reconstruye el JPEG desde el JPEGData escribiendolo via el JPEGOutput. 1/0.
EXPORT int brunsli_WriteJpeg(void* p, void* oup) {
  return brunsli::WriteJpeg(*reinterpret_cast<JPEGData*>(p),
                            *reinterpret_cast<JPEGOutput*>(oup)) ? 1 : 0;
}
