unit preprocessor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs;

const
  TokenBacklogSize = 16;

type

  { TJSPreprocessorFile }

  TJSPreprocessorFile = class
  private
    FError: Boolean;
    FFilename: ansistring;
    FContent: TStringList;
    FOutput: ansistring;
    FLinePos: Integer;
    FHasExports: Boolean;
    FPragmaOnce: Boolean;
    function GetEoF: Boolean;
    function GetOutput: ansistring;
  public
    constructor Create(AFilename: ansistring);
    destructor Destroy; override;
    procedure AddExport(const exportName: ansistring);
    procedure AddOutput(const s: ansistring);
    function GetLine: ansistring;
    property Error: Boolean read FError;
    property EoF: Boolean read GetEoF;
    property Filename: ansistring read FFilename;
    property HasExports: Boolean read FHasExports;
    property PragmaOnce: Boolean read FPragmaOnce write FPragmaOnce;
    property LinePos: Integer read FLinePos;
    property Output: ansistring read GetOutput;
  end;

  { TJSPreprocessor }
  TJSPreprocessor = class
  private
    FDefines: TFPStringHashTable;
    FExcludedFiles: array of ansistring;
    FFiles: array of TJSPreprocessorFile;
    FCurrentLine: ansistring;
    FHasError: Boolean;
    FTokenBacklog: array[0..TokenBacklogSize-1] of ansistring;
    FTokenBacklogPos, FTokenStepsBack: Integer;
    FCurrentFile: ansistring;
    FCurrentLinePos: Integer;
    FIfDepth: array of Integer;
    FStripComments: Boolean;
    FStripNewLines: Boolean;
    FStripSpaces: Boolean;
    FOutput, FCSS: ansistring;
    FVerbose: Boolean;
    FResources: array of string;
    function CurrentPosition: ansistring;
    procedure ExcludeFile(AFilename: ansistring);
    function GetLine: ansistring;
    function GetResource(Index: Integer): string;
    function GetResourceCount: Integer;
    function MergeCSS(AFilename: ansistring): Boolean;
    procedure AddOutput(const s: ansistring);
    procedure ParseExportedFunction;
    function ParsePre(str: ansistring): Boolean;
    function SkipUntil(ConditionA: ansistring; ConditionB: ansistring = ''): Integer;
    procedure PushIf(Flag: Integer);
    function PopIf: Integer;
    function ProcessLineOptions(const Line: ansistring): ansistring;
    procedure VerboseMsg(msg: ansistring; msg2: ansistring = '');
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function AddResource(filename: string): Integer;
    function OpenFile(AFilename: ansistring): Boolean;
    function GetNextToken: ansistring;
    function GetNextNonWhitespaceToken: ansistring;
    function LastToken: ansistring;
    function Finished: Boolean;
    procedure RestoreLastToken;
    function Process: Boolean;
    function SaveProcessed(OutputFile: ansistring): Boolean;
    function SaveCSS(CSSFile: ansistring): Boolean;
    property CSS: ansistring read FCSS;
    property HasError: Boolean read FHasError;
    property StripComments: Boolean read FStripComments write FStripComments;
    property StripSpaces: Boolean read FStripSpaces write FStripSpaces;
    property StripNewLines: Boolean read FStripNewLines write FStripNewLines;
    property Output: ansistring read FOutput;
    property Verbose: Boolean read FVerbose write FVerbose;
    property ResourceCount: Integer read GetResourceCount;
    property Resources[Index: Integer]: string read GetResource;
  end;

function FilterPath(FullFilename: ansistring): ansistring;

implementation

const
  Prefix = '//#';
  NewLine = #13#10;
  SeparatorChars = '()|/%+-*.,;:[]{}<>&!=?"'' '#13#10#9;
  Numbers = '0123456789.';
  HexNumbers = Numbers + 'abcdefABCDEF';

function ReadFileAsJSString(Filename: ansistring): ansistring;
var
  t: Textfile;
  s: ansistring;
  function Escape(s: ansistring): ansistring;
  var
    i: Integer;
  begin
    result:='';
    for i:=1 to length(s) do
    begin
      if s[i]='\' then
        result:=result + '\\'
      else if s[i]='"' then
        result:=result + '\"'
      else if s[i]=#13 then
        result:=result + '\n'
      else if s[i]=#10 then
        // nothing
      else
        result:=result + s[i];
    end;
  end;

begin
  result:='';
  Assignfile(t, Filename);
  {$i-}reset(t);{$i+}
  if ioresult<>0 then
  exit;
  try
  while not Eof(t) do
  begin
    Readln(t, s);
    if result <> '' then
      result:=result + '\n' + Escape(s)
    else
      result:=Escape(s);
  end;
  result:='"' + result + '"';
  finally
    closefile(t);
  end;
end;

function FilterPath(FullFilename: ansistring): ansistring;
var
  s: ansistring;
  i, j: Integer;
begin
  result:=FullFilename;
  s:=FullFilename;
  {$IFDEF MSWINDOWS}
  s:=StringReplace(s, '\', '/', [rfReplaceAll]);
  {$ENDIF}
  i:=Pos('/./', s);
  while i>0 do
  begin
    Delete(s, i, 2);
    i:=Pos('/./', s);
  end;
  i:=Pos('/../', s);
  while i>0 do
  begin
    j:=i-1;
    while (j>0)and(s[j] <> '/') do
      Dec(j);

    if j=0 then
      Exit;
    Delete(s, j, 3+i-j);
    i:=Pos('/../', s);
  end;
  {$IFDEF MSWINDOWS}
  s:=StringReplace(s, '/', '\', [rfReplaceAll]);
  {$ENDIF}
  result:=s;
end;

{
function GetToken(var str: ansistring; Separator: ansistring): ansistring;
var
  i: Integer;
begin
  i:=Pos(Separator, str) - 1;
  if i>=0 then
  begin
    if i>0 then
      result:=Copy(str, 1, i);
    Delete(str, 1, i + Length(Separator));
    if i=0 then
      result:=GetToken(str, Separator);
  end else
  begin
    result:=str;
    str:='';
  end;
end; }

function GetToken(var InputString: ansistring; IgnoreStrings: Boolean = False): ansistring;
var
  i: Integer;
begin
  result:='';

  if InputString = '' then
    Exit;

  // parse numbers (decimal, float(.) and hex (prefixed with 0x)
  if Pos(InputString[1], '0123456789')>0 then
  begin
    if (Length(InputString)>1) and (InputString[1] = '0') and (InputString[2] = 'x') then
    begin
      i:=3;
      while (i<=Length(InputString)) and (Pos(InputString[i], HexNumbers)>0) do Inc(i);
    end else
    begin
      i:=1;
      while (i+1<=Length(InputString)) and (Pos(InputString[i+1], Numbers)>0) do Inc(i);
    end;
  end else
  // parse string
  if (not IgnoreStrings) and ((InputString[1]='"') or (InputString[1]='''')) then
  begin
    i:=2;
    repeat
      if InputString[i]='\' then
        Inc(i)
      else if InputString[i]=InputString[1] then
        Break;
      Inc(i);
    until i>Length(InputString);
  end else
  begin
    i:=1;
    if Pos(InputString[1], SeparatorChars)=0 then
    while (i+1<=Length(InputString)) and (Pos(InputString[i+1], SeparatorChars)=0) do
      Inc(i);
  end;
  result:=Copy(InputString, 1, i);
  Delete(InputString, 1, i);
end;

function GetNonWhitespaceToken(var Inputstring: ansistring): ansistring;
begin
  repeat
    result:=GetToken(InputString);
  until Pos(result, ' '#9#13#10)=0;
end;

function NeedsSeparator(A, B: ansichar): Boolean;
const
  SafeCharacters = ';(){},.[]<>=:|&+-*/!?"'' ' + NewLine;
begin
  result:=(Pos(A, SafeCharacters)=0) and (Pos(B, SafeCharacters)=0);
end;

function SkipString(const input: ansistring; EndChar: AnsiChar; var Position: Integer): Boolean;
begin
  result:=input[Position] = EndChar;
  if result then
  begin
    repeat
      inc(Position)
    until (Position>length(input)) or ((input[Position] = EndChar) and (input[Position-1] <> '\'));
  inc(Position);
  end;
end;

function StripRedundantSpaces(const input: ansistring): ansistring;
var
  i: Integer;
begin
  i:=1;
  result:=input;
  while i<Length(result) do
  begin
    while (i<Length(result)) and (SkipString(result, '"', i) or SkipString(result, '''', i)) do;
    if i>Length(result) then
      Break;
    if ((result[i] = ' ') or (result[i] = #9)) and ((i = 1) or (not NeedsSeparator(result[i-1], result[i+1]))) then
      Delete(result, i, 1)
    else
      inc(i);
  end;
end;

function StripLineComment(input: ansistring): ansistring;
var
  i: Integer;
begin
  i:=1;
  result:='';
  while i<Length(input) do
  begin
    while (i<Length(input)) and (SkipString(input, '"', i) or SkipString(input, '''', i)) do;
    if i>Length(Input) then
      Break;
    if (i<Length(input)) then
      if (input[i]='/') and (input[i+1]='/') then
      begin
        result:=Copy(input, 1, i-1);
        exit;
      end;
    inc(i);
  end;
  result:=input;
end;

{ TJSPreprocessorFile }

function TJSPreprocessorFile.GetEoF: Boolean;
begin
  result:=FLinePos >= FContent.Count;
end;

function TJSPreprocessorFile.GetOutput: ansistring;
begin
  if FHasExports then
    result:='var '+FOutput + '})();'
  else
    result:=FOutput;
end;

constructor TJSPreprocessorFile.Create(AFilename: ansistring);
begin
  FContent:=TStringList.Create;
  FFilename:=AFilename;
  FError:=False;
  FLinePos:=0;
  FOutput:='';
  FHasExports:=False;
  FPragmaOnce:=False;
  try
    FContent.LoadFromFile(FFilename);
  except
    FError:=True;
    FContent.Clear;
  end;
end;

destructor TJSPreprocessorFile.Destroy;
begin
  FContent.Free;
  inherited Destroy;
end;

procedure TJSPreprocessorFile.AddExport(const exportName: ansistring);
begin
  if not FHasExports then
    FOutput:=exportName + ';(function(){' + FOutput
  else
    FOutput:=exportName + ',' + FOutput;
  FHasExports:=True;
end;

procedure TJSPreprocessorFile.AddOutput(const s: ansistring);
begin
  FOutput:=FOutput + s;
end;

function TJSPreprocessorFile.GetLine: ansistring;
begin
  if FLinePos < FContent.Count then
  begin
    result:=FContent[FLinePos];
    Inc(FLinePos);
  end else
    result:='';
end;

{ TJSPreprocessor }

function TJSPreprocessor.GetLine: ansistring;
var
  i: Integer;
begin
  result:='';
  repeat
    i:=Length(FFiles)-1;
    if i<0 then
      Exit;
    if FFiles[i].EoF then
    begin
      if (i>0) and (not (FFiles[i].HasExports or FFiles[i].PragmaOnce)) then
        FFiles[i-1].AddOutput(FFiles[i].Output)
      else
        FOutput:=FOutput + FFiles[i].Output;
      FFiles[i].Free;
      Setlength(FFiles, i);
    end else
      Break;
  until false;
  result:=FFiles[i].GetLine;
  FCurrentFile:=FFiles[i].FileName;
  FCurrentLinePos:=FFiles[i].LinePos;
end;

function TJSPreprocessor.GetResource(Index: Integer): string;
begin
  result:=FResources[Index];
end;

function TJSPreprocessor.GetResourceCount: Integer;
begin
  result:=Length(FResources);
end;

function TJSPreprocessor.MergeCSS(AFilename: ansistring): Boolean;
var
  t: TextFile;
  s: ansistring;
begin
  result:=False;

  s:=ExtractFilePath(AFilename);
  if (s = '') or (s[1] = '.') then
  begin
    if Length(FFiles)>0 then
      AFilename:=ExtractFilePath(FFiles[Length(FFiles)-1].FileName) + AFilename
    else
      AFilename:=ExpandFileName(AFilename);
  end;
  AFilename:=FilterPath(AFilename);

  Assignfile(t, AFilename);
  {$i-}Reset(t);{$i+}
  if ioresult <> 0 then
  begin
    Writeln(CurrentPosition, 'Could not open ', AFilename);
    result:=False;
    Exit;
  end;
   VerboseMsg('Opening ', AFilename);

  if FCSS <> '' then
    FCSS:=FCSS + #13#10;
  if FVerbose and not (FStripComments or FStripNewLines) then
    FCSS:=FCSS + '/* ----- '+AFilename+' -----*/'#13#10 + s;

  while not EoF(t) do
  begin
    Readln(t, s);
    //if trim(s) <> '' then
    FCSS:=FCSS + s + #13#10;
  end;

  Closefile(t);
  result:=True;
end;

procedure TJSPreprocessor.AddOutput(const s: ansistring);
begin
  if Length(FFiles)>0 then
    FFiles[Length(FFiles)-1].AddOutput(s)
  else
    FOutput:=FOutput + s;
end;

procedure TJSPreprocessor.ParseExportedFunction;
var
  s: ansistring;
  BraceCount: Integer;
  FC: Integer;
begin
  BraceCount:=0;
  FC:=Length(FFiles);
  while not Finished do
  begin
    s:=GetNextToken;
    while (s = '/') and (Pos('/', FCurrentLine)=1) do
    begin
      // ignore comments
      if not FStripComments then
      AddOutput(s + FCurrentLine);
      FCurrentLine:='';
      s:=GetNextToken;
    end;

    if FC > length(FFiles) then
    begin
      Writeln(CurrentPosition, 'Warning: exported function goes through multiple files');
      FC:=Length(FFiles);
    end;

    AddOutput(s);
    if s = '{' then
    begin
      Inc(BraceCount)
    end
    else if s = '}' then
    begin
      Dec(BraceCount);
      if BraceCount=0 then
      begin
        s:=GetNextToken;
        if s <> ';' then s:=';' + s;
        AddOutput(s);
        Exit;
      end;
    end;
  end;
  FHasError:=True;
  Writeln(CurrentPosition, 'Closing parenthesis for exported function not found!');
end;

function TJSPreprocessor.OpenFile(AFilename: ansistring): Boolean;
var
  i: Integer;
  s: ansistring;
begin
  result:=False;

  s:=ExtractFilePath(AFilename);
  if (s = '') or (s[1] = '.') then
  begin
    if Length(FFiles)>0 then
      AFilename:=ExtractFilePath(FFiles[Length(FFiles)-1].FileName) + AFilename
    else
      AFilename:=ExpandFileName(AFilename);
  end;

  AFilename:=FilterPath(AFileName);

  for i:=0 to Length(FExcludedFiles)-1 do
  if AFilename = FExcludedFiles[i] then
  begin
    // just ignore, but don't fail
    result:=True;
    Exit;
  end;
  // prevent recursion
  for i:=0 to Length(FFiles)-1 do
  if AFilename = FFiles[i].Filename then
  begin
    Writeln('Circular reference detected');
    Exit;
  end;
  VerboseMsg('Opening ', AFilename);

  i:=Length(FFiles);
  SetLength(FFiles, i+1);
  FFiles[i]:=TJSPreprocessorFile.Create(AFilename);
  result:=not FFiles[i].Error;
  if FFiles[i].Error then
    Setlength(FFiles, i);
end;

function TJSPreprocessor.GetNextToken: ansistring;
var
  s: ansistring;
begin
  result:='';
  if FTokenStepsBack>0 then
  begin
    Dec(FTokenStepsBack);
    result:=FTokenBacklog[(FTokenBacklogPos - FTokenStepsBack -1) mod TokenBacklogSize];
    Exit;
  end;

  while FCurrentLine = '' do
  begin
    if Finished then
      Exit;
    FCurrentLine:=GetLine;

    s:=Trim(FCurrentLine);
    if Pos(Prefix, s)=1 then
    begin
      FCurrentLine:='';
      Delete(s, 1, Length(Prefix));
      if ParsePre(s) then
      begin
        if FVerbose and not (FStripComments or FStripNewLines) then
        begin
          result:='/* '+s+' */' + NewLine;
          Exit;
        end;
        Continue;
      end;
      FHasError:=True;
      //Writeln(CurrentPosition, 'Invalid preprocessor syntax: ', Trim(FCurrentLine));
      Exit;
    end;
    FCurrentLine:=ProcessLineOptions(FCurrentLine);
  end;

  result:=GetToken(FCurrentLine);

  // filter out multiline comments /* */
  if (result = '/') and (Pos('*', FCurrentLine)=1) then
  begin
    result:=CurrentPosition; // save current position in case comment is not closed

    if not FStripComments then
      AddOutput('/*');

    GetToken(FCurrentLine); // remove "*" from opening "/*"
    repeat
      if FCurrentLine = '' then
        FCurrentLine:=ProcessLineOptions(GetLine);
      s:=GetToken(FCurrentLine, True);
      if not FStripComments then
        AddOutput(s);

      if (s = '*') and (Pos('/', FCurrentLine)=1) then
      begin
        if not FStripComments then
          AddOutput('/');
        GetToken(FCurrentLine); // remove "/" from closing "*/"
        result:=GetNextToken();
        Exit;
      end;
    until Finished;
    FHasError:=True;
    Writeln(result, 'unclosed comment');
    Exit;
  end;

  if Assigned(FDefines.Find(result)) then
  begin
    s:=FDefines[result];
    if s<>'' then
      result:=s;
  end;

  FTokenBacklog[FTokenBacklogPos mod TokenBacklogSize]:=result;
  Inc(FTokenBacklogPos);
end;

function TJSPreprocessor.GetNextNonWhitespaceToken: ansistring;
begin
  repeat
    result:=GetNextToken;
  until Pos(result, ' '#9#13#10)=0;
end;

function TJSPreprocessor.LastToken: ansistring;
begin
  result:=FTokenBacklog[(FTokenBacklogPos - FTokenStepsBack - 1) mod TokenBacklogSize];
end;

function TJSPreprocessor.Finished: Boolean;
begin
  result:=((Length(FFiles)=0) and (FCurrentLine = '')) or FHasError;
end;

procedure TJSPreprocessor.RestoreLastToken;
begin
  if FTokenStepsBack < TokenBacklogSize - 1 then
    Inc(FTokenStepsBack);
end;

function TJSPreprocessor.Process: Boolean;
begin
  result:=False;
  if Finished then
    Exit;
  FOutput:='';
  FCSS:='';

  while not Finished do
  begin
    AddOutput(GetNextToken);
  end;

  result:=not FHasError;
end;

function TJSPreprocessor.SaveProcessed(OutputFile: ansistring): Boolean;
var
  t: Textfile;
begin
  result:=False;
  if (not Finished) or FHasError then
    Exit;

  AssignFile(t, OutputFile);
  {$i-}Rewrite(t);{$i+}
  if ioresult<>0 then
    Exit;
  Write(t, FOutput);
  Closefile(t);
  result:=not FHasError;
end;

function TJSPreprocessor.SaveCSS(CSSFile: ansistring): Boolean;
var
  t: Textfile;
begin
  result:=False;
  if not Finished then
    Exit;

  AssignFile(t, CSSFile);
  {$i-}Rewrite(t);{$i+}
  if ioresult<>0 then
    Exit;
  Write(t, FCSS);
  Closefile(t);
  result:=True;
end;

function TJSPreprocessor.ParsePre(str: ansistring): Boolean;
var
  cmd, s: ansistring;
  i: Integer;
begin
  result:=False;

  i:=Length(FFiles) - 1;
  if i<0 then
  raise Exception.Create('Internal error');

  cmd:=lowercase(GetToken(str));
  str:=trim(str);


  if trim(cmd) = '' then
  begin
    result:=True;
    Exit;
  end;

  if cmd='resource' then
  begin
    s:=GetToken(str);
    if (FDefines.Find(s)<>nil) and FVerbose then
      Writeln(CurrentPosition, '''', s, ''' is already defined');
    FDefines.Add(s, IntToStr(AddResource(ExpandFileName(trim(str)))));
  end else
  if cmd='export' then
  begin
    s:=GetNextNonWhitespaceToken;
    if s='var' then
    begin
      s:=GetNextNonWhitespaceToken;
      FFiles[i].AddOutput(s);
      FFiles[i].AddExport(s);
    end else
    if s='function' then
    begin
      s:=GetNextNonWhitespaceToken;
      FFiles[i].AddOutput(s + '=function');
      FFiles[i].AddExport(s);
      ParseExportedFunction;
    end else
    begin
      Writeln(CurrentPosition, 'export must be followed by function or var declaration (got ', s, ')');
      Exit;
    end;
    if Pos(s, SeparatorChars)>0 then
    begin
      Writeln(CurrentPosition, 'invalid identifier');
      Exit;
    end;
  end else
  if cmd='include' then
  begin
    result:=OpenFile(str);
    Exit;
  end else
  if cmd='inline' then
  begin
    AddOutput(ReadFileAsJSString(str));
  end else
  {
  if cmd='mergecss' then
  begin
    result:=MergeCSS(str);
  end else}
  if cmd='pragma' then
  begin
    if str='once' then
    begin
      ExcludeFile(FCurrentFile);
      FFiles[i].PragmaOnce:=True;
      result:=True;
    end else
      Writeln(CurrentPosition, 'Unsupported pragma ', str);
  end else
  if cmd='define' then
  begin
    s:=GetToken(str);
    FDefines.Add(s, str);
    if (FDefines.Find(s)<>nil) and FVerbose then
      Writeln(CurrentPosition, '''', s, ''' is already defined');
    result:=true;
  end else
  if cmd='undef' then
  begin
    FDefines.Delete(str);
  end else
  if (cmd='if') then
  begin
    Writeln(CurrentPosition, 'Warning: if unsupported, assuming true...');
    Writeln(CurrentPosition, cmd, ' ', str);
    PushIf(2);
  end else
  if (cmd='ifdef') or (cmd='ifndef') then
  begin
    if Assigned(FDefines.Find(str)) xor (cmd = 'ifdef') then
    begin
      case SkipUntil('else', 'endif') of
        0: begin
          Writeln('ifdef without endif');
          exit;
        end;
        1: PushIf(1);
      end;
    end else
      PushIf(2);
  end else
  if (cmd='else') then
  begin
    case PopIf() of
      -1: begin
        Writeln(CurrentPosition, 'else without if');
        Exit;
      end;
      1: begin
        Writeln(CurrentPosition, 'endif expected');
        Exit;
      end;
      2: begin
        SkipUntil('endif');
        //PushIf(1);
      end;
      else begin
        Writeln('Internal error');
        Exit;
      end;
    end;
  end else if (cmd = 'endif') then
  begin
    if PopIf = -1 then
    begin
      Writeln(CurrentPosition, 'endif without if');
      Exit;
    end;
  end else
  begin
    Writeln(CurrentPosition,'Unknown preprocessor command: "', cmd,'"');
    Exit;
  end;
  result:=True;
end;

function TJSPreprocessor.SkipUntil(ConditionA: ansistring;
  ConditionB: ansistring): Integer;
var
  s: ansistring;
  depth: Integer;
begin
  result:=0;
  depth:=0;
  repeat
    s:=Trim(GetLine);
    if Pos(Prefix, s)=1 then
    begin
      Delete(s, 1, 3);
      if (pos('ifdef ', s)>0) or (pos('ifndef ',s)>0) then
        Inc(depth)
      else if (depth > 0) then
      begin
        if s = 'endif' then
          Dec(depth);
      end else
      if (s = ConditionA) then
      begin
        result:=1;
        Exit;
      end else
      if (ConditionB <> '') and (s = ConditionB) then
      begin
        result:=2;
        Exit;
      end;
    end;
  until Length(FFiles)<=0;
end;

procedure TJSPreprocessor.PushIf(Flag: Integer);
var
  i: Integer;
begin
  i:=Length(FIfDepth);
  Setlength(FIfDepth, i+1);
  FIfDepth[i]:=Flag;
end;

function TJSPreprocessor.PopIf: Integer;
var
  i: Integer;
begin
  i:=Length(FIfDepth) - 1;
  if i<0 then
    result:=-1
  else begin
    result:=FIfDepth[i];
    Setlength(FIfDepth, i);
  end;
end;

function TJSPreprocessor.ProcessLineOptions(const Line: ansistring): ansistring;
begin
  result:=Line;
  if not FStripNewLines then
    result:=Result + NewLine;
  if FStripSpaces then
    Result:=StripRedundantSpaces(StringReplace(Result, #9, ' ', [rfReplaceAll]));
  if FStripComments then
    Result:=StripLineComment(Result);
end;

procedure TJSPreprocessor.VerboseMsg(msg: ansistring; msg2: ansistring);
begin
  if not FVerbose then
    Exit;
  Writeln(Msg, msg2);
end;

procedure TJSPreprocessor.ExcludeFile(AFilename: ansistring);
var
  i: Integer;
begin
  i:=Length(FExcludedFiles);
  Setlength(FExcludedFiles, i+1);
  FExcludedFiles[i]:=AFilename;
end;

function TJSPreprocessor.CurrentPosition: ansistring;
begin
  result:='[' + FCurrentFile+':'+IntToStr(FCurrentLinePos) + '] ';
end;

constructor TJSPreprocessor.Create;
begin
  FDefines:=TFPStringHashTable.Create;
  FStripNewLines:=False;
  FStripSpaces:=False;
  FStripComments:=False;
  FTokenBacklogPos:=0;
  FTokenStepsBack:=0;
end;

destructor TJSPreprocessor.Destroy;
begin
  Setlength(FFiles, 0);
  FDefines.Free;
  inherited Destroy;
end;

procedure TJSPreprocessor.Clear;
var
  i: Integer;
begin
  FDefines.Clear;
  for i:=0 to Length(FFiles)-1 do
  FFiles[i].Free;
  Setlength(FFiles, 0);
  Setlength(FExcludedFiles, 0);
  FOutput:='';
  FCSS:='';
  FCurrentLine:='';
  FHasError:=False;
  FTokenBacklogPos:=0;
  FTokenStepsBack:=0;
  FCurrentFile:='';
  FCurrentLinePos:=0;
  Setlength(FIfDepth, 0);
  Setlength(FResources, 0);
end;

function TJSPreprocessor.AddResource(filename: string): Integer;
var
  i: Integer;
  tmp: string;
begin
  if not FileExists(filename) then
    Writeln('Warning: Could not find file '+filename);
  tmp:=LowerCase(ExtractFileName(filename));
  for i:=0 to Length(FResources)-1 do
  begin
    if tmp = LowerCase(ExtractFileName(FResources[i])) then
    begin
      result:=i;
      exit;
    end;
  end;
  i:=Length(FResources);
  Setlength(FResources, i + 1);
  FResources[i]:=filename;
  result:=i;
end;

end.

