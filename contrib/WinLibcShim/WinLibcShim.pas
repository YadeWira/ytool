unit WinLibcShim;

// The static i386-win32 objects for zstd/xxHash/lz4 (built with
// i686-w64-mingw32-gcc, see build-native-windows-x86.sh) call a handful of
// plain C runtime symbols internally (memset/memcpy/memmove for bulk copies,
// malloc/calloc/free for zstd's default allocator, plus GCC's own stack-probe
// helper for large stack frames on Windows). FPC's i386-win32 RTL does not
// export any of these under their C names, unlike x86-64 where the same
// static objects apparently never need them (or FPC's win64 RTL already
// happens to provide them) -- so this unit supplies them.
//
// memset/memcpy/memmove/malloc/calloc/free are plain Pascal wrappers here
// (no dependency on msvcrt.dll import stubs, which would have pulled in a
// whole import-table "head" object from libmsvcrt.a transitively). __alloca/
// ___chkstk cannot be reimplemented in Pascal (it adjusts ESP directly using
// an ad-hoc register calling convention, not a normal call), so chkstk.x86.o
// is the real object extracted from i686-w64-mingw32's own libgcc.a.
//
// `public name` is NOT auto-decorated by FPC on i386-win32 (unlike
// `external`, which always gets an extra leading underscore prepended --
// verified empirically, see contrib/build-native-windows-x86.sh comments),
// so the leading underscore below must be written explicitly to match the
// symbol names the C objects actually reference.

interface

implementation

{$IFDEF WIN32}

{$L chkstk.x86.o}
// ___chkstk_ms: the stack probe current mingw emits (zstd/lz4 objects rebuilt
// from source in 0.9.9a); chkstk.x86.o above covers the older __alloca.
{$L chkstk_ms.x86.o}
// GCC's compiler-rt-style 64-bit arithmetic helpers: i386 has no native
// 64-bit divide/modulo/shift instructions, so any C code doing Int64/UInt64
// division, modulo, or shifts by a non-constant amount (xxHash/zstd do
// plenty of both) compiles down to calls to these.
{$L udivdi3.x86.o}
{$L divdi3.x86.o}
{$L umoddi3.x86.o}
{$L moddi3.x86.o}
{$L ctzdi2.x86.o}   // lz4 with a 64-bit reg_t (0.9.9f)
{$L ashldi3.x86.o}
{$L ashrdi3.x86.o}
{$L lshrdi3.x86.o}

function ShimMemSet(dst: Pointer; c: Integer; n: NativeUInt): Pointer; cdecl;
  public name '_memset';
begin
  FillChar(dst^, n, Byte(c));
  Result := dst;
end;

// memcmp: lzo (0.9.9f, built in) compares with it
function ShimMemCmp(a, b: Pointer; n: NativeUInt): Integer; cdecl;
  public name '_memcmp';
var
  i: NativeUInt;
begin
  Result := 0;
  i := 0;
  while i < n do
  begin
    if PByte(a)[i] <> PByte(b)[i] then
      exit(Integer(PByte(a)[i]) - Integer(PByte(b)[i]));
    Inc(i);
  end;
end;

function ShimMemCpy(dst, src: Pointer; n: NativeUInt): Pointer; cdecl;
  public name '_memcpy';
begin
  Move(src^, dst^, n);
  Result := dst;
end;

function ShimMemMove(dst, src: Pointer; n: NativeUInt): Pointer; cdecl;
  public name '_memmove';
begin
  Move(src^, dst^, n);
  Result := dst;
end;

function ShimMalloc(n: NativeUInt): Pointer; cdecl; public name '_malloc';
begin
  if n = 0 then n := 1;
  GetMem(Result, n);
end;

function ShimCalloc(count, size: NativeUInt): Pointer; cdecl;
  public name '_calloc';
var
  total: NativeUInt;
begin
  total := count * size;
  if total = 0 then total := 1;
  Result := AllocMem(total);
end;

procedure ShimFree(p: Pointer); cdecl; public name '_free';
begin
  if p <> nil then FreeMem(p);
end;

// LZMA SDK 21+ (Alloc.c's MyRealloc). C semantics: realloc(nil, n) allocates,
// realloc(p, 0) frees and returns nil; ReAllocMem does both.
function ShimRealloc(p: Pointer; n: NativeUInt): Pointer; cdecl;
  public name '_realloc';
begin
  Result := p;
  ReAllocMem(Result, n);
end;

{$ENDIF}

end.
