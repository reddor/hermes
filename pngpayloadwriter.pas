unit PNGPayloadWriter;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  FPImgCmn,
  PNGcomn;

type
  TChunkId = packed record
    case Boolean of
      true: (
        Raw: LongWord;
      );
      false: (
        Id: array[0..3] of Char;
      );
  end;

  TPNGChunk = packed record
    length: LongWord;
    ChunkType: array[0..3] of Char;
  end;

  TPNGPayloadWriter = class
  private
    FCrunch: Boolean;
    FFileSize: Integer;
    FData: PByteArray;
    FChunks: array of record
      ChunkId: TChunkId;
      Data: Pointer;
      Length: Integer;
      OldCRC: LongWord;
    end;
    FSize: Integer;
    procedure WriteChunk(var F: File; Index: Integer);
  public
    constructor Create(InputFile: ansistring);
    destructor Destroy; override;
    procedure Rebuild(OutputFile, Comment: ansistring);
    property Crunch: Boolean read FCrunch write FCrunch;
    property Size: Integer read FSize;
  end;

implementation

{ TPNGPayloadWriter }

procedure TPNGPayloadWriter.WriteChunk(var F: File; Index: Integer);
var
  t: LongWord;
begin
  t:=SwapEndian(FChunks[Index].Length);
  BlockWrite(f, t, SizeOf(t));
  t:=FChunks[Index].ChunkId.Raw;
  BlockWrite(f, t, SizeOf(t));
  if FChunks[Index].Length>0 then
    BlockWrite(f, FChunks[Index].Data^, FChunks[Index].Length);
  t:=FChunks[Index].OldCRC;
  BlockWrite(f, t, SizeOf(t));
end;

constructor TPNGPayloadWriter.Create(InputFile: ansistring);
var
  f: File;
  pos, c: LongWord;
begin
  FCrunch:=False;
  Assignfile(f, InputFile);
  Reset(f, 1);
  FFileSize:=FileSize(f);
  GetMem(FData, FFileSize);
  BlockRead(f, FData^, FFileSize);
  Closefile(F);
  pos:=8;
  while pos < FFileSize do
  begin
    c:=Length(FChunks);
    Setlength(FChunks, c+1);
    FChunks[c].Length:=SwapEndian(PLongWord(@FData^[pos])^);
    Inc(Pos, SizeOf(LongWord));
    FChunks[c].ChunkId.Raw:=PLongWord(@FData^[pos])^;
    Inc(Pos, SizeOf(LongWord));
    FChunks[c].Data:=@FData^[pos];
    Inc(Pos, FChunks[c].Length);
    if pos>=FFileSize then
      raise Exception.Create('Invalid PNG');
    FChunks[c].OldCRC:=PLongWord(@FData^[pos])^;
    Inc(Pos, SizeOf(LongWord));
  end;
end;

destructor TPNGPayloadWriter.Destroy;
begin
  if Assigned(FData) then
    Freemem(FData);
  inherited Destroy;
end;

procedure TPNGPayloadWriter.Rebuild(OutputFile, Comment: ansistring);
var
  f: File;
  i: Integer;
  t: LongWord;
  c: TChunkId;
begin
  Assignfile(f, OutputFile);
  rewrite(f, 1);
  BlockWrite(f, FData^[0], 8);
  WriteChunk(f, 0);
  c.Id:='hrms';
  t:=Length(Comment);
  t:=SwapEndian(t);
  BlockWrite(f, t, SizeOf(t));
  BlockWrite(f, c.Raw, SizeOf(c.Raw));
  BlockWrite(f, Comment[1], Length(Comment));
  t:=SwapEndian(CalculateCRC(CalculateCRC(All1Bits, c, SizeOf(c)), Comment[1], Length(Comment)) xor All1Bits);
  BlockWrite(f, t, SizeOf(t));

  for i:=1 to Length(FChunks)-1 do
  if (FChunks[i].ChunkId.Id <> 'IEND') or (not Crunch) then
  WriteChunk(f, i);
  FSize:=FileSize(f);
  Closefile(f);
end;

end.

