/* Shim de nombre-de-archivo: mingw-w64 trae "shobjidl.h" en minuscula (correcto en
   Windows real, case-insensitive); el fuente de srep (Compression/Common.cpp) pide
   <ShObjIdl.h> en PascalCase, que solo importa al cross-compilar desde un filesystem
   case-sensitive como Linux. No se toca el fuente de srep; se agrega este directorio
   al include path (despues de los de srep) para resolver el nombre exacto. */
#include <shobjidl.h>
