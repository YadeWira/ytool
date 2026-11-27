unit PrecompHelp;

// precomp's and decode's help. A unit of its own because it asks each codec
// library whether it loaded, and their units all export the same names
// (DLLLoaded, Init...), which would shadow each other inside PrecompMain.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

type
  // A codec analyze can try: its -m name, the streams it competes for (one
  // codec per group ends up in a recommendation), and whether its library
  // loaded.
  TCodecInfo = record
    Name, Group: string;
    Available: Boolean;
    Lib: string; // the library it needs next to ytool ('' = built in)
  end;

procedure PrecompPrintHelp;
procedure DecodePrintHelp;
function CodecTable: TArray<TCodecInfo>;
// '' when the codec works here (or is not one of the table's); else the
// library it is missing. 0.9.9f: decode says so before it starts.
function CodecMissingLib(const Name: string): string;
// One help line: an option, padded, and what it does.
procedure HelpOption(const Opt, Text: string; const Default: string = '');
procedure HelpSection(const Title: string);

implementation

uses
  SysUtils, Utils, CliUI,
  ZLibDLL, PreflateDLL, LibDeflateDLL, LZlibDLL, LZ4DLL, LZODLL, ZSTDDLL, OodleDLL, FLACDLL,
  WavPackDLL, BrunsliDLL, PJADLL, FLZMA2DLL;

const
  OPT_WIDTH = 20;

procedure HelpSection(const Title: string);
begin
  WriteLine('');
  WriteLine(UIBold(Title));
end;

procedure HelpOption(const Opt, Text: string; const Default: string = '');
var
  S: string;
begin
  S := '  ' + UIPad(UICyan(Opt), OPT_WIDTH) + ' ' + Text;
  if Default <> '' then
    S := S + ' ' + UIDim('[' + Default + ']');
  WriteLine(S);
end;

var
  Missing: Boolean;

function Codec(const Name: string; Available: Boolean): string;
begin
  if Available then
    Result := Name
  else
  begin
    Result := UIDim(Name + '*');
    Missing := True;
  end;
end;

procedure CodecRow(const Group: string; const Names: array of string;
  const Available: array of Boolean);
var
  I: Integer;
  S: string;
begin
  S := '  ' + UIPad(Group, 12);
  for I := Low(Names) to High(Names) do
    S := S + Codec(Names[I], Available[I]) + '  ';
  WriteLine(TrimRight(S));
end;

procedure PrecompPrintHelp;
begin
  WriteLine(UIBold('precomp') + ' - find compressed streams and unpack them');
  WriteLine('');
  WriteLine('Usage: ytool precomp [options] input output');
  WriteLine('');
  WriteLine('  Finds the compressed streams inside input (deflate, JPEG, zstd, lz4...),');
  WriteLine('  unpacks them and writes output, which a general compressor packs better.');
  WriteLine('  ''ytool decode'' rebuilds input from it byte for byte. input or output');
  WriteLine('  can be - (stdin, stdout).');

  HelpSection('Examples');
  WriteLine('  ytool precomp -mzlib+zstd+pja game.pak game.ytp');
  WriteLine('  ytool precomp -mpreflate+png -t8 -dd -l9 data.bin data.ytp');
  WriteLine('  ytool decode game.ytp game.pak');

  Missing := False;
  HelpSection('Codecs (-m, several joined with +)');
  CodecRow('deflate', ['zlib', 'libdeflate', 'preflate', 'png'],
    [ZLibDLL.DLLLoaded, LibDeflateDLL.DLLLoaded, PreflateDLL.DLLLoaded,
    ZLibDLL.DLLLoaded or PreflateDLL.DLLLoaded]);
  CodecRow('JPEG', ['pja', 'brunsli'], [PJADLL.DLLLoaded,
    BrunsliDLL.DLLLoaded]);
  CodecRow('lz4', ['lz4', 'lz4hc', 'lz4f'], [LZ4DLL.DLLLoaded,
    LZ4DLL.DLLLoaded, LZ4DLL.DLLLoaded]);
  CodecRow('zstd', ['zstd'], [ZSTDDLL.DLLLoaded]);
  CodecRow('lzo', ['lzo1x', 'lzo1c', 'lzo2a'], [LZODLL.DLLLoaded,
    LZODLL.DLLLoaded, LZODLL.DLLLoaded]);
  CodecRow('lzma', ['lzma', 'lzip'], [True, LZlibDLL.DLLLoaded]);
  CodecRow('audio', ['flac', 'wavpack'], [FLACDLL.DLLLoaded,
    WavPackDLL.DLLLoaded]);
  CodecRow('Oodle', ['kraken', 'mermaid', 'selkie', 'hydra', 'leviathan',
    'lzna'], [OodleDLL.DLLLoaded, OodleDLL.DLLLoaded, OodleDLL.DLLLoaded,
    OodleDLL.DLLLoaded, OodleDLL.DLLLoaded, OodleDLL.DLLLoaded]);
  if Missing then
    WriteLine('  ' + UIYellow('*') +
      ' library not found next to ytool: that codec does nothing');
  WriteLine('  Also plugins (.ini, .dll/.so, programs) from ytool''s folder, by name.');

  HelpSection('Scanning');
  HelpOption('-m<codecs>', 'codecs to use');
  HelpOption('-d#', 'depth: also scan inside unpacked streams', '0');
  HelpOption('-c#', 'scanning range (chunk size)', '16mb');
  HelpOption('-r<a>=<b>', 'process the streams codec a finds with codec b');
  HelpOption('-scan', 'detect only, write nothing: prints "SCAN n streams"');

  HelpSection('Speed and memory');
  HelpOption('-t#', 'threads (a number, or a share of the CPUs)', '50p');
  HelpOption('-lm#', 'low memory mode, 0-3', '0');
  HelpOption('-p#', 'prefetch cache', '0mb');
  HelpOption('-T#', 'priority, 0 idle .. 6 time critical', '3');
  HelpOption('-db#', 'decode block size', '512mb');

  HelpSection('Deduplication');
  HelpOption('-dd', 'store repeated streams once (in memory)');
  HelpOption('-dd1 .. -dd5', 'the same with srep, method 1-5 (srep64 next to ytool)');
  HelpOption('-ddo', 'the same with OSREP, built into ytool (MIT)');
  HelpOption('-dm#', 'deduplication memory limit', '75p');
  HelpOption('-sp<params>', 'srep parameters, joined with :');
  HelpOption('-osp<params>', 'osrep parameters, joined with : (-ospm3:l64)');
  HelpOption('-f', 'full scan: no early exit in the dedup hash search');

  HelpSection('Output');
  HelpOption('-l#[x][:d#][:o#]', 'compress the result with fast-lzma2, level 1-10', '0');
  HelpOption('', 'x high compression, d dictionary, o overlap');
  HelpOption('-e<program>', 'compress the result with an external program instead');
  HelpOption('-x<dir>', 'also write every stream found to dir');
  HelpOption('-X<dir>', 'write only the streams that could not be processed');
  HelpOption('-o', 'optimise decode: drop codec variants already verified');

  HelpSection('Verification and patching');
  HelpOption('-s', 'skip stream verification');
  HelpOption('-df#[:l#]', 'accept a stream that differs by up to #, as a patch', '5p');
  HelpOption('', 'l patch compression level 1-22 [1]');
  HelpOption('-pa', 'patch every stream the level search could not reproduce');

  HelpSection('Tuning');
  HelpOption('-cfg<codec>[:key#]', 'codec settings: zlib st; zstd wl hl cl sl mm tl st');
  HelpOption('', 'cs ldm lhl lmm lbs lhr; lz4 x b ac ds af (see the wiki)');
  HelpOption('-b[#][:n#][:s#]', 'brute: find the lz4/lz4f/zstd settings of the streams,');
  HelpOption('', 'process nothing [5p of the candidates, n5 matches]');
  HelpOption('-lz4<lib>', 'use that library (also -zstd<lib>, -oodle<lib>)');
  HelpOption('-seed<hex>', 'srep seed, 64 hex digits, for reproducible -dd1..5');

  HelpSection('Display');
  HelpOption('-v', 'verbose: log each stream');
  HelpOption('-bar', 'print "PROGRESS done total" lines on stderr, for programs');
  WriteLine('');
  WriteLine('Sizes take kb, mb, gb; shares take p (50p = 50%). Colours: set NO_COLOR to');
  WriteLine('turn them off. More: https://github.com/YadeWira/ytool/wiki/CLI-Reference');
  WriteLine('');
end;

function CodecTable: TArray<TCodecInfo>;

  procedure Add(const Name, Group: string; Available: Boolean;
    const Lib: string = '');
  var
    C: TCodecInfo;
  begin
    C.Name := Name;
    C.Group := Group;
    C.Available := Available;
    C.Lib := Lib;
    Insert(C, Result, Length(Result));
  end;

begin
  Result := nil;
  Add('zlib', 'deflate', ZLibDLL.DLLLoaded);
  Add('libdeflate', 'deflate', LibDeflateDLL.DLLLoaded and ZLibDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'libdeflate.dll'{$ELSE}'libdeflate.so'{$ENDIF});
  Add('preflate', 'deflate', PreflateDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'preflate_dll.dll'{$ELSE}'libpreflate.so'{$ENDIF});
  Add('png', 'deflate', ZLibDLL.DLLLoaded or PreflateDLL.DLLLoaded);
  Add('pja', 'jpeg', PJADLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'pja.dll'{$ELSE}'libpja.so'{$ENDIF});
  Add('brunsli', 'jpeg', BrunsliDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'brunsli.dll'{$ELSE}'libbrunsli.so'{$ENDIF});
  Add('lz4f', 'lz4f', LZ4DLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'liblz4.dll'{$ELSE}'liblz4.so'{$ENDIF});
  Add('lz4', 'lz4', LZ4DLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'liblz4.dll'{$ELSE}'liblz4.so'{$ENDIF});
  Add('lz4hc', 'lz4', LZ4DLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'liblz4.dll'{$ELSE}'liblz4.so'{$ENDIF});
  Add('zstd', 'zstd', ZSTDDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'libzstd.dll'{$ELSE}'libzstd.so'{$ENDIF});
  Add('lzo1x', 'lzo', LZODLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'lzo2.dll'{$ELSE}'liblzo2.so.2'{$ENDIF});
  Add('lzo1c', 'lzo', LZODLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'lzo2.dll'{$ELSE}'liblzo2.so.2'{$ENDIF});
  Add('lzo2a', 'lzo', LZODLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'lzo2.dll'{$ELSE}'liblzo2.so.2'{$ENDIF});
  Add('lzma', 'lzma', True);
  Add('lzip', 'lzip', LZlibDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'lzlib.dll'{$ELSE}'liblz.so'{$ENDIF});
  Add('flac', 'wav', FLACDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'libFLAC_dynamic.dll'{$ELSE}'libFLAC'{$ENDIF});
  Add('wavpack', 'wav', WavPackDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'wavpackdll.dll'{$ELSE}'libwavpack.so.1'{$ENDIF});
  Add('kraken', 'oodle', OodleDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'Oodle (oo2core)'{$ELSE}'Oodle (oo2core)'{$ENDIF});
  Add('mermaid', 'oodle', OodleDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'Oodle (oo2core)'{$ELSE}'Oodle (oo2core)'{$ENDIF});
  Add('selkie', 'oodle', OodleDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'Oodle (oo2core)'{$ELSE}'Oodle (oo2core)'{$ENDIF});
  Add('leviathan', 'oodle', OodleDLL.DLLLoaded,
    {$IFDEF MSWINDOWS}'Oodle (oo2core)'{$ELSE}'Oodle (oo2core)'{$ENDIF});
end;

function CodecMissingLib(const Name: string): string;
var
  C: TCodecInfo;
begin
  Result := '';
  for C in CodecTable do
    if SameText(C.Name, Name) then
    begin
      if not C.Available then
        Result := C.Lib;
      exit;
    end;
end;

procedure DecodePrintHelp;
begin
  WriteLine(UIBold('decode') + ' - rebuild the original from a .ytp file');
  WriteLine('');
  WriteLine('Usage: ytool decode [options] input output');
  WriteLine('');
  WriteLine('  Writes back exactly what precomp read. Codecs and settings come from the');
  WriteLine('  file: none of precomp''s options are needed. input or output can be -.');

  HelpSection('Examples');
  WriteLine('  ytool decode game.ytp game.pak');
  WriteLine('  ytool decode -t4 game.ytp - | sha256sum');

  HelpSection('Options');
  HelpOption('-t#', 'threads (a number, or a share of the CPUs)', '50p');
  HelpOption('-T#', 'priority, 0 idle .. 6 time critical', '3');
  HelpOption('-dm#', 'deduplication memory limit', '75p');
  HelpOption('-p#', 'prefetch cache', '0mb');
  HelpOption('-sp<params>', 'srep parameters, joined with :');
  HelpOption('-e<program>', 'the external program the file was compressed with');
  HelpOption('-v', 'verbose: log each stream');
  HelpOption('-bar', 'print "PROGRESS done total" lines on stderr, for programs');
  WriteLine('');
end;

end.
