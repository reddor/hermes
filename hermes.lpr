program hermes;

{$mode objfpc}{$H+}

uses
  SysUtils,
  preprocessor,
  minifier,
  websocketserver,
  compress2png,
  pngpayloadwriter,
  utils,
  clientmanager;

var
  Processor: TJSPreprocessor;
  MinifierInstance: TMinifier;
  ServerClients: TClientManager;
  InputFile, OutputFile: string;
  DoServe, DoMinify: Boolean;
  ReservedFile: string;
  ServerPort, ServerRoot: string;
  ServerCallbacks: TWebserverCallbacks;
  LastFileSize: Integer;
  ImageWidth: Integer;

const
  PNGPayload =
'<canvas id=c><img src=# onload=''var b=c.getContext("2d"),a=d="",w="width",h="height",t=this,i=0;c[w]=t[w];c[h]=t[h];b.drawImage(t,0,0);a=b.getImageData(0,0,c[w],c[h]).data;while(a[i*4])d+=String.fromCharCode(a[(i++)*4]);eval(d);''>';

procedure GenerateResourceJS(ResourceFile: ansistring);
var
  t, t2: Textfile;
  s, ss: ansistring;

function safestr(s: string): string;
var
  i: Integer;
begin
  result:=Uppercase(s);
  for i:=1 to Length(result) do
  if not (((result[i]>='A')and(result[i]<='Z')) or ((result[i]>='0')and(result[i]<='9'))) then
    result[i]:='_';
end;

begin
  if (ResourceFile <> '') and FileExists(ResourceFile) then
  begin
    Assignfile(t, ResourceFile);
    reset(t);
    Assignfile(t2, ExtractFilePath(ResourceFile)+'resources.gen.js');
    rewrite(t2);
    try
      while not Eof(t) do
      begin
        Readln(t, s);
        ss:=s;
        s:=ExtractFilePath(ResourceFile)+s;
        Writeln(t2, '//#define _', safestr(ss),' ', Processor.AddResource(s));
      end;
    finally
       closefile(t);
       closefile(t2);
    end;
  end;
end;

function CompressAll(OutputFile, InputStr: ansistring): Boolean;
var
  Buf: array of Byte;
  i, j, k: Integer;
  s: ansistring;
  f: File;
  fc: Integer;
  files: array of record
    filename: string;
    offset: longword;
    size: longword;
  end;

begin
  i:=Length(InputStr);
  Setlength(Buf, i + 1);
  try
  Move(InputStr[1], Buf[0], i);
  Buf[i]:=0;
  Inc(i);

  k:=0;
  Setlength(files, Processor.ResourceCount);
  for fc:=0 to Processor.ResourceCount-1 do
  begin
    s:=Processor.Resources[fc];
    files[fc].filename:=ExtractFileName(s);
    files[fc].offset:=i;
    Assignfile(f, s);
    {$i-}Reset(f, 1);{$i+}
    if ioresult<>0 then
    begin
      Writeln('Could not open ', s);
      Continue;
    end;
    try
      j:=FileSize(f);
      files[fc].Size:=j;
      Setlength(Buf, i + j);
      BlockRead(f, buf[i], j);
      i:=i + j;
    finally
      Closefile(f);
    end;
    if Processor.Verbose then
      Writeln('Adding resource ', s, ' with size ', j);
    k:=k + j;
  end;

  if Processor.ResourceCount>0 then
  begin
    Writeln('Resources size: ', k, ' (', Processor.ResourceCount, ' files)');
  end;

  fc:=Processor.ResourceCount;
  if fc > 0 then
  begin
    SetLength(Buf, i + fc * SizeOf(LongWord) + 1);
    for k:=0 to fc - 1 do
    begin
      PLongWord(@Buf[i])^:=files[k].offset;
      Inc(i, sizeof(LongWord));
    end;
    Buf[i]:=fc;
    Inc(i);
  end;
  Writeln('Uncompressed size: ', Length(Buf));
  result:=CompressToPNG(PByteArray(@Buf[0]), Length(Buf), OutputFile, ImageWidth);
  finally
     Setlength(Buf, 0);
  end;
end;

function ParseParameters: Boolean;
var
  i: Integer;
  s: ansistring;
begin
  result:=False;
  i:=1;
  InputFile:='';
  OutputFile:='';
  DoServe:=False;
  DoMinify:=False;
  ImageWidth:=4096;
  while i<=ParamCount do
  begin
    s:=Paramstr(i);
    if Pos(s[1], '/-')>0 then
    begin
      while Length(s)>1 do
      begin
        Delete(s, 1, 1);
        if s = 'server' then
        begin
          DoServe:=True;
          ServerPort:=Paramstr(i+1);
          if ServerPort = '' then
          begin
            Writeln('Expected server port!');
            Exit;
          end;
          Inc(i);
          break;
        end else
        if s = 'w' then
        begin
          try
            ImageWidth:=StrToInt(Paramstr(i+1));
          except
            Writeln('number expected for -w parameter');
          end;
          Inc(i);
          break;
        end else
        if s[1] = 'c' then Processor.StripComments:=True
        else if s[1] = 's' then Processor.StripSpaces:=True
        else if s[1] = 'r' then Processor.StripNewLines:=True
        else if s[1] = 'v' then Processor.Verbose:=True
        else if s[1] = 'm' then DoMinify:=True
        else if s[1] = 'x' then MinifierInstance.ReuseStrings:=True
        else if s[1] = 'y' then MinifierInstance.ReuseIdentifiers:=True
        else if s[1] = 'z' then MinifierInstance.DocumentHack:=True
        else
        begin
          Writeln('Invalid option ', s[1]);
          Exit;
        end;
      end;
    end else
    begin
      if InputFile = '' then
        InputFile:=s
      else if OutputFile = '' then
        OutputFile:=s
      else
      begin
        Writeln('Unexpected parameter: ', s);
        Exit;
      end;
    end;
    Inc(i);
  end;
  result:=(InputFile <> '') and (OutputFile <> '');
end;

procedure ShowHelp;
begin
  Writeln('Usage:');
  Writeln('  hermes.exe [-csrvxyz] [-server <port>] <input js file> <output html file>');
  Writeln;
  Writeln('             -server <port>  be a webserver and serve directory of input file');
  Writeln('             -c              strip comments');
  Writeln('             -s              strip spaces');
  Writeln('             -r              strip newlines');
  Writeln('             -m              minify');
  Writeln('             -v              verbose');
  Writeln('             -x              reuse strings');
  Writeln('             -y              reuse identifiers');
end;

procedure Run;
var
  s: ansistring;
begin
  try
  Processor.Clear;
  GenerateResourceJS(ServerRoot + 'resources.txt');
  if not Processor.OpenFile(InputFile) then
  begin
    Error('Could not open ' + InputFile);
    if FileExists(InputFile) then
    begin
      Writeln('Could it be your open editor? Trying again in a bit...');
      Sleep(500);
      if not Processor.OpenFile(InputFile) then
      begin
        Writeln('Nope, still failing, bummers :(');
        Exit;
      end else
        Writeln('Success!');
    end else
      Exit;
  end;

  if not Processor.Process then
  begin
    Error('Error parsing!');
    Exit;
  end;

  s:=Processor.Output;
  Writeln('Javascript size: ', Length(s));
  if DoMinify then
  begin
    MinifierInstance.ClearWordList;
    MinifierInstance.AddWordList(ReservedFile);
    s:=MinifierInstance.Process(s);
    Writeln('Minified size: ', Length(s));
  end;

  CompressAll(OutputFile, s);

  with TPNGPayloadWriter.Create(OutputFile) do
  begin
    if FileExists(ServerRoot + 'payload.txt') then
      Rebuild(OutputFile, ReadFileString(ServerRoot + 'payload.txt'))
    else
      Rebuild(OutputFile, PNGPayload);

    LastFileSize:=Size;
    Writeln('Final size: ', Size);
    Free;
  end;
  except
    on e: Exception do
      Error(e.Message);
  end;
end;

function ClientConnect(Client: TWebsocketClientThread; const uri: ansistring): Boolean;
begin
  if uri = '/hotreload' then
  begin
    result:=True;
    ServerClients.AddClient(Client);
    Client.Send('{"reload":true,"file":"' + OutputFile+'","size":'+IntToStr(LastFileSize)+'}', false);
  end else
  result:=False;
end;

procedure ClientDisconnect(Client: TWebsocketClientThread);
begin
  ServerClients.RemoveClient(Client);
end;

function ClientRequest(Client: TWebsocketClientThread; {%H-}Filename: ansistring): Boolean;
begin
  result:=True;
  Client.Response.Header.Add('Cache-Control', 'no-cache');
end;

var
  WantsRebuild: Boolean;

function ClientData({%H-}Client: TWebsocketClientThread; const data: ansistring): Boolean;
begin
  result:=data='rebuild';
  if result then
    WantsRebuild:=True;
end;

function AbortWatchCallback: Boolean;
begin
  result:=not WantsRebuild;
end;

function WaitForRebuild: Boolean;
begin
  result:=True;
{$IFDEF MSWINDOWS}
  result:=MonitorDirectory(ServerRoot, 100, 100, @AbortWatchCallback);
{$ELSE}
  while (not WantsRebuild) do
  Sleep(100);
{$ENDIF}
  WantsRebuild:=False;
end;

begin
  Processor:=TJSPreprocessor.Create;
  MinifierInstance:=TMinifier.Create;
  DoServe:=False;
  OutputFile:='';
  InputFile:='';
  LastFilesize:=0;
  ServerPort:='8099';

  if not ParseParameters then
  begin
    ShowHelp;
    Processor.Free;
    MinifierInstance.Free;
    Exit;
  end;

  ServerRoot:=ExtractFilePath(ExpandFileName(InputFile));
  if not DirectoryExists(ServerRoot) then
  begin
    Error('Could not find directory ' + ServerRoot);
  end;

  ReservedFile:=ServerRoot + 'reserved.txt';
  if not FileExists(ReservedFile) then
  begin
    ReservedFile:=ExtractFilePath(ExpandFileName(Paramstr(0))) + 'reserved.txt';
    if not FileExists(ReservedFile) then
      Error('Could not find file with reserved words!');
  end;
  Writeln('Keyword file  : ', ReservedFile);

  if DoServe then
  begin
    ServerCallbacks.OnConnect:=@ClientConnect;
    ServerCallbacks.OnData:=@ClientData;
    ServerCallbacks.OnDisconnect:=@ClientDisconnect;
    ServerCallbacks.OnRequest:=@ClientRequest;
    ServerCallbacks.OnServerStart:=nil;
    ServerCallbacks.OnStatusCode:=nil;
    ServerCallbacks.OnTerminate:=nil;
    Writeln('Work directory: ', ServerRoot);
    ServerClients:=TClientManager.Create;
    TWebsocketListenerThread.Create(ServerCallbacks, '127.0.0.1', ServerPort, ServerRoot);
    HaltOnError:=False;

    repeat
      Writeln('+------------------------------');
      Writeln('| New Build');
      Writeln('+------------------------------');
      Run;
      ServerClients.Broadcast('{"reload":true,"file":"' + OutputFile+'","size":'+IntToStr(LastFileSize)+'}');
    until not WaitForRebuild();
  end else
    Run;
end.

