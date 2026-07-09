unit PrecompMedia;

{$POINTERMATH ON}

interface

uses
  BrunsliDLL, FLACDLL, PackJPGDLL, PackMP3DLL, JoJpegDLL, WavPackDLL,
  Utils,
  PrecompUtils,
  SysUtils, Classes, Math;

var
  Codec: TPrecompressor;

implementation

const
  MediaCodecs: array of PChar = ['flac', 'packjpg', 'brunsli', 'jojpeg',
    'packmp3', 'wavpack'];
  CODEC_COUNT = 6;
  FLAC_CODEC = 0;
  PACKJPG_CODEC = 1;
  BRUNSLI_CODEC = 2;
  JOJPEG_CODEC = 3;
  MP3_CODEC = 4;
  WAVPACK_CODEC = 5;

const
  FLAC_LEVEL = 5;
  J_WORKMEM = 65536;

type
  PFlacEncCD = ^TFlacEncCD;

  TFlacEncCD = record
    Output: TMemoryStreamEx;
    Error: Boolean;
  end;

  PFlacDecCD = ^TFlacDecCD;

  TFlacDecCD = record
    Input, Output: TMemoryStreamEx;
  end;

  PWvEncCD = ^TWvEncCD;

  TWvEncCD = record
    Output: TMemoryStreamEx;
    Error: Boolean;
  end;

  PWvDecCD = ^TWvDecCD;

  TWvDecCD = record
    Input: TMemoryStreamEx;
  end;

var
  cctx, dctx: array of Pointer;
  ccd: array of TFlacEncCD;
  dcd: array of TFlacDecCD;
  wvenc: array of TWvEncCD;
  wvdec: array of TWvDecCD;
  JJInst: TArray<Pointer>;
  FlacLevel: Integer = FLAC_LEVEL;
  CodecAvailable, CodecEnabled: TArray<Boolean>;
  RestoreOut: TArray<_PrecompOutput>;
  RestoreSize: TArray<Integer>;

const
  RIFF_SIGN = $46464952;
  WAVE_SIGN = $45564157;
  fmt_SIGN = $20746D66;
  data_SIGN = $61746164;

  WAVE_FORMAT_PCM = 1;
  WAVE_FORMAT_EXTENSIBLE = $FFFE;

type
  PRIFF_hdr = ^TRIFF_hdr;

  TRIFF_hdr = packed record
    chunk_id, chunk_size, form_type: Cardinal;
  end;

  PWAVE_hdr = ^TWAVE_hdr;

  TWAVE_hdr = packed record
    audio_format, num_channels: Word;
    sample_rate, byte_rate: Cardinal;
    block_align, bits_per_sample: Word;
  end;

  PWAVE_subchunk_hdr = ^TWAVE_subchunk_hdr;

  TWAVE_subchunk_hdr = packed record
    subchunk_id, subchunk_size: Cardinal;
  end;

  PWAVE_subformat = ^TWAVE_subformat;

  TWAVE_subformat = packed record
    f1: Cardinal;
    f2, f3: Word;
    f4: array [0 .. 7] of Byte;
  end;

  PWAVE_ext_hdr = ^TWAVE_ext_hdr;

  TWAVE_ext_hdr = packed record
    cb_size, valid_bits: Word;
    ch_mask: Cardinal;
    est: TWAVE_subformat;
  end;

function GetWAVEInfo(InBuff: PByte; InSize: NativeInt; wave_hdr: PWAVE_hdr;
  chunk_size, header_size: PCardinal): Boolean;
var
  Pos, LastPos: NativeInt;
  riffhdr: TRIFF_hdr;
  subchunk_hdr: TWAVE_subchunk_hdr;
  wave_hdr_ex: TWAVE_ext_hdr;
begin
  Result := False;
  Pos := 0;
  if InSize - Pos < SizeOf(TRIFF_hdr) then
    exit;
  Move((InBuff + Pos)^, riffhdr, SizeOf(TRIFF_hdr));
  Inc(Pos, SizeOf(TRIFF_hdr));
  if (riffhdr.chunk_id <> RIFF_SIGN) or (riffhdr.form_type <> WAVE_SIGN) then
    exit;
  while True do
  begin
    if InSize - Pos < SizeOf(TWAVE_subchunk_hdr) then
      exit;
    Move((InBuff + Pos)^, subchunk_hdr, SizeOf(TWAVE_subchunk_hdr));
    Inc(Pos, SizeOf(TWAVE_subchunk_hdr));
    if subchunk_hdr.subchunk_id = fmt_SIGN then
    begin
      LastPos := Pos;
      if InSize - Pos < SizeOf(TWAVE_hdr) then
        exit;
      Move((InBuff + Pos)^, wave_hdr^, SizeOf(TWAVE_hdr));
      Inc(Pos, SizeOf(TWAVE_hdr));
      if wave_hdr^.audio_format = WAVE_FORMAT_EXTENSIBLE then
      begin
        if InSize - Pos < SizeOf(TWAVE_ext_hdr) then
          exit;
        Move((InBuff + Pos)^, wave_hdr_ex, SizeOf(TWAVE_ext_hdr));
        Inc(Pos, SizeOf(TWAVE_ext_hdr));
        wave_hdr^.audio_format := wave_hdr_ex.est.f1;
      end
      else if wave_hdr^.audio_format <> WAVE_FORMAT_PCM then
        exit;
      Pos := LastPos + subchunk_hdr.subchunk_size;
    end
    else if subchunk_hdr.subchunk_id = data_SIGN then
    begin
      chunk_size^ := Min(subchunk_hdr.subchunk_size,
        (riffhdr.chunk_size + 8 - Pos));
      header_size^ := Pos;
      Result := chunk_size^ + header_size^ <= InSize;
      exit;
    end
    else
      Inc(Pos, subchunk_hdr.subchunk_size);
  end;
end;

function FlacEncoderWriteCB(encoder: Pointer; const Buffer; bytes: NativeUInt;
  samples, current_frame: Cardinal; client_data: PFlacEncCD): Integer cdecl;
begin
  try
    client_data^.Output.WriteBuffer(Buffer, bytes);
  except
    client_data^.Error := True;
  end;
  Result := 0;
end;

function FlacDecoderReadCB(decoder: Pointer; var Buffer; bytes: PNativeUInt;
  client_data: PFlacDecCD): Integer cdecl;
begin
  bytes^ := client_data^.Input.Read(Buffer, bytes^);
  if bytes^ > 0 then
    Result := 0
  else
    Result := 1;
end;

function FlacDecoderWriteCB(decoder: Pointer; frame: PFLAC__Frame;
  Buffer: Pointer; client_data: PFlacDecCD): Integer cdecl;
var
  I, J, X: Integer;
begin
  for I := 0 to frame^.header.blocksize - 1 do
    for J := 0 to frame^.header.channels - 1 do
    begin
      X := PInteger(PNativeInt(Buffer)[J])[I];
      client_data^.Output.WriteBuffer(X, frame^.header.bits_per_sample div 8);
    end;
  Result := 0;
end;

procedure FlacDecoderErrorCB(decoder: Pointer; Status: Integer;
  client_data: Pointer)cdecl;
begin

end;

function FlacEncode(ctx: Pointer; cd: PFlacEncCD; InBuff: PByte;
  InSize: Integer; OutBuff: PByte; OutSize: Integer;
  Level: Integer = 5): Integer;
const
  READSIZE = 1000;
var
  I, J, X: Integer;
  Ptr: PByte;
  wave_hdr: TWAVE_hdr;
  byte_per_sample: Word;
  data_size, hdr_size, smp_size: Cardinal;
  ok: Boolean;
  pcm: TArray<Integer>;
begin
  Result := 0;
  ok := False;
  if GetWAVEInfo(InBuff, InSize, @wave_hdr, @data_size, @hdr_size) then
  begin
    ok := True;
    byte_per_sample := (wave_hdr.bits_per_sample + 7) div 8;
    smp_size := wave_hdr.num_channels * byte_per_sample;
    ok := ok and FLAC__stream_encoder_set_verify(ctx, True);
    ok := ok and FLAC__stream_encoder_set_compression_level(ctx, Level);
    ok := ok and FLAC__stream_encoder_set_channels(ctx, wave_hdr.num_channels);
    ok := ok and FLAC__stream_encoder_set_bits_per_sample(ctx,
      wave_hdr.bits_per_sample);
    ok := ok and FLAC__stream_encoder_set_sample_rate(ctx,
      wave_hdr.sample_rate);
  end;
  if ok then
    try
      cd^.Error := False;
      cd^.Output.Update(OutBuff, OutSize);
      cd^.Output.Size := 0;
      if FLAC__stream_encoder_init_stream(ctx, @FlacEncoderWriteCB, nil, nil,
        nil, cd) = 0 then
      begin
        Ptr := InBuff + hdr_size;
        SetLength(pcm, READSIZE * wave_hdr.num_channels);
        while True do
        begin
          X := 0;
          for I := 0 to READSIZE - 1 do
          begin
            if NativeInt(Ptr + smp_size - InBuff) > hdr_size + data_size then
              break;
            Inc(X);
            for J := 0 to wave_hdr.num_channels - 1 do
            begin
              if NativeInt(Ptr - InBuff) > hdr_size + data_size then
                break;
              pcm[I * wave_hdr.num_channels + J] :=
                GetBits(PInteger(Ptr)^, 0, Pred(wave_hdr.bits_per_sample)) -
                IfThen(GetBits(PInteger(Ptr)^, Pred(wave_hdr.bits_per_sample),
                1) = 0, 0, 1 shl Pred(wave_hdr.bits_per_sample));
              Inc(Ptr, byte_per_sample);
            end;
          end;
          ok := ok and FLAC__stream_encoder_process_interleaved(ctx, pcm[0], X);
          if (NativeInt(Ptr + smp_size - InBuff) > hdr_size + data_size) or
            (ok = False) then
            break;
        end;
      end;
    finally
      FLAC__stream_encoder_finish(ctx);
      if ok and (cd^.Error = False) then
        Result := cd^.Output.Size;
    end;
end;

function FlacDecode(ctx: Pointer; cd: PFlacDecCD; InBuff: PByte;
  InSize: Integer; OutBuff: PByte; OutSize: Integer): Integer;
var
  ok: Boolean;
begin
  Result := 0;
  ok := False;
  cd^.Input.Update(InBuff, InSize);
  cd^.Input.Position := 0;
  cd^.Input.Size := InSize;
  cd^.Output.Update(OutBuff, OutSize);
  cd^.Output.Size := 0;
  try
    if FLAC__stream_decoder_init_stream(ctx, @FlacDecoderReadCB, nil, nil, nil,
      nil, @FlacDecoderWriteCB, nil, @FlacDecoderErrorCB, cd) = 0 then
    begin
      ok := True;
      ok := ok and FLAC__stream_decoder_process_until_end_of_stream(ctx);
    end;
  finally
    FLAC__stream_decoder_finish(ctx);
    if ok then
      Result := cd^.Output.Size;
  end;
end;

// ── WavPack (lossless audio codec, same model as FLAC: WAV->wv reversible) ──
function WvBlockOutCB(id, data: Pointer; bcount: Integer): Integer cdecl;
begin
  try
    PWvEncCD(id)^.Output.WriteBuffer(data^, bcount);
    Result := 1;
  except
    PWvEncCD(id)^.Error := True;
    Result := 0;
  end;
end;

function WvReadCB(id, data: Pointer; bcount: Integer): Integer cdecl;
begin
  Result := PWvDecCD(id)^.Input.Read(data^, bcount);
end;

function WvGetPosCB(id: Pointer): Int64 cdecl;
begin
  Result := PWvDecCD(id)^.Input.Position;
end;

function WvSetPosAbsCB(id: Pointer; pos: Int64): Integer cdecl;
begin
  PWvDecCD(id)^.Input.Position := pos;
  Result := 0;
end;

function WvSetPosRelCB(id: Pointer; delta: Int64; mode: Integer): Integer cdecl;
begin
  PWvDecCD(id)^.Input.Seek(delta, TSeekOrigin(mode));
  Result := 0;
end;

function WvPushBackCB(id: Pointer; c: Integer): Integer cdecl;
begin
  PWvDecCD(id)^.Input.Position := PWvDecCD(id)^.Input.Position - 1;
  Result := c;
end;

function WvGetLenCB(id: Pointer): Int64 cdecl;
begin
  Result := PWvDecCD(id)^.Input.Size;
end;

function WvCanSeekCB(id: Pointer): Integer cdecl;
begin
  Result := 1;
end;

function WavpackDecode(cd: PWvDecCD; InBuff: PByte; InSize: Integer;
  OutBuff: PByte; OutSize: Integer): Integer;
const
  READSIZE = 4096;
var
  reader: TWavpackStreamReader64;
  wpc: Pointer;
  err: array [0 .. 127] of AnsiChar;
  ch, bytes_ps: Integer;
  got, I: Cardinal;
  sbuf: TArray<Integer>;
  outp: PByte;
begin
  Result := 0;
  cd^.Input.Update(InBuff, InSize);
  cd^.Input.Position := 0;
  cd^.Input.Size := InSize;
  FillChar(reader, SizeOf(reader), 0);
  reader.read_bytes := @WvReadCB;
  reader.get_pos := @WvGetPosCB;
  reader.set_pos_abs := @WvSetPosAbsCB;
  reader.set_pos_rel := @WvSetPosRelCB;
  reader.push_back_byte := @WvPushBackCB;
  reader.get_length := @WvGetLenCB;
  reader.can_seek := @WvCanSeekCB;
  FillChar(err, SizeOf(err), 0);
  wpc := WavpackOpenFileInputEx64(@reader, cd, nil, @err[0], 0, 0);
  if wpc = nil then
    exit;
  try
    ch := WavpackGetNumChannels(wpc);
    bytes_ps := WavpackGetBytesPerSample(wpc);
    if (ch <= 0) or (bytes_ps <= 0) then
      exit;
    outp := OutBuff;
    SetLength(sbuf, READSIZE * ch);
    while True do
    begin
      got := WavpackUnpackSamples(wpc, @sbuf[0], READSIZE);
      if got = 0 then
        break;
      for I := 0 to (got * Cardinal(ch)) - 1 do
      begin
        if NativeInt(outp - OutBuff) + bytes_ps > OutSize then
          break;
        Move(sbuf[I], outp^, bytes_ps);
        Inc(outp, bytes_ps);
      end;
      if got < READSIZE then
        break;
    end;
    Result := outp - OutBuff;
  finally
    WavpackCloseFile(wpc);
  end;
end;

function WavpackEncode(ecd: PWvEncCD; dcd: PWvDecCD; InBuff: PByte;
  InSize: Integer; OutBuff: PByte; OutSize: Integer): Integer;
const
  READSIZE = 4096;
var
  I, J, X: Integer;
  Ptr: PByte;
  wave_hdr: TWAVE_hdr;
  byte_per_sample: Word;
  data_size, hdr_size, smp_size: Cardinal;
  total: Int64;
  wpc: Pointer;
  cfg: TWavpackConfig;
  pcm: TArray<Integer>;
  vbuf: TArray<Byte>;
  ok: Boolean;
begin
  Result := 0;
  if not GetWAVEInfo(InBuff, InSize, @wave_hdr, @data_size, @hdr_size) then
    exit;
  byte_per_sample := (wave_hdr.bits_per_sample + 7) div 8;
  smp_size := wave_hdr.num_channels * byte_per_sample;
  if smp_size = 0 then
    exit;
  total := data_size div smp_size;
  ecd^.Error := False;
  ecd^.Output.Update(OutBuff, OutSize);
  ecd^.Output.Size := 0;
  wpc := WavpackOpenFileOutput(@WvBlockOutCB, ecd, nil);
  if wpc = nil then
    exit;
  ok := True;
  try
    FillChar(cfg, SizeOf(cfg), 0);
    cfg.bytes_per_sample := byte_per_sample;
    cfg.bits_per_sample := wave_hdr.bits_per_sample;
    cfg.num_channels := wave_hdr.num_channels;
    cfg.sample_rate := wave_hdr.sample_rate;
    if WavpackSetConfiguration64(wpc, @cfg, total, nil) = 0 then
      exit;
    if WavpackPackInit(wpc) = 0 then
      exit;
    Ptr := InBuff + hdr_size;
    SetLength(pcm, READSIZE * wave_hdr.num_channels);
    while True do
    begin
      X := 0;
      for I := 0 to READSIZE - 1 do
      begin
        if NativeInt(Ptr + smp_size - InBuff) > hdr_size + data_size then
          break;
        Inc(X);
        for J := 0 to wave_hdr.num_channels - 1 do
        begin
          pcm[I * wave_hdr.num_channels + J] :=
            GetBits(PInteger(Ptr)^, 0, Pred(wave_hdr.bits_per_sample)) -
            IfThen(GetBits(PInteger(Ptr)^, Pred(wave_hdr.bits_per_sample),
            1) = 0, 0, 1 shl Pred(wave_hdr.bits_per_sample));
          Inc(Ptr, byte_per_sample);
        end;
      end;
      if X > 0 then
        if WavpackPackSamples(wpc, @pcm[0], X) = 0 then
        begin
          ok := False;
          break;
        end;
      if (NativeInt(Ptr + smp_size - InBuff) > hdr_size + data_size) or (X = 0)
      then
        break;
    end;
    if ok then
      if WavpackFlushSamples(wpc) = 0 then
        ok := False;
  finally
    WavpackCloseFile(wpc);
  end;
  if (not ok) or ecd^.Error or (ecd^.Output.Size <= 0) then
    exit;
  // VERIFY (libwavpack has no set_verify like FLAC): decode the just-created
  // .wv and require it to reproduce the EXACT original PCM; if not, fail -> literal.
  SetLength(vbuf, data_size);
  if data_size > 0 then
    if (WavpackDecode(dcd, OutBuff, ecd^.Output.Size, @vbuf[0], data_size)
      <> Integer(data_size)) or
      (not CompareMem(@vbuf[0], InBuff + hdr_size, data_size)) then
      exit;
  Result := ecd^.Output.Size;
end;

const
  JPG_HEADER = $D8FF;
  JPG_FOOTER = $D9FF;

function GetJPEGInfo(InBuff: PByte; InSize: NativeInt; ImageSize: PCardinal;
  IsProgressive: PBoolean): Boolean;
// https://github.com/schnaader/precomp-cpp/blob/master/precomp.cpp
var
  Pos: NativeInt;
  hasQuantTable: Boolean;
  done, found: Boolean;
  length: Integer;
  isMarker: Boolean;
  bytesRead: Cardinal;
begin
  Result := False;
  Pos := 0;
  done := False;
  found := False;
  if (PWord(InBuff)^ = JPG_HEADER) and ((InBuff + 2)^ = $FF) then
  begin
    Pos := 3;
    if (InBuff + Pos)^ in [$C0, $C2, $C4, $DB .. $FE] then
    begin
      hasQuantTable := (InBuff + Pos)^ = $DB;
      IsProgressive^ := (InBuff + Pos)^ = $C2;
      Pos := 2;
      repeat
        if (Pos + 5 > InSize) or ((InBuff + Pos)[0] <> $FF) then
          break;
        length := Integer((InBuff + Pos)[2]) * 256 + Integer((InBuff + Pos)[3]);
        case (InBuff + Pos)[1] of
          $DB:
            begin
              if (length <= 262) and (((length - 2) mod 65) = 0) and
                ((InBuff + Pos)[4] <= 3) then
              begin
                hasQuantTable := True;
                Inc(Pos, length + 2);
              end
              else
                done := True;
            end;
          $C4:
            begin
              done := (((InBuff + Pos)[4] and $F) > 3) or
                (((InBuff + Pos)[4] shr 4) > 1);
              Inc(Pos, length + 2);
            end;
          $DA:
            begin
              found := hasQuantTable;
              Inc(Pos, length + 2);
            end;
          $D9:
            done := True;
          $C2:
            begin
              IsProgressive^ := True;
              Inc(Pos, length + 2);
            end;
          $C0:
            begin
              done := (InBuff + Pos)[4] <> $08;
              Inc(Pos, length + 2);
            end;
        else
          Inc(Pos, length + 2);
        end;
      until done;
      if found then
        while Pos < InSize - 1 do
        begin
          if PWord(InBuff + Pos)^ = JPG_FOOTER then
          begin
            ImageSize^ := Pos + 2;
            Result := True;
            break;
          end;
          Inc(Pos);
        end;
    end;
  end;
end;

// Detects an MP3 stream (MPEG-1/2/2.5 Layer III) starting at InBuff: optional
// ID3v2 + consecutive Layer III frames + optional ID3v1. Returns the total size
// in StreamSize. Conservative (>=2 frames) to avoid false positives with stray
// 0xFF bytes; a failure only means "not recompressed" (reversibility is
// guaranteed by ytool's fallback to literal).
function GetMP3Info(InBuff: PByte; InSize: NativeInt;
  StreamSize: PCardinal): Boolean;
const
  BR1: array [0 .. 15] of Integer = (0, 32, 40, 48, 56, 64, 80, 96, 112, 128,
    160, 192, 224, 256, 320, 0); // MPEG1 LayerIII kbps
  BR2: array [0 .. 15] of Integer = (0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96,
    112, 128, 144, 160, 0); // MPEG2/2.5 LayerIII kbps
  MP3SR: array [0 .. 3, 0 .. 3] of Integer = ((11025, 12000, 8000, 0), (0, 0, 0,
    0), (22050, 24000, 16000, 0), (44100, 48000, 32000, 0));
var
  Pos, Start: NativeInt;
  b0, b1, b2: Byte;
  ver, lay, bri, sri, pad, br, sr, flen, frames, sz: Integer;
begin
  Result := False;
  StreamSize^ := 0;
  Pos := 0;
  if (InSize > 10) and (InBuff[0] = Ord('I')) and (InBuff[1] = Ord('D')) and
    (InBuff[2] = Ord('3')) then
  begin
    sz := ((InBuff[6] and $7F) shl 21) or ((InBuff[7] and $7F) shl 14) or
      ((InBuff[8] and $7F) shl 7) or (InBuff[9] and $7F);
    Pos := 10 + sz;
  end;
  Start := Pos;
  frames := 0;
  while Pos + 4 <= InSize do
  begin
    b0 := InBuff[Pos];
    b1 := InBuff[Pos + 1];
    b2 := InBuff[Pos + 2];
    if (b0 <> $FF) or ((b1 and $E0) <> $E0) then
      break;
    ver := (b1 shr 3) and 3;
    lay := (b1 shr 1) and 3;
    if (ver = 1) or (lay <> 1) then // reserved version / not Layer III (01)
      break;
    bri := (b2 shr 4) and $F;
    sri := (b2 shr 2) and 3;
    pad := (b2 shr 1) and 1;
    if (bri = 0) or (bri = 15) or (sri = 3) then
      break;
    sr := MP3SR[ver, sri];
    if sr = 0 then
      break;
    if ver = 3 then
      br := BR1[bri]
    else
      br := BR2[bri];
    if ver = 3 then
      flen := (144 * br * 1000) div sr + pad
    else
      flen := (72 * br * 1000) div sr + pad;
    if flen < 4 then
      break;
    Inc(Pos, flen);
    Inc(frames);
  end;
  if frames < 2 then
    exit;
  if (Pos + 128 <= InSize) and (InBuff[Pos] = Ord('T')) and
    (InBuff[Pos + 1] = Ord('A')) and (InBuff[Pos + 2] = Ord('G')) then
    Inc(Pos, 128);
  StreamSize^ := Pos;
  Result := Pos > Start;
end;

function BrunsliWriter(cd: Pointer; data: Pointer; Size: NativeUInt)
  : Integer cdecl;
begin
  RestoreOut[PInteger(cd)^](PInteger(cd)^, data, Size);
  Inc(RestoreSize[PInteger(cd)^], Size);
  Result := Size;
end;

function MediaInit(Command: PChar; Count: Integer;
  Funcs: PPrecompFuncs): Boolean;
var
  I: Integer;
  Options: TArray<Integer>;
  S: String;
  X, Y: Integer;
begin
  Result := True;
  SetLength(RestoreOut, Count);
  SetLength(RestoreSize, Count);
  for X := Low(CodecAvailable) to High(CodecAvailable) do
  begin
    CodecAvailable[X] := False;
    CodecEnabled[X] := False;
  end;
  CodecAvailable[FLAC_CODEC] := FLACDLL.DLLLoaded;
  CodecAvailable[PACKJPG_CODEC] := PackJPGDLL.DLLLoaded;
  CodecAvailable[BRUNSLI_CODEC] := BrunsliDLL.DLLLoaded;
  CodecAvailable[JOJPEG_CODEC] := JoJpegDLL.DLLLoaded;
  CodecAvailable[MP3_CODEC] := PackMP3DLL.DLLLoaded;
  CodecAvailable[WAVPACK_CODEC] := WavPackDLL.DLLLoaded;
  X := 0;
  while Funcs^.GetCodec(Command, X, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, X, False);
    if (CompareText(S, MediaCodecs[FLAC_CODEC]) = 0) and FLACDLL.DLLLoaded then
    begin
      CodecEnabled[FLAC_CODEC] := True;
      if Funcs^.GetParam(Command, X, 'l') <> '' then
        FlacLevel := StrToInt(Funcs^.GetParam(Command, X, 'l'));
    end
    else if (CompareText(S, MediaCodecs[PACKJPG_CODEC]) = 0) and PackJPGDLL.DLLLoaded
    then
      CodecEnabled[PACKJPG_CODEC] := True
    else if (CompareText(S, MediaCodecs[BRUNSLI_CODEC]) = 0) and BrunsliDLL.DLLLoaded
    then
      CodecEnabled[BRUNSLI_CODEC] := True
    else if (CompareText(S, MediaCodecs[JOJPEG_CODEC]) = 0) and JoJpegDLL.DLLLoaded
    then
      CodecEnabled[JOJPEG_CODEC] := True
    else if (CompareText(S, MediaCodecs[MP3_CODEC]) = 0) and PackMP3DLL.DLLLoaded
    then
      CodecEnabled[MP3_CODEC] := True
    else if (CompareText(S, MediaCodecs[WAVPACK_CODEC]) = 0) and
      WavPackDLL.DLLLoaded then
      CodecEnabled[WAVPACK_CODEC] := True;
    Inc(X);
  end;
  if CodecAvailable[WAVPACK_CODEC] then
  begin
    SetLength(wvenc, Count);
    SetLength(wvdec, Count);
    for X := Low(wvenc) to High(wvenc) do
    begin
      wvenc[X].Output := TMemoryStreamEx.Create(False);
      wvenc[X].Error := False;
      wvdec[X].Input := TMemoryStreamEx.Create(False);
    end;
  end;
  if CodecAvailable[FLAC_CODEC] then
  begin
    SetLength(cctx, Count);
    SetLength(dctx, Count);
    SetLength(ccd, Count);
    SetLength(dcd, Count);
    for X := Low(cctx) to High(cctx) do
    begin
      cctx[X] := nil;
      dctx[X] := nil;
      ccd[X].Output := TMemoryStreamEx.Create(False);
      dcd[X].Input := TMemoryStreamEx.Create(False);
      dcd[X].Output := TMemoryStreamEx.Create(False);
    end;
  end;
  if CodecAvailable[JOJPEG_CODEC] then
  begin
    SetLength(JJInst, Count);
    for X := Low(JJInst) to High(JJInst) do
      JJInst[X] := nil;
  end;
end;

procedure MediaFree(Funcs: PPrecompFuncs);
var
  X: Integer;
begin
  if CodecAvailable[FLAC_CODEC] then
  begin
    for X := Low(cctx) to High(cctx) do
    begin
      if Assigned(cctx[X]) then
        FLAC__stream_encoder_delete(cctx[X]);
      if Assigned(dctx[X]) then
        FLAC__stream_decoder_delete(dctx[X]);
      ccd[X].Output.Free;
      dcd[X].Input.Free;
      dcd[X].Output.Free;
    end;
  end;
  if CodecAvailable[WAVPACK_CODEC] then
    for X := Low(wvenc) to High(wvenc) do
    begin
      wvenc[X].Output.Free;
      wvdec[X].Input.Free;
    end;
  if CodecAvailable[JOJPEG_CODEC] then
    for X := Low(JJInst) to High(JJInst) do
      if Assigned(JJInst[X]) then
        FreeMemory(JJInst[X]);
end;

function MediaParse(Command: PChar; Option: PInteger;
  Funcs: PPrecompFuncs): Boolean;
var
  S: String;
  I: Integer;
begin
  Result := False;
  Option^ := 0;
  I := 0;
  while Funcs^.GetCodec(Command, I, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, I, False);
    if (CompareText(S, MediaCodecs[FLAC_CODEC]) = 0) and FLACDLL.DLLLoaded then
    begin
      SetBits(Option^, FLAC_CODEC, 0, 3);
      Result := True;
    end
    else if (CompareText(S, MediaCodecs[PACKJPG_CODEC]) = 0) and PackJPGDLL.DLLLoaded
    then
    begin
      SetBits(Option^, PACKJPG_CODEC, 0, 3);
      Result := True;
    end
    else if (CompareText(S, MediaCodecs[BRUNSLI_CODEC]) = 0) and BrunsliDLL.DLLLoaded
    then
    begin
      SetBits(Option^, BRUNSLI_CODEC, 0, 3);
      Result := True;
    end
    else if (CompareText(S, MediaCodecs[JOJPEG_CODEC]) = 0) and JoJpegDLL.DLLLoaded
    then
    begin
      SetBits(Option^, JOJPEG_CODEC, 0, 3);
      Result := True;
    end
    else if (CompareText(S, MediaCodecs[MP3_CODEC]) = 0) and PackMP3DLL.DLLLoaded
    then
    begin
      SetBits(Option^, MP3_CODEC, 0, 3);
      Result := True;
    end
    else if (CompareText(S, MediaCodecs[WAVPACK_CODEC]) = 0) and
      WavPackDLL.DLLLoaded then
    begin
      SetBits(Option^, WAVPACK_CODEC, 0, 3);
      Result := True;
    end;
    Inc(I);
  end;
end;

procedure MediaScan1(Instance, Depth: Integer; Input: PByte;
  Size, SizeEx: NativeInt; Output: _PrecompOutput; Add: _PrecompAdd;
  Funcs: PPrecompFuncs);
var
  Buffer: PByte;
  Pos: NativeInt;
  X, Y, Z: Integer;
  SI: _StrInfo1;
  wave_hdr: TWAVE_hdr;
  data_size, hdr_size: Cardinal;
  progressive: Boolean;
begin
  if BoolArray(CodecEnabled, False) then
    exit;
  Pos := 0;
  while Pos < Size do
  begin
    if (CodecEnabled[FLAC_CODEC] or CodecEnabled[WAVPACK_CODEC]) and
      (PCardinal(Input + Pos)^ = RIFF_SIGN) then
    begin
      Y := SizeEx - Pos;
      if GetWAVEInfo(Input + Pos, Y, @wave_hdr, @data_size, @hdr_size) then
        Y := data_size + hdr_size
      else
        Y := 0;
      if Y > 0 then
      begin
        Z := data_size;
        Buffer := Funcs^.Allocator(Instance, hdr_size);
        Move((Input + Pos)^, Buffer^, hdr_size);
        Inc(PInteger(Buffer)^);
        Output(Instance, @hdr_size, hdr_size.Size);
        Output(Instance, Buffer, hdr_size);
        Output(Instance, Input + Pos + hdr_size, Z);
        Inc(Z, hdr_size.Size);
        Inc(Z, hdr_size);
        SI.Position := Pos;
        SI.OldSize := Y;
        SI.NewSize := Z;
        SI.Option := 0;
        if CodecEnabled[FLAC_CODEC] then
          SetBits(SI.Option, FLAC_CODEC, 0, 3)
        else
          SetBits(SI.Option, WAVPACK_CODEC, 0, 3);
        SI.Status := TStreamStatus.None;
        Funcs^.LogScan1(MediaCodecs[GetBits(SI.Option, 0, 3)], SI.Position,
          SI.OldSize, -1);
        Add(Instance, @SI, nil, nil);
        Inc(Pos, SI.OldSize);
        continue;
      end;
    end;
    if (CodecEnabled[PACKJPG_CODEC] or CodecEnabled[BRUNSLI_CODEC] or
      CodecEnabled[JOJPEG_CODEC]) and (PWord(Input + Pos)^ = JPG_HEADER) then
    begin
      Y := SizeEx - Pos;
      if GetJPEGInfo(Input + Pos, Y, @data_size, @progressive) then
        Y := data_size
      else
        Y := 0;
      if Y > 0 then
      begin
        Z := data_size;
        Output(Instance, Input + Pos, Z);
        SI.Position := Pos;
        SI.OldSize := Y;
        SI.NewSize := Z;
        SI.Option := 0;
        if CodecEnabled[BRUNSLI_CODEC] then
          SetBits(SI.Option, BRUNSLI_CODEC, 0, 3)
        else if CodecEnabled[JOJPEG_CODEC] then
          SetBits(SI.Option, JOJPEG_CODEC, 0, 3)
        else if CodecEnabled[PACKJPG_CODEC] then
          SetBits(SI.Option, PACKJPG_CODEC, 0, 3);
        SI.Status := TStreamStatus.None;
        Funcs^.LogScan1(MediaCodecs[GetBits(SI.Option, 0, 3)], SI.Position,
          SI.OldSize, -1);
        Add(Instance, @SI, nil, nil);
        Inc(Pos, SI.OldSize);
        continue;
      end;
    end;
    if CodecEnabled[MP3_CODEC] and
      ((((Input + Pos)^ = $FF) and (((Input + Pos + 1)^ and $E0) = $E0)) or
      ((PWord(Input + Pos)^ = $4449) and ((Input + Pos + 2)^ = Ord('3')))) then
    begin
      Y := SizeEx - Pos;
      if GetMP3Info(Input + Pos, Y, @data_size) then
        Y := data_size
      else
        Y := 0;
      if Y > 0 then
      begin
        Z := data_size;
        Output(Instance, Input + Pos, Z);
        SI.Position := Pos;
        SI.OldSize := Y;
        SI.NewSize := Z;
        SI.Option := 0;
        SetBits(SI.Option, MP3_CODEC, 0, 3);
        SI.Status := TStreamStatus.None;
        Funcs^.LogScan1(MediaCodecs[GetBits(SI.Option, 0, 3)], SI.Position,
          SI.OldSize, -1);
        Add(Instance, @SI, nil, nil);
        Inc(Pos, SI.OldSize);
        continue;
      end;
    end;
    Inc(Pos);
  end;
end;

function MediaScan2(Instance, Depth: Integer; Input: Pointer; Size: NativeInt;
  StreamInfo: PStrInfo2; Offset: PInteger; Output: _PrecompOutput;
  Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  X, Y, Z: Integer;
  wave_hdr: TWAVE_hdr;
  data_size, hdr_size: Cardinal;
  progressive: Boolean;
begin
  Result := False;
  X := GetBits(StreamInfo^.Option, 0, 3);
  if StreamInfo^.OldSize <= 0 then
    exit;
  Y := StreamInfo^.OldSize;
  case X of
    FLAC_CODEC, WAVPACK_CODEC:
      begin
        if GetWAVEInfo(Input, Y, @wave_hdr, @data_size, @hdr_size) then
          Y := data_size + hdr_size
        else
          Y := 0;
      end;
    PACKJPG_CODEC, BRUNSLI_CODEC, JOJPEG_CODEC:
      begin
        if GetJPEGInfo(Input, Y, @data_size, @progressive) then
          Y := data_size
        else
          Y := 0;
      end;
    MP3_CODEC:
      begin
        if GetMP3Info(Input, Y, @data_size) then
          Y := data_size
        else
          Y := 0;
      end;
  else
    Y := 0;
  end;
  if Y > 0 then
  begin
    Z := data_size;
    if (X = FLAC_CODEC) or (X = WAVPACK_CODEC) then
    begin
      Buffer := Funcs^.Allocator(Instance, hdr_size);
      Move(Input^, Buffer^, hdr_size);
      Inc(PInteger(Buffer)^);
      Output(Instance, @hdr_size, hdr_size.Size);
      Output(Instance, Buffer, hdr_size);
      Output(Instance, PByte(Input) + hdr_size, Z);
      Inc(Z, hdr_size.Size);
      Inc(Z, hdr_size);
    end
    else
      Output(Instance, Input, Z);
    StreamInfo^.NewSize := Z;
    Funcs^.LogScan2(MediaCodecs[GetBits(StreamInfo^.Option, 0, 3)],
      StreamInfo^.OldSize, -1);
    Result := True;
  end;
end;

function MediaProcess(Instance, Depth: Integer; OldInput, NewInput: Pointer;
  StreamInfo: PStrInfo2; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer, Ptr: PByte;
  Params: String;
  ctx: Pointer;
  I, J: Integer;
  X, Y: Integer;
  Res: Cardinal;
  Res1, Res2: Integer;
begin
  Result := False;
  X := GetBits(StreamInfo^.Option, 0, 3);
  if BoolArray(CodecAvailable, False) or (CodecAvailable[X] = False) then
    exit;
  Params := '';
  case X of
    FLAC_CODEC:
      begin
        Params := 'l' + FlacLevel.ToString;
        Y := Integer.Size + PInteger(NewInput)^;
        if not Assigned(cctx[Instance]) then
          cctx[Instance] := FLAC__stream_encoder_new;
        Res := StreamInfo.NewSize - Y;
        Res := FlacEncode(cctx[Instance], @ccd[Instance], OldInput,
          StreamInfo^.OldSize, PByte(NewInput) + Y, Res, FlacLevel);
        if (Res > 0) and (Res + Y < StreamInfo^.NewSize) then
        begin
          StreamInfo^.NewSize := Res + Y;
          Result := True;
        end;
      end;
    WAVPACK_CODEC:
      begin
        Y := Integer.Size + PInteger(NewInput)^;
        Res := StreamInfo.NewSize - Y;
        Res := WavpackEncode(@wvenc[Instance], @wvdec[Instance], OldInput,
          StreamInfo^.OldSize, PByte(NewInput) + Y, Res);
        if (Res > 0) and (Res + Y < StreamInfo^.NewSize) then
        begin
          StreamInfo^.NewSize := Res + Y;
          Result := True;
        end;
      end;
    PACKJPG_CODEC:
      begin
        Buffer := nil;
        Res := StreamInfo.OldSize;
        pjglib_init_streams(OldInput, pjglib_memory, StreamInfo^.OldSize,
          Buffer, pjglib_memory);
        if pjglib_convert_stream2mem(@Buffer, @Res, nil) and
          (Res < StreamInfo^.NewSize) then
        begin
          Move(Buffer^, NewInput^, Res);
          StreamInfo^.NewSize := Res;
          Result := True;
        end;
      end;
    BRUNSLI_CODEC:
      begin
        ctx := brunsli_alloc_JPEGData;
        try
          if brunsli_ReadJpeg(ctx, OldInput, StreamInfo^.OldSize) = Integer(True)
          then
          begin
            Res := brunsli_GetMaximumEncodedSize(ctx);
            Buffer := Funcs^.Allocator(Instance, Res);
            Res := brunsli_EncodeJpeg(ctx, Buffer, Res);
            if Res < StreamInfo^.NewSize then
            begin
              Move(Buffer^, NewInput^, Res);
              StreamInfo^.NewSize := Res;
              Result := True;
            end;
          end;
        finally
          brunsli_free_JPEGData(ctx);
        end;
      end;
    JOJPEG_CODEC:
      begin
        if not Assigned(JJInst[Instance]) then
          JJInst[Instance] := GetMemory(jojpeg_Size);
        ctx := JJInst[Instance];
        FillChar(ctx^, jojpeg_Size, 0);
        Buffer := Funcs^.Allocator(Instance, J_WORKMEM * 2);
        I := 0;
        J := 0;
        Y := 0;
        jojpeg_Init(ctx, jojpeg_Compress);
        try
          jojpeg_Addbuf(ctx, jojpeg_Compress, Buffer, J_WORKMEM,
            jojpeg_enc_Output1);
          jojpeg_Addbuf(ctx, jojpeg_Compress, Buffer + J_WORKMEM, J_WORKMEM,
            jojpeg_enc_Output2);
          while True do
          begin
            Res1 := jojpeg_Loop(ctx, jojpeg_Compress);
            if (Res1 = 1) then
            begin
              Res2 := Min(StreamInfo^.OldSize - I, J_WORKMEM);
              jojpeg_Addbuf(ctx, jojpeg_Compress, PByte(OldInput) + I, Res2,
                jojpeg_enc_Input);
              Inc(I, Res2);
            end;
            if (Res1 in [0, 2]) then
            begin
              Res2 := jojpeg_Getvalue(ctx, jojpeg_Compress, jojpeg_enc_Output1);
              Move(Buffer^, (PByte(NewInput) + J)^, Res2);
              Inc(J, Res2);
              jojpeg_Addbuf(ctx, jojpeg_Compress, Buffer, J_WORKMEM,
                jojpeg_enc_Output1);
            end;
            if (Res1 = 3) or (Res1 = 0) then
            begin
              Res2 := jojpeg_Getvalue(ctx, jojpeg_Compress, jojpeg_enc_Output2);
              Output(Instance, Buffer + J_WORKMEM, Res2);
              Inc(Y, Res2);
              jojpeg_Addbuf(ctx, jojpeg_Compress, Buffer + J_WORKMEM, J_WORKMEM,
                jojpeg_enc_Output2);
              if Res1 = 0 then
                break;
            end;
          end;
          if I = StreamInfo^.OldSize then
          begin
            StreamInfo^.NewSize := J;
            Result := True;
          end;
        finally
          jojpeg_Quit(ctx, jojpeg_Compress);
        end;
      end;
    MP3_CODEC:
      begin
        Buffer := nil;
        Res := StreamInfo.OldSize;
        pmplib_init_streams(OldInput, pmplib_memory, StreamInfo^.OldSize,
          Buffer, pmplib_memory);
        if pmplib_convert_stream2mem(@Buffer, @Res, nil) and
          (Res < StreamInfo^.NewSize) then
        begin
          Move(Buffer^, NewInput^, Res);
          StreamInfo^.NewSize := Res;
          Result := True;
        end;
      end;
  end;
  Funcs^.LogProcess(MediaCodecs[GetBits(StreamInfo^.Option, 0, 3)],
    PChar(Params), StreamInfo^.OldSize, StreamInfo^.NewSize, -1, Result);
end;

function MediaRestore(Instance, Depth: Integer; Input, InputExt: Pointer;
  StreamInfo: _StrInfo3; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  Params: String;
  ctx, writer: Pointer;
  I, J: Integer;
  X, Y: Integer;
  Res: Cardinal;
  Res1, Res2: Integer;
begin
  Result := False;
  X := GetBits(StreamInfo.Option, 0, 3);
  if BoolArray(CodecAvailable, False) or (CodecAvailable[X] = False) then
    exit;
  Params := '';
  case X of
    FLAC_CODEC:
      begin
        Buffer := Funcs^.Allocator(Instance, StreamInfo.OldSize);
        Y := Integer.Size + PInteger(Input)^;
        if not Assigned(dctx[Instance]) then
          dctx[Instance] := FLAC__stream_decoder_new;
        Res := StreamInfo.OldSize;
        Res := FlacDecode(dctx[Instance], @dcd[Instance], PByte(Input) + Y,
          StreamInfo.NewSize - Y, Buffer + PInteger(Input)^, Res);
        if Res > 0 then
        begin
          Move((PByte(Input) + Integer.Size)^, Buffer^, PInteger(Input)^);
          Inc(Res, PInteger(Input)^);
          Dec(PInteger(Buffer)^);
          Result := True;
        end;
        if Result then
          Output(Instance, Buffer, Res);
      end;
    WAVPACK_CODEC:
      begin
        Buffer := Funcs^.Allocator(Instance, StreamInfo.OldSize);
        Y := Integer.Size + PInteger(Input)^;
        Res := WavpackDecode(@wvdec[Instance], PByte(Input) + Y,
          StreamInfo.NewSize - Y, Buffer + PInteger(Input)^,
          StreamInfo.OldSize - PInteger(Input)^);
        if Res > 0 then
        begin
          Move((PByte(Input) + Integer.Size)^, Buffer^, PInteger(Input)^);
          Inc(Res, PInteger(Input)^);
          Dec(PInteger(Buffer)^);
          Result := True;
        end;
        if Result then
          Output(Instance, Buffer, Res);
      end;
    PACKJPG_CODEC:
      begin
        Buffer := nil;
        pjglib_init_streams(Input, pjglib_memory, StreamInfo.NewSize, Buffer,
          pjglib_memory);
        Res := StreamInfo.OldSize;
        Result := pjglib_convert_stream2mem(@Buffer, @Res, nil);
        if Result then
          Output(Instance, Buffer, Res);
      end;
    BRUNSLI_CODEC:
      begin
        RestoreOut[Instance] := Output;
        RestoreSize[Instance] := 0;
        Res := RestoreSize[Instance];
        ctx := brunsli_alloc_JPEGData;
        try
          if brunsli_DecodeJpeg(ctx, Input, StreamInfo.NewSize) = BRUNSLI_OK
          then
          begin
            writer := brunsli_alloc_JPEGOutput(BrunsliWriter, @Instance);
            try
              Result := Boolean(brunsli_WriteJpeg(ctx, writer));
            finally
              brunsli_free_JPEGOutput(writer);
            end;
          end;
        finally
          brunsli_free_JPEGData(ctx);
        end;
        Res := RestoreSize[Instance];
      end;
    JOJPEG_CODEC:
      begin
        if not Assigned(JJInst[Instance]) then
          JJInst[Instance] := GetMemory(jojpeg_Size);
        ctx := JJInst[Instance];
        FillChar(ctx^, jojpeg_Size, 0);
        Buffer := Funcs^.Allocator(Instance, J_WORKMEM);
        I := 0;
        J := 0;
        Y := 0;
        jojpeg_Init(ctx, jojpeg_Decompress);
        try
          jojpeg_Addbuf(ctx, jojpeg_Decompress, Buffer, J_WORKMEM,
            jojpeg_dec_Output);
          while True do
          begin
            Res1 := jojpeg_Loop(ctx, jojpeg_Decompress);
            if (Res1 = jojpeg_dec_Input1) then
            begin
              Res2 := Min(StreamInfo.NewSize - I, J_WORKMEM);
              jojpeg_Addbuf(ctx, jojpeg_Decompress, PByte(Input) + I, Res2,
                jojpeg_dec_Input1);
              Inc(I, Res2);
            end;
            if (Res1 = jojpeg_dec_Input2) then
            begin
              Res2 := Min(StreamInfo.ExtSize - J, J_WORKMEM);
              jojpeg_Addbuf(ctx, jojpeg_Decompress, PByte(InputExt) + J, Res2,
                jojpeg_dec_Input2);
              Inc(J, Res2);
            end;
            if (Res1 in [0, jojpeg_dec_Output]) then
            begin
              Res2 := jojpeg_Getvalue(ctx, jojpeg_Decompress,
                jojpeg_dec_Output);
              Output(Instance, Buffer, Res2);
              Inc(Y, Res2);
              jojpeg_Addbuf(ctx, jojpeg_Decompress, Buffer, J_WORKMEM,
                jojpeg_dec_Output);
              if Res1 = 0 then
                break;
            end;
          end;
          Res := Y;
          Result := Y = StreamInfo.OldSize;
        finally
          jojpeg_Quit(ctx, jojpeg_Decompress);
        end;
      end;
    MP3_CODEC:
      begin
        Buffer := nil;
        pmplib_init_streams(Input, pmplib_memory, StreamInfo.NewSize, Buffer,
          pmplib_memory);
        Res := StreamInfo.OldSize;
        Result := pmplib_convert_stream2mem(@Buffer, @Res, nil);
        if Result then
          Output(Instance, Buffer, Res);
      end;
  end;
  Funcs^.LogRestore(MediaCodecs[GetBits(StreamInfo.Option, 0, 3)],
    PChar(Params), StreamInfo.NewSize, Res, -1, Result);
end;

var
  I: Integer;

initialization

Codec.Names := [];
for I := Low(MediaCodecs) to High(MediaCodecs) do
begin
  Codec.Names := Codec.Names + [MediaCodecs[I]];
  StockMethods.Add(MediaCodecs[I]);
end;
Codec.Initialised := False;
Codec.Init := @MediaInit;
Codec.Free := @MediaFree;
Codec.Parse := @MediaParse;
Codec.Scan1 := @MediaScan1;
Codec.Scan2 := @MediaScan2;
Codec.Process := @MediaProcess;
Codec.Restore := @MediaRestore;
SetLength(CodecAvailable, length(Codec.Names));
SetLength(CodecEnabled, length(Codec.Names));

end.
