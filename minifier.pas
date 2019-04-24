unit minifier;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs;

type

  { TMinifier }

  TMinifier = class
  private
    FData: ansistring;
    FDocHack: Boolean;
    FPosition: Integer;
    FReservedWords: TFPStringHashTable;
    FReuseIdentifiers: Boolean;
    FReuseStrings: Boolean;
    FWords: array of record
      word, replacement: ansistring;
      hitCount: Integer;
    end;
  protected
    function GetToken: ansistring;
    procedure AddProtected(Word: ansistring);
    procedure WordHit(Word: ansistring);
    function replace(Word: ansistring; MightNeedSpace: Boolean): ansistring;
    function GenName(Count: Integer): ansistring;
    function ReplaceReserved(token: ansistring): ansistring;
  public
    constructor Create;
    function Process(Input: ansistring): ansistring;
    destructor Destroy; override;
    procedure AddWordList(Filename: ansistring);
    procedure ClearWordList;
    property ReuseStrings: Boolean read FReuseStrings write FReuseStrings;
    property ReuseIdentifiers: Boolean read FReuseIdentifiers write FReuseIdentifiers;
    property DocumentHack: Boolean read FDocHack write FDocHack;
  end;

function Minify(InFile, OutFile: ansistring): ansistring;

implementation

const
  SeparatorChars = '()|/%+-*.,;:[]{}<>&!=?"'' '#13#10#9;
  Numbers = '0123456789.';
  HexNumbers = Numbers + 'abcdefABCDEF';

function Minify(InFile, OutFile: ansistring): ansistring;
var
  f: File;
begin
  Assignfile(f, InFile);
  Reset(f, 1);
  Setlength(result, FileSize(f));
  Blockread(f, result[1], Length(result));
  Closefile(f);
  with TMinifier.Create do
  begin
    if FileExists('whitelist.txt') then
      AddWordList('whitelist.txt')
    else
      AddWordList(ExtractFilePath(paramstr(0))+'whitelist.txt');
    Result:=Process(result);
    Free;
  end;

  result:=result;
  Assignfile(f, OutFile);
  rewrite(f, 1);
  blockwrite(f, result[1], Length(result));
  closefile(f);
end;

{ TMinifier }

constructor TMinifier.Create;
begin
  FReservedWords:=TFPStringHashTable.Create;
  ReuseStrings:=False;
end;

function TMinifier.Process(Input: ansistring): ansistring;
var
  token, lasttoken: ansistring;
  i, j: Integer;
  b: Boolean;
  doc: ansistring;

begin
  FData:=Input;
  FPosition:=1;
  Setlength(FWords, 0);
  lasttoken:='';
  while FPosition <= Length(FData) do
  begin
    token:=GetToken;
    if (Pos(token, SeparatorChars) = 0) and (not Assigned(FReservedWords.Find(token))) and (Pos(token[1], Numbers) =0) and
       (ReuseStrings or ((token[1]<>'"')and(token[1]<>''''))) then
      WordHit(token)
    else if (lasttoken='.') and Assigned(FReservedWords.Find(token)) and FReuseIdentifiers then
      WordHit('"'+token+'"');
    lasttoken:=token;
  end;
  repeat
    b:=true;
    for i:=0 to Length(FWords)-2 do
    if FWords[i].hitCount < FWords[i+1].hitCount then
    begin
      token:=FWords[i].word;
      j:=FWords[i].hitCount;
      FWords[i].word:=FWords[i+1].word;
      FWords[i].hitCount:=FWords[i+1].hitCount;
      FWords[i+1].word:=token;
      FWords[i+1].hitCount:=j;
      b:=False;
    end;
  until b;
  j:=0;
  result:='';
  b:=False;
  if FDocHack then
  begin
    repeat
      doc:=GenName(j);
      inc(j);
    until not Assigned(FReservedWords.Find(doc));
    b:=True;
    result:='var '+doc+'=document';
  end;
  for i:=0 to Length(FWords)-1 do
  begin
      if ((FWords[i].word[1] = '"') or (FWords[i].word[1] = '''')) then
      begin
        if {FReuseStrings and }(FWords[i].hitCount>1) and (Length(FWords[i].Word)>4) then
        begin
          repeat
            FWords[i].replacement:=GenName(j);
            inc(j);
          until not Assigned(FReservedWords.Find(FWords[i].replacement));
          if not b then
            result:='var '+FWords[i].replacement+'='+FWords[i].word
          else
            result:=result + ',' + FWords[i].replacement+'='+FWords[i].word;
          b:=True;
        end;
      end else
      begin
        repeat
          FWords[i].replacement:=GenName(j);
          inc(j);
        until not Assigned(FReservedWords.Find(FWords[i].replacement));
      end;
  end;
  if b then result:=result + ';';

  FPosition:=1;
  while FPosition <= Length(FData) do
  begin
    token:=GetToken;
    if FDocHack and (Token = 'document') then
      result:=result + doc
    else
    if token='.' then
    begin
      result:=result + ReplaceReserved(GetToken);
    end else
    if (Pos(token, SeparatorChars) > 0) or (Assigned(FReservedWords.Find(token))) {or (token[1] = '"') or (token[1] = '''') } or (Pos(token[1], Numbers) <> 0) then
      result:=result + token
    else
      result:=result + Replace(token, (Length(result)>0) and (Pos(result[Length(Result)], ' '#13#10)=0));
  end;
end;

destructor TMinifier.Destroy;
begin
  FReservedWords.Free;
  inherited Destroy;
end;

procedure SkipString(input: ansistring; EndChar: AnsiChar; var Position: Integer);
begin
  if input[Position] = EndChar then
  repeat
    inc(Position)
  until (Position>length(input)) or ((input[Position] = EndChar) and (input[Position-1] <> '\'));
end;

function TMinifier.GetToken: ansistring;
var
  start: Integer;
begin
  result:='';
  if FPosition>Length(Fdata) then
    Exit;
  if Pos(FData[Fposition], Numbers)>0 then
  begin
    if (FPosition<Length(FData)) and (FData[FPosition] = '0') and (Uppercase(FData[FPosition+1]) = 'X') then
    begin
      // hex
      result:='0x';
      Inc(FPosition, 2);
      while FPosition<=Length(FData) do
      begin
        if Pos(FData[FPosition], HexNumbers)>0 then
          result:=result + FData[FPosition]
        else
          Exit;
        Inc(FPosition);
      end;
    end else
    begin
      while FPosition<=Length(FData) do
      begin
        if Pos(FData[FPosition], Numbers)>0 then
          result:=result + FData[FPosition]
        else
          Exit;
        Inc(FPosition);
      end;
    end;
  end;
  while FPosition<=Length(FData) do
  begin
    if Pos(FData[FPosition], SeparatorChars)>0 then
    begin
      if result = '' then
      begin
        if (FData[FPosition] = '"') or (FData[FPosition] = '''') then
        begin
          start:=FPosition;
          SkipString(FData, FData[FPosition], FPosition);
          Inc(FPosition);
          result:=Copy(FData, start, FPosition - start);
        end else
        begin
          result:=FData[FPosition];
          Inc(FPosition);
        end;
      end;
      Exit;
    end;
    result:=result + FData[FPosition];
    Inc(FPosition);
  end;
end;

procedure TMinifier.AddProtected(Word: ansistring);
begin
  if not Assigned(FReservedWords.Find(Word)) then
  FReservedWords.Add(Word, '');
end;

procedure TMinifier.WordHit(Word: ansistring);
var
  i: Integer;
begin
  for i:=0 to Length(FWords)-1 do
  if FWords[i].word = word then
  begin
    Inc(FWords[i].hitCount);
    Exit;
  end;
  i:=Length(FWords);
  Setlength(FWords, i+1);
  FWords[i].word:=Word;
  FWords[i].replacement:='';
  FWords[i].hitCount:=1;
end;

function TMinifier.replace(Word: ansistring; MightNeedSpace: Boolean): ansistring;
var
  i: Integer;
begin
  for i:=0 to Length(FWords)-1 do
  if FWords[i].word = word then
  begin
    if FWords[i].replacement = '' then
      result:=Word
    else
      if (Pos(Word[1], '"''')>0) and MightNeedSpace then
        result:=' ' +FWords[i].replacement
      else
        result:=FWords[i].replacement;
    Exit;
  end;
  result:=Word;
  //raise Exception.Create('Internal error');
end;

function TMinifier.GenName(Count: Integer): ansistring;
const
  Chars : ansistring = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_';
begin
  result:=Chars[1 + (Count mod Length(Chars))];
  while Count>=Length(Chars) do
  begin
    Count:=Count div Length(Chars);
    result:=result + Chars[1 + (Count mod Length(Chars))];
  end;
end;

function TMinifier.ReplaceReserved(token: ansistring): ansistring;
var
  i: Integer;
begin
  result:='';
  if Assigned(FReservedWords.Find(token)) then
  begin
    result:='.'+token;
    for i:=0 to Length(FWords)-1 do
    if FWords[i].word = '"'+token+'"' then
    begin
      if FWords[i].replacement<>'' then
        result:='[' + FWords[i].replacement + ']';
      Exit;
    end;
  end else
  if (Pos(token, SeparatorChars) = 0) and (Pos(token[1], Numbers) = 0) then
    result:='.' + replace(token, false);
end;

procedure TMinifier.AddWordList(Filename: ansistring);
var
  t: Textfile;
  s: AnsiString;
begin
  Assignfile(t, Filename);
  reset(t);
  while not Eof(t) do
  begin
    readln(t, s);
    AddProtected(s);
  end;
  closefile(t);
end;

procedure TMinifier.ClearWordList;
begin
  FReservedWords.Clear;
end;

end.

