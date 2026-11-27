# ytool 1.0.0: nota de planificación

Borrador del 2026-11-27, escrito sobre la 0.9.9e. Es una propuesta para que Wira decida qué entra;
nada de esto está comprometido todavía. Las prioridades marcadas como suyas vienen de lo que él pidió.

**Decidido por Wira (2026-11-27): la 1.0.0 es el congelamiento del formato.** Lo que tenga que cambiar
el `.ytp` (zpaq-std, la variante de biblioteca por stream) entra antes de 1.0.0 o espera a un formato
nuevo; las features que no tocan el formato pueden seguir en 1.x.

Entran también, por pedido de Wira: **trabajar con carpetas** (punto 2), **descomprimir solo con el
binario** (punto 3), un **formato nuevo que sigue leyendo los `.ytp` de 0.9.9x** (punto 4) y
**mejorar el formato de los plugins** (punto 5).

## Qué significaría "1.0.0"

La serie 0.9.9x fue de recreación (xtool 0.7.9 → 0.9.9 en abierto) y luego de corrección. Una 1.0.0
debería prometer estabilidad, no solo sumar features:

- **Formato congelado.** Todo `.ytp` hecho con 1.0.0 decodifica con cualquier 1.x. Hoy el contenedor
  es XTP2 (desde 0.9.9b) y los números de codec no se mueven (los nuevos se agregan al final), pero
  no hay una prueba que lo garantice: faltan archivos de referencia por versión (ver más abajo).
- **Línea de comandos estable.** Comandos y opciones documentados que no cambian de significado en 1.x.
  La 0.9.9e ya rechaza comandos y archivos inexistentes y avisa de opciones desconocidas.
- **Plataformas declaradas y probadas:** Linux x86/x64 y Windows x86/x64 (Windows 7 o posterior).
- **Datos dañados siempre fallan** con un mensaje (fuzzing del decodificador desde 0.9.9d).

## Candidatos a entrar

### 1. zpaq-std como compresor final (prioridad de Wira)

Es la razón por la que se pospusieron los plugins de juegos. ytool usaría zpaq-std como etapa final
sobre el flujo ya precomprimido, como hoy `-l#` (fast-lzma2) o `-e` (programa externo).

- **Formato:** un valor nuevo del byte `Compressed` del `.ytp`, que hoy vale 0 (nada), 1 (fast-lzma2)
  o 2 (`-e`).
- **Biblioteca:** la prepara el agente zpaq-std, con
  `zpaqstd_run(argc, argv, in, out, err)` y `zpaqstd_version()`, cdecl. Se enchufa con
  `TProcessStream.RegisterInProcess`, igual que libsrep.
- **Requisitos que le pasé:** flujo ZPAQ estándar, secuencial (sin seek), bit-exacto y determinista;
  runtime estático en Windows; probado con muchas llamadas en un mismo proceso bajo LSan.
- **Estado (2026-11-27):** hay un prototipo para Linux x64 en
  `/mnt/IA_LAB/agentes/ZPAQ-STD/int/lib219/`, todavía no estable. Faltan Windows x64/x86, Linux x86,
  los `-ma` y el decode multihilo.
- **Por decidir:** nombre de la opción (`-z#`, `-mz`…), si se distribuye la biblioteca en los
  paquetes, y si reemplaza a fast-lzma2 por defecto o queda como alternativa.

### 2. Trabajar con carpetas (pedido de Wira, 2026-11-27)

Hoy ytool se usa con archivos. Por debajo ya existe algo heredado de xtool: `precomp` acepta una carpeta
(`TDirInputStream`) y `decode` a una carpeta existente la reconstruye (`TDirOutputStream`). Probado en
Linux: una carpeta con subcarpetas vuelve idéntica (`diff -r`). Pero no está a la altura de una 1.0.0:

- **Formato mínimo y sin marca.** Por archivo: longitud del nombre (Integer), nombre relativo, tamaño
  (Int64) y datos, todo dentro del flujo que se precomprime. Nada dice que el `.ytp` contiene una
  carpeta: `decode` a una ruta que no existe escribe **un solo archivo** con todo concatenado, sin aviso.
- **Separador del sistema en los nombres.** Una carpeta comprimida en Windows guarda `sub\b.bin`; en
  Linux eso sería un nombre de archivo con barra invertida, no una subcarpeta. Y la codificación de
  los nombres (UTF-8 o ANSI) no está definida: los nombres no ASCII no son portables.
- **Se pierde:** las carpetas vacías, las fechas de modificación y los permisos o atributos.
  Una carpeta de entrada vacía da "No file name specified".
- **Windows:** sin probar (Wira lo ve como "solo archivos").

Como el formato de carpeta viaja dentro del `.ytp`, **hay que rediseñarlo antes de congelar**:

- una marca en la cabecera (archivo o carpeta);
- nombres en UTF-8 con `/` como separador;
- entradas para carpetas vacías;
- fecha de modificación y atributos básicos;
- que `decode` cree la carpeta de salida si no existe y que se niegue a escribir fuera de ella
  (rutas con `..` o absolutas en un `.ytp` dañado o malicioso).

A decidir: si `precomp` acepta varias entradas (`ytool precomp a.bin carpeta/ salida.ytp`), y si hace
falta listar o extraer un solo archivo de un `.ytp` de carpeta.

### 3. Descomprimir solo con el binario, sin plugins ni bibliotecas (pedido de Wira, 2026-11-27)

Al estilo de zpaq: un solo ejecutable que restaura cualquier `.ytp` sin nada al lado. Hoy no es así:
restaurar un stream es **volver a comprimirlo** con la misma biblioteca que lo produjo, así que
`decode` carga en tiempo de ejecución una biblioteca por codec:

| Codec | Biblioteca que carga hoy (Linux / Windows) |
|---|---|
| zlib | `libz.so.1` **del sistema** / `zlib1.dll` |
| libdeflate, lzip | `libdeflate`, `liblz` / `lzlib.dll` |
| preflate (`-mpreflate`, `-mpng`) | `libpreflate` / `preflate_dll.dll` (C++) |
| lz4, zstd, lzo | `liblz4`, `libzstd`, `liblzo2` |
| pja, brunsli (JPEG) | `libpja`, `libbrunsli` (C++) |
| FLAC, WavPack | `libFLAC`, `libwavpack` |
| `-l#` (fast-lzma2) | `libfast-lzma2` |
| `-ddo`, `-dd1`..`-dd5` | los programas `osrep` / `srep` (o `libsrep`) |

**Por qué importa además de la comodidad.** En Linux, zlib es la del sistema. Una distribución con
otra zlib (zlib-ng en modo compatible, por ejemplo) puede escribir otros bytes y dejar streams sin
restaurar. Compilar las bibliotecas **dentro** del binario fija sus versiones y quita ese riesgo.

**Cómo:**
- Enlazar estáticamente las bibliotecas de C (zlib, libdeflate, lzlib, lz4, zstd, lzo, FLAC, WavPack,
  fast-lzma2) como objetos o `.a`, compiladas desde las mismas fuentes fijadas en
  `contrib/pin-repo.sh`. Ya se hace con partes de lz4, zstd y LZMA.
- Las de C++ (preflate, pja, brunsli) necesitan libstdc++ estática dentro de un programa FPC: viable en
  Linux; en Windows (mingw + FPC: excepciones, TLS) hay que probarlo. Si no resulta, quedan como
  plugin con el resto adentro.
- Revisar que todas las licencias permitan distribuirlas dentro de un mismo binario.
- Los plugins externos siguen sirviendo para codecs nuevos o de terceros.

**Lo que no puede ir adentro:**
- **srep** (`-dd1`..`-dd5`), por su licencia ("All rights reserved"). Un `.ytp` con `-dd1`..`-dd5`
  seguirá necesitando srep al lado. `-dd`, que es interno, no.

**OSREP se integra en ytool para 1.0.0 (decidido por Wira, 2026-11-27).** Hoy `osrep` 0.0.18 viaja en
los paquetes como programa aparte y ytool lo lanza por tuberías para `-ddo`. En 1.0.0 va dentro del
binario (licencia MIT), y `-ddo` deja de necesitar nada al lado. Camino: una biblioteca de omega-srep
con la forma de libsrep (`run(argc, argv, in, out, err)`), enlazada estáticamente; pedida a su agente
por aim el 2026-11-27. El formato de sus datos dentro del `.ytp` no cambia: los `.ytp` con `-ddo` de
0.9.9x siguen decodificando.
- **Oodle** (propietario), y **`-e`** (un programa externo, por definición).

**Toca el formato (antes de congelar):** conviene que el `.ytp` registre la versión de cada biblioteca
usada. Así `decode` puede decir antes de empezar "este archivo necesita srep" o "se hizo con zstd
1.5.2 y aquí hay otra", en vez de fallar a la mitad.

**A decidir:**
- si es el mismo `ytool` el que lleva todo adentro, o además un `ytool-dec` chico solo para
  descomprimir;
- cuánto puede crecer el ejecutable (unos MB más por las bibliotecas).

### 4. Formato nuevo, que sigue leyendo los `.ytp` de 0.9.9x (pedido de Wira, 2026-11-27)

La 1.0.0 escribe un **contenedor nuevo**, el que se congela, y sigue **leyendo y descomprimiendo**
los `.ytp` de ytool 0.9.9a–0.9.9e: XTP1 (0.9.9a) y XTP2 (0.9.9b en adelante). No incluye los `.pmp`
de xtool: sigue decidido no ser compatible con xtool.

**Por qué un formato nuevo y no seguir con XTP2:** los puntos 1, 2, 3, 5 y 7 necesitan campos que XTP2
no tiene. Es mejor reunirlos en un único cambio, revisado una vez, que en varios XTP sucesivos:
- el compresor final zpaq-std (un valor nuevo del byte `Compressed`);
- una carpeta como entrada: marca, nombres UTF-8 con `/`, carpetas vacías, fechas y atributos;
- la versión de cada biblioteca usada;
- si entra, la variante de biblioteca por stream;
- una versión de formato explícita en la cabecera, para que un ytool viejo ante un archivo nuevo
  pueda decir "hace falta ytool 1.x" en vez de "Unrecognized .ytp format".

El diseño se escribe antes de implementarlo, en `Precomp-File-Format` de la wiki. Así se revisa como
especificación y no solo como código.

**Leer los 0.9.9x no es solo leer su contenedor.** Restaurar un stream de 0.9.9x exige **las mismas
versiones de biblioteca** que lo produjeron. Si la 1.0.0 sube una biblioteca (por ejemplo zstd 1.5.2 →
1.5.7, o lz4), los `.ytp` viejos con esos streams dejan de restaurarse. Por eso, o la 1.0.0 conserva
las versiones de 0.9.9x, o lleva las dos (vieja para leer, nueva para escribir), que es exactamente el
punto 7. Esto también decide qué versiones se enlazan dentro del binario (punto 3).

**Cómo se garantiza:**
- **Archivos de referencia** en `tests/golden/`: un `.ytp` por codec y por modo (`-dd`, `-l#`, varios
  bloques), hechos con los binarios **publicados** de 0.9.9a, 0.9.9b, 0.9.9c, 0.9.9d y 0.9.9e (bajados de
  las releases de GitHub, no recompilados), con el original de cada uno. La suite los decodifica en
  cada build, en Linux y en Windows, x64 y x86. srep-builds ya lo hace con sus archivos.
- Lo mismo para el formato 1.0.0 en cuanto exista: desde ahí, cada 1.x tiene que decodificar los
  archivos de la 1.0.0.
- El fuzz del decodificador también para los contenedores viejos.

**Lo que ya no restaura en 0.9.9x tampoco lo hará en 1.0.0:** streams packJPG, packPNG y packMP3 de
pre-releases anteriores a 0.9.9a (sus codecs se quitaron), y lo listado en Known Issues ("0.9.9a library
baseline"). Habrá que dejarlo explícito en las notas de la 1.0.0.

### 5. Mejorar el formato de los plugins (acordado con Wira, 2026-11-27)

Hoy hay cuatro tipos, heredados de xtool y sin especificar:
- **de biblioteca**: una DLL/`.so` con la API binaria de xtool, sin documentar ni versionar;
- **INI** de streams, en dos dialectos parecidos (`Stream1` en `PrecompINI.pas`, `StreamList1` en
  `PrecompINIEx.pas`);
- **EXE**: `Encode=`/`Decode=` con marcadores `<stdin>`/`<stdout>` (`PrecompEXE.pas`);
- bases **`.xtl`** de `generate`.

Problemas:
- el `.ytp` guarda solo el **nombre** del método: si el plugin cambia por debajo, el archivo deja de
  restaurarse sin aviso;
- los INI no tienen versión ni validación (una clave mal escrita se ignora);
- la API de biblioteca no tiene versión;
- no hay forma de comprobar si un plugin es reversible antes de usarlo.

Propuesta:
1. **Lo que toca el formato, obligatorio para 1.0.0:** el `.ytp` registra identidad y versión de cada
   plugin usado, quizá con un hash, y `decode` avisa antes de empezar si falta o no coincide. Es lo
   mismo que las versiones de biblioteca del punto 3.
2. **Un solo manifiesto documentado y versionado** que reemplace los dos dialectos INI y el EXE, con
   errores ante claves desconocidas. Los INI actuales se siguen leyendo.
3. **Una API de biblioteca en C, estable y versionada**, con un plugin de ejemplo mínimo.
4. **Un comando de prueba** (`ytool plugin-test <plugin> <muestra>`) que haga el ida y vuelta y diga
   si el plugin es reversible.

El punto 1 entra en 1.0.0. Los puntos 2 a 4 pueden ir en 1.0.0 o en 1.1, pero **antes de los plugins
de juegos** (punto 6), que serían sus primeros usuarios.

### 6. Plugins de formatos de juegos (pospuestos por Wira)

Después de zpaq-std. Desde cero y en abierto (Unity, Unreal `.pak`, BSA/BA2, PSARC, Paradox…), con
especificaciones públicas y caja negra; nunca descompilando los DLL de XTool_2020_Archive. El material de
prueba son los repacks de Wira en `/mnt/OSR_D1`: solo lectura, se copian antes de usarse y no se
comparten. Puede quedar para una 1.1 si 1.0.0 se centra en estabilidad.

### 7. Selección de variante de biblioteca

`-mzstd=zstd147` al estilo de xtool: varias versiones de lz4/zstd para reproducir streams de distintos
productores (lz4 1.9.4 y 1.10 escriben bytes distintos al mismo nivel). Hoy `-lz4`/`-zstd` repetibles
solo ordenan intentos. Exige un byte de variante por stream: hay que definirlo **antes** de congelar el
formato.

### 8. Sucesores de packPNG y packMP3

PPA (PNG) y PMPA (MP3/MP2) entran cuando sean estables; sus números de codec están reservados.

### 9. Lo que falta de xtool 0.9.9

- `-cfg<codec>` con el significado de cada clave (hoy implementado lo que se pudo medir).
- El comando `brute` de 0.9.9 (semántica desconocida). Decidir si se investiga o se descarta.

### 10. Detalles pendientes ya identificados

- **`-dd` reserva unos 1,7 GB:** ytool le pasa los datos a srep por stdin sin `-s<tamaño>`, y srep
  dimensiona sus tablas para 25 GB. Pasarle el tamaño cuando se conoce.
- ~~**Wiki:** la sección "Windows x86 cannot decode some 64-bit `.ytp` files (lz4 fast mode)" de Known
  Issues quedó vieja: se arregló en 0.9.9b (commit aa32bd3).~~ Hecho en la wiki con la 0.9.9e.
- **CI:** el de Windows compila sin las DLL de plugins (los codecs pasan por 0 streams). Sumar las DLL
  y un fuzz corto, como en srep-builds.
- **Rendimiento:** no hay benchmarks publicados (Known Issues). Publicar números de un corpus fijo
  antes de 1.0.0.

## Fuera de alcance (no entran)

- **Oodle:** propietario. El cargador sigue listo para quien aporte su propia biblioteca.
- **TAK, ogg/vorbis/opus, bink, wwise:** no existe un encoder abierto que reproduzca sus flujos.
- **gdeflate, jojpeg, reflate:** quitados a propósito (ver Known Issues).
- **Compatibilidad con los `.pmp` de xtool:** decidido que no (formato propio desde 0.9.9a).
- **GUI.**
- **Distribuir srep (programa o biblioteca):** "All rights reserved"; sigue aparte en srep-builds.

## Criterios para publicar 1.0.0

- [ ] Lo que Wira elija de "Candidatos" terminado y documentado.
- [ ] Formato nuevo congelado y especificado; archivos de referencia de 0.9.9a–e y de 1.0.0 en
      `tests/golden/`, decodificados en cada build y en las cuatro plataformas.
- [ ] Suite de regresión estricta en Linux x64 y x86, y smoke en Windows 10 y 7, x64 y x86.
- [ ] Fuzz del decodificador (10.000 casos) y del codificador sin hallazgos.
- [ ] Ayuda, README y wiki al día; ningún problema conocido abierto que pierda datos.

## Preguntas para Wira

1. ~~¿1.0.0 es "estable" o "con zpaq-std y plugins"?~~ Respondida: congelamiento del formato.
2. ¿zpaq-std reemplaza a fast-lzma2 como compresor por defecto o queda opcional?
3. ¿La selección de variante de biblioteca entra antes de congelar el formato o se descarta?
4. ¿Hay fecha objetivo?
