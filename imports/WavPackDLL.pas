unit WavPackDLL;

// Binding for libwavpack 5.x for ytool's WavPack codec (mirrors FLACDLL).
// API validated via a C probe: encode (OpenFileOutput+SetConfiguration64+PackInit+
// PackSamples+FlushSamples) and decode (OpenFileInputEx64+UnpackSamples) in memory
// with callbacks; bit-exact PCM round-trip. libwavpack.so.1 (system) on Unix.

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils;

{$PACKRECORDS C}

type
  PWavpackConfig = ^TWavpackConfig;

  TWavpackConfig = record
    bitrate, shaping_weight: Single;
    bits_per_sample, bytes_per_sample: Integer;
    qmode, flags, xmode, num_channels, float_norm_exp: Integer;
    block_samples, extra_flags, sample_rate, channel_mask: Integer;
    md5_checksum: array [0 .. 15] of Byte;
    md5_read: Byte;
    num_tag_strings: Integer;
    tag_strings: Pointer;
  end;

  PWavpackStreamReader64 = ^TWavpackStreamReader64;

  TWavpackStreamReader64 = record
    read_bytes: function(id, data: Pointer; bcount: Integer): Integer cdecl;
    write_bytes: function(id, data: Pointer; bcount: Integer): Integer cdecl;
    get_pos: function(id: Pointer): Int64 cdecl;
    set_pos_abs: function(id: Pointer; pos: Int64): Integer cdecl;
    set_pos_rel: function(id: Pointer; delta: Int64; mode: Integer): Integer cdecl;
    push_back_byte: function(id: Pointer; c: Integer): Integer cdecl;
    get_length: function(id: Pointer): Int64 cdecl;
    can_seek: function(id: Pointer): Integer cdecl;
    truncate_here: function(id: Pointer): Integer cdecl;
    close: function(id: Pointer): Integer cdecl;
  end;

  TWavpackBlockOutput = function(id, data: Pointer; bcount: Integer)
    : Integer cdecl;

{$PACKRECORDS DEFAULT}

var
  WavpackOpenFileOutput: function(blockout: TWavpackBlockOutput;
    wv_id, wvc_id: Pointer): Pointer cdecl;
  WavpackSetConfiguration64: function(wpc: Pointer; config: PWavpackConfig;
    total_samples: Int64; chan_ids: PByte): Integer cdecl;
  WavpackPackInit: function(wpc: Pointer): Integer cdecl;
  WavpackPackSamples: function(wpc: Pointer; sample_buffer: PInteger;
    sample_count: Cardinal): Integer cdecl;
  WavpackFlushSamples: function(wpc: Pointer): Integer cdecl;
  WavpackOpenFileInputEx64: function(reader: PWavpackStreamReader64;
    wv_id, wvc_id: Pointer; error: PAnsiChar; flags, norm_offset: Integer)
    : Pointer cdecl;
  WavpackUnpackSamples: function(wpc: Pointer; buffer: PInteger;
    samples: Cardinal): Cardinal cdecl;
  WavpackGetNumChannels: function(wpc: Pointer): Integer cdecl;
  WavpackGetBitsPerSample: function(wpc: Pointer): Integer cdecl;
  WavpackGetBytesPerSample: function(wpc: Pointer): Integer cdecl;
  WavpackCloseFile: function(wpc: Pointer): Pointer cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

procedure Init;
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(PluginsPath + 'wavpackdll.dll', True));
{$IFDEF UNIX}
  if not Lib.Loaded then
    Lib.LoadLib('libwavpack.so.1');
{$ENDIF}
  if Lib.Loaded then
  begin
    @WavpackOpenFileOutput := Lib.GetProcAddr('WavpackOpenFileOutput');
    @WavpackSetConfiguration64 := Lib.GetProcAddr('WavpackSetConfiguration64');
    @WavpackPackInit := Lib.GetProcAddr('WavpackPackInit');
    @WavpackPackSamples := Lib.GetProcAddr('WavpackPackSamples');
    @WavpackFlushSamples := Lib.GetProcAddr('WavpackFlushSamples');
    @WavpackOpenFileInputEx64 := Lib.GetProcAddr('WavpackOpenFileInputEx64');
    @WavpackUnpackSamples := Lib.GetProcAddr('WavpackUnpackSamples');
    @WavpackGetNumChannels := Lib.GetProcAddr('WavpackGetNumChannels');
    @WavpackGetBitsPerSample := Lib.GetProcAddr('WavpackGetBitsPerSample');
    @WavpackGetBytesPerSample := Lib.GetProcAddr('WavpackGetBytesPerSample');
    @WavpackCloseFile := Lib.GetProcAddr('WavpackCloseFile');
    DLLLoaded := Assigned(WavpackOpenFileOutput) and
      Assigned(WavpackOpenFileInputEx64) and Assigned(WavpackPackSamples) and
      Assigned(WavpackUnpackSamples);
  end;
end;

procedure Deinit;
begin
  Lib.Free;
end;

initialization

Init;

finalization

Deinit;

end.
