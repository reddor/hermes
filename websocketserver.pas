unit websocketserver;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  syncobjs,
  synsock,
  blcksock,
  sockets,
  httphelper;

type
  TWebsocketClientThread = class;

  TWebserverDataCallback = function(Client: TWebsocketClientThread; const data: ansistring): Boolean;
  TWebserverConnect = function(Client: TWebsocketClientThread; const uri: ansistring): Boolean;
  TWebserverDisconnect = procedure(Client: TWebsocketClientThread);
  TWebserverHttpRequest = function(Client: TWebsocketClientThread; Filename: ansistring): Boolean;
  TWebserverStatusCode = procedure(Client: TwebsocketClientThread; StatusCode: Word);
  TWebserverStart = procedure(IP, Port: ansistring; Success: boolean);

  TWebserverCallbacks = record
      OnData: TWebserverDataCallback;
      OnConnect: TWebserverConnect;
      OnDisconnect: TWebserverDisconnect;
      OnRequest: TWebserverHttpRequest;
      OnStatusCode: TWebserverStatusCode;
      OnServerStart: TWebserverStart;
      OnTerminate: procedure;
  end;

  TWebsocketVersion = (wvNone, wvUnknown, wvHixie76, wvHybi07, wvHybi10, wvRFC);

  TWebsocketFrame = record
      fin, RSV1, RSV2, RSV3: Boolean;
      opcode: Byte;
      masked: Boolean;
      Length: Int64;
      Mask: array[0..3] of Byte;
    end;

  TWebsocketHeaderReadResult = (hrTimeOut, hrFail, hrSuccess);

  TWebsocketListenerThread = class;
  { TWebsocketClientThread }

  TWebsocketClientThread = class(TThread)
  private
    FCS: TCriticalSection;
    FCustomHandle: Pointer;
    FRemoteAddresS: ansistring;
    FWSVersion: TWebsocketVersion;
    FParent: TWebsocketListenerThread;
    FSocket: TTCPBlockSocket;
    FReply: THTTPReply;
    FHeader: THTTPRequest;
    FWSData: ansistring;
    FHasSegmented: Boolean;
    FSendQueueRead,
    FSendQueueWrite: longword;
    FSendQueue: array[0..1023] of record
      data: ansistring;
      binary: Boolean;
    end;
  protected
    { send file as http response }
    procedure SendFile(FileName: ansistring);
    { send status page and generate fancy page }
    procedure SendStatusCode(const Code: Word);
    { send any content }
    procedure SendContent(const MimeType, Data: ansistring; const Result: ansistring = '200 OK');
    { process regular http requests until upgrade request is received (returns true) or
      connection is closed (returns false) }
    function ServeUntilWebsocketRequest: Boolean;
    { performs websocket handshake }
    function UpgradeToWebsocket: Boolean;
    { reads websocket frame header }
    function ReadWebsocketFrame(out header: TWebsocketFrame; TimeOut: Integer): TWebsocketHeaderReadResult;
    { reads complete websocket frame if available, returns false if socket is broken }
    function ProcessWS(TimeOut: Integer): Boolean;
    { called when websocket data is received }
    procedure HandleWS(const Data: ansistring);
    { send websocket frame }
    procedure SendWS(const Data: ansistring; Binary: Boolean = False);
    { generate directory listing }
    procedure SendDirectoryListing(AbsolutePath: ansistring);
    { the thread proc }
    procedure Execute; override;
  public
    constructor Create(AClient: TSocket; AParent: TWebsocketListenerThread);
    destructor Destroy; override;
    procedure Send(const data: ansistring; Binary: Boolean);
    property Header: THTTPRequest read FHeader;
    property CustomHandle: Pointer read FCustomHandle write FCustomHandle;
    property RemoteAddress: ansistring read FRemoteAddress;
    property Response: THTTPReply read FReply;
  end;

  { TWebsocketListenerThread }

  TWebsocketListenerThread = class(TThread)
  private
    FAllowDirListing: Boolean;
    FCallbacks: TWebserverCallbacks;
    FIP, FPort: ansistring;
    FWebRoot: ansistring;
  protected
    procedure Execute; override;
  public
    constructor Create(ACallbacks: TWebserverCallbacks; AIP, APort, AWebRoot: ansistring);
    destructor Destroy; override;
    property WebRoot: ansistring read FWebRoot write FWebRoot;
    property AllowDirectoryListing: Boolean read FAllowDirListing write FAllowDirListing;
    property Callbacks: TWebserverCallbacks read FCallbacks;
  end;

implementation

uses
  registry,
  sha1,
  md5,
  base64;

var GlobalShutdown: Boolean;

function GetFileMIMEType(const AName: String): String;
var
  Registry: TRegistry;
  ext: String;
begin
  Result := '';
  ext := ExtractFileExt(AName);
  if ext='.pas' then
  begin
    result := 'text/x-pascal';
    Exit;
  end;

  if ext='.svg' then
  begin
    result := 'image/svg+xml';
    Exit;
  end;

  if ext = '.appcache' then
  begin
    result := 'text/cache-manifest';
    Exit;
  end;
  Registry := TRegistry.Create;
  try
    Registry.RootKey := HKEY_CLASSES_ROOT;
    if Registry.KeyExists(ext) then
    begin
      Registry.OpenKey(ext, false);
      Result := Registry.ReadString('Content Type');
      Registry.CloseKey;
    end else
      result:='application/binary';
  finally
      Registry.Free;
  end;
end;

function ProcessHandshakeString(const Input: ansistring): ansistring;
var
  SHA1: TSHA1Context;
  hash: ansistring;

  procedure ShaUpdate(s: ansistring);
  begin
    SHA1Update(SHA1, s[1], length(s));
  end;

type
  PSHA1Digest = ^TSHA1Digest;

begin
  SHA1Init(SHA1);
  Setlength(hash, 20);

  ShaUpdate(Input+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11');

  SHA1Final(SHA1, PSHA1Digest(@hash[1])^);
  result:=EncodeStringBase64(hash);
end;

function MD5ofStr(str: ansistring): ansistring;
type
  TDigestString = array[0..15] of Char;
var
  tempstr: TDigestString;
begin
  tempstr:=TDigestString(MDString(str, MD_VERSION_5));
  result:=tempstr;
end;

function CreateRFCHeader(opcode: Byte; Length:Int64): ansistring;
begin
  if Length>125 then
    SetLength(Result, 4)
  else
    setlength(Result, 2);

  result[1] := AnsiChar(128 + (opcode and 15));
  if Length<126 then
  begin
    result[2] := AnsiChar(Length);
  end else
  if Length < 65536 then
  begin
    result[2] := #126;
    result[3] := AnsiChar(Length shr 8);
    result[4] := AnsiChar(Length);
  end else
  begin
    Setlength(result, 10);
    result[2] := #127;
    result[3]:=AnsiChar(Length shr 56);
    result[4]:=AnsiChar(Length shr 48);
    result[5]:=AnsiChar(Length shr 40);
    result[6]:=AnsiChar(Length shr 32);
    result[7]:=AnsiChar(Length shr 24);
    result[8]:=AnsiChar(Length shr 16);
    result[9]:=AnsiChar(Length shr 8);
    result[10]:=AnsiChar(Length);
  end;
end;

{ TWebsocketClientThread }

function TWebsocketClientThread.ServeUntilWebsocketRequest: Boolean;
var
  RequestStr, Target: ansistring;
  i: Integer;
begin
  result:=False;
  while not Terminated do
  begin
    RequestStr:=FSocket.RecvTerminated(30000, #13#10#13#10);
    if (RequestStr='') then
      Break;
    i:=FHeader.Read(@RequestStr[1], Length(RequestStr));
    if i<=0 then
      Break;
    Delete(RequestStr, 1, i);
    FReply.Clear(FHeader.Version);

    if not URLPathToAbsolutePath(FHeader.Url, FParent.WebRoot, Target) then
    begin
      SendStatusCode(403);
      Break;
    end;

    if (FHeader.Action <> 'GET') and (FHeader.Action <> 'HEAD') then
    begin
      SendStatusCode(405);
      Break;
    end;

    if (FHeader.version = 'HTTP/1.1') and
       (Pos('UPGRADE', UpperCase(FHeader.header['Connection']))>0) and
       (Uppercase(FHeader.header['Upgrade'])='WEBSOCKET') then
    begin
      result:=True;
      Exit;
    end;

    if DirectoryExists(Target) then
    begin
      if Target[Length(Target)]<>'/' then
      begin
        FReply.Header.Add('Location', FHeader.Url+'/');
        SendStatusCode(301);
      end else
      begin
        if FileExists(Target + 'index.html') then
        begin
          SendFile(Target+'index.html');
        end else if FParent.AllowDirectoryListing then
          SendDirectoryListing(Target)
        else
          SendStatusCode(403);
      end;
    end else
    if FileExists(Target) then
    begin
      SendFile(Target);
    end else
      SendStatusCode(404);

    if FHeader.Header['Connection']<>'keep-alive' then
      Break;
  end;
end;

function TWebsocketClientThread.UpgradeToWebsocket: Boolean;
var
  s,s2: ansistring;
begin
  result:=False;
  s := FHeader.header['Sec-WebSocket-Version'];

  Freply.header.add('Upgrade', 'WebSocket');
  Freply.header.add('Connection', 'Upgrade');

  s2 := FHeader.header['Sec-WebSocket-Protocol'];
  if pos(',', s2)>0 then
    Freply.header.Add('Sec-WebSocket-Protocol', Copy(s2, 1, pos(',', s2)-1))
  else if length(s2)>0 then
    Freply.header.Add('Sec-WebSocket-Protocol', s2);

  FWSVersion := wvUnknown;
  if s = '' then
  begin
    // draft-ietf-hybi-thewebsocketprotocol-00 / hixie76 ?
    SendStatusCode(426);
    Exit;
  end else
  if s = '7' then
  begin
    // draft-ietf-hybi-thewebsocketprotocol-07
    FWSVersion := wvHybi07;
  end else
  if s = '8' then
  begin
    // draft-ietf-hybi-thewebsocketprotocol-10
    FWSVersion := wvHybi10;
  end else
  if s = '13' then
  begin
    // rfc6455
    FWSVersion := wvRFC;
  end else
  begin
    SendStatusCode(426);
    Exit;
  end;


  { there are only minor differences between version 7, 8 & 13, it's basically
    the same handshake }
  if Assigned(FParent.Callbacks.OnConnect) and
     FParent.Callbacks.OnConnect(Self, FHeader.Url) then
  begin
    Freply.header.Add('Sec-WebSocket-Accept', ProcessHandshakeString(FHeader.header['Sec-WebSocket-Key']));
    if FHeader.header.Exists('Sec-WebSocket-Protocol')<>-1 then
       Freply.header.Add('Sec-WebSocket-Protocol', FHeader.header['Sec-WebSocket-Protocol']);

    FSocket.SendString(FReply.Build('101 Switching protocols'));
    result:=True;
  end else
  begin
    result:=False;
    SendStatusCode(400);
  end;
end;

function TWebsocketClientThread.ReadWebsocketFrame(out
  header: TWebsocketFrame; TimeOut: Integer
  ): TWebsocketHeaderReadResult;
var
  InBuffer: packed array[0..1] of Byte;
  SizeBuffer: array[0..7] of Byte;
begin
  result:=hrTimeOut;
  if FSocket.RecvBufferEx(@InBuffer[0], SizeOf(InBuffer), TimeOut) <> SizeOf(InBuffer) then
  begin
    if FSocket.LastError <> WSAETIMEDOUT then
      result:=hrFail;
    Exit;
  end;
  result:=hrFail;

  header.fin := Inbuffer[0] and 128 <> 0;
  header.RSV1 := Inbuffer[0] and 64 <> 0;
  header.RSV2 := Inbuffer[0] and 32 <> 0;
  header.RSV3 := Inbuffer[0] and 16 <> 0;
  header.opcode := Inbuffer[0] and 15;
  header.masked := Inbuffer[1] and 128 <> 0;
  header.length := Inbuffer[1] and 127;

  if header.length = 126 then
  begin
    InBuffer[0]:=0;
    InBuffer[1]:=0;
    if FSocket.RecvBufferEx(@InBuffer[0], SizeOf(InBuffer), TimeOut) <> SizeOf(InBuffer) then
        Exit;
    header.length:=Inbuffer[1] + Inbuffer[0] * 256;
  end else if header.length = 127 then
  begin
    if FSocket.RecvBufferEx(@SizeBuffer[0], SizeOf(SizeBuffer), TimeOut) <> SizeOf(SizeBuffer) then
        Exit;
     header.length:=SizeBuffer[7] + SizeBuffer[6] * $100 +
                    SizeBuffer[5] * $10000 + SizeBuffer[4] * $1000000 +
                    SizeBuffer[3] * $100000000 + SizeBuffer[2] * $10000000000 +
                    SizeBuffer[1] * $1000000000000 + SizeBuffer[0] * $100000000000000;
  end;
  if header.Masked then
  begin
    if FSocket.RecvBufferEx(@header.Mask[0], 4, 30000) <> 4 then
      Exit;
  end;

  if header.opcode = 255 then
  begin
    Exit;
  end;
  result:=hrSuccess;
end;

function TWebsocketClientThread.ProcessWS(TimeOut: Integer): Boolean;
var
  hdr: TWebsocketFrame;
  s: ansistring;
  i: Integer;
begin
  result:=false;
  case ReadWebsocketFrame(hdr, TimeOut) of
    hrTimeOut:
    begin
      result:=True;
      Exit;
    end;
    hrFail:
    begin
      Writeln('Reading from socket failed');
      Exit;
    end;
    hrSuccess:
    begin
      result:=False;
      s:=FSocket.RecvBufferStr(hdr.Length, 30000);
      if Length(s)<>hdr.Length then
      begin
        Writeln('Invalid websocket packet length');
        Exit;
      end;
      if not hdr.masked then
      begin
        Writeln('Got unmasked packet');
        Exit; // only accept masked frames
      end;
      for i:=1 to hdr.Length do
        s[i]:=AnsiChar(Byte(s[i]) xor hdr.mask[(i-1) mod 4]);
      result:=True;
      case hdr.opcode of
        254: result:=False;
        0: begin
          if not FHasSegmented then
          begin
            Writeln('Got unsegmented packet when expecting otherwise');
            result:=False;
            Exit;
          end;
          FWSData:=FWSData + s;
          if hdr.fin then
          begin
            HandleWS(FWSData);
            FWSData:='';
          end;
        end;
        1,2: begin
          if FHasSegmented then
          begin
            Writeln('Got segmented packet when expecting otherwise');
            result:=False;
            Exit;
          end;
          FWSData:=s;
          if not hdr.fin then
            FHasSegmented:=True
          else
          begin
            HandleWS(FWSData);
            FWSData:='';
          end;
        end;
        8: begin
          FSocket.SendString(CreateRFCHeader(hdr.opcode, Length(s))+s);
          result:=False;
        end;
        9: FSocket.SendString(CreateRFCHeader(10, Length(s)) + s);
        10: begin
          // pong
        end;
        else
        begin
          Writeln('Got invalid packet');
          result:=False;
        end;
      end;
    end;
  end;
end;

procedure TWebsocketClientThread.HandleWS(const Data: ansistring);
begin
  if Assigned(FParent.Callbacks.OnData) then
  begin
    if not FParent.Callbacks.OnData(Self, Data) then
      Terminate;
  end else
    Terminate;
end;

procedure TWebsocketClientThread.SendWS(const Data: ansistring; Binary: Boolean
  );
begin
  if Binary then
    FSocket.SendString(CreateRFCHeader(2, length(data))+data)
  else
    FSocket.SendString(CreateRFCHeader(1, length(data))+data);
end;

procedure TWebsocketClientThread.SendDirectoryListing(AbsolutePath: ansistring);
var
  SR: TSearchRec;
  i: Integer;
  s: ansistring;
begin
  s:='<!doctype html><html><head><title>Directory Listing</title></head><body><h1>Directory Listing</h1>';

  i:=FindFirst(AbsolutePath + '/*.*', faAnyFile, SR);
  while i = 0 do
  begin
    s:=s + '<div><a href="' + SR.Name + '">' + SR.Name + '</a></div>';
    i:=FindNext(SR);
  end;
  FindClose(SR);
  SendContent('text/html', s);
end;

procedure TWebsocketClientThread.SendFile(FileName: ansistring);
var
  f: File;
  buf: Array[0..32768] of Byte;
  BufRead: Integer;
  LastModified: TDateTime;
begin
  if Assigned(FParent.Callbacks.OnRequest) then
  begin
    if not FParent.Callbacks.OnRequest(self, FileName) then
    begin
      SendStatusCode(403);
      Exit;
    end;
  end;
  LastModified:=FileDateToDateTime(FileAge(FileName));
  Freply.header.Add('Last-Modified', DateTimeToHTTPTime(LastModified));
  if FHeader.header.Exists('If-Modified-Since')<>-1 then
  begin
    if HTTPTimeToDateTime(FHeader.header['If-Modified-Since']) = LastModified then
    begin
      FSocket.SendString(Freply.Build('304 Not Modified'));
      Exit;
    end;
  end;

  Assignfile(f, FileName);
  {$i-}reset(f, 1);{$i+}
  if ioresult<>0 then
  begin
    SendStatusCode(403);
    Exit;
  end;

  FReply.Header.Add('Content-Length', IntToStr(FileSize(f)));
  FReply.Header.Add('Content-Type', GetFileMIMEType(FileName));
  FSocket.SendString(FReply.Build('200 OK'));
  while not Eof(f) do
  begin
    BlockRead(f,  {%H-}Buf, SizeOf(Buf),  {%H-}BufRead);
    if BufRead>0 then
      FSocket.SendBuffer(@Buf[0], BufRead);
  end;
  CloseFile(f);
end;

procedure TWebsocketClientThread.SendStatusCode(const Code: Word);
var
  title, desc: ansistring;
begin
  if Assigned(FParent.Callbacks.OnStatusCode) then
  begin
    FParent.Callbacks.OnStatusCode(self, Code);
  end;
  GetHTTPStatusCode(Code, Title, Desc);
  SendContent('text/html', '<!doctype html><html><head>'+
  '<title>'+title+'</title></head><body><h1>'+title+'</h1>'+desc+'<hr></body></html>', IntToStr(Code)+' '+Title);
end;

procedure TWebsocketClientThread.SendContent(const MimeType, Data: ansistring;
  const Result: ansistring);
begin
  if MimeType<>'' then
    FReply.Header.Add('Content-Type', MimeType);
  if Length(Data)>0 then
    FReply.Header.Add('Content-Length', IntToStr(length(Data)));

  if FHeader.action = 'HEAD' then
    FSocket.SendString(freply.build(result))
  else
    FSocket.SendString(freply.Build(result) + data);
end;

procedure TWebsocketClientThread.Execute;
var
  s: ansistring;
  i: Longword;
begin
  try
    if ServeUntilWebsocketRequest then
    begin
      if UpgradeToWebsocket then
      begin
        while not (Terminated or GlobalShutdown) do
        begin
          if not ProcessWS(10) then
            Break;
          while FSendQueueRead <> FSendQueueWrite do
          begin
            FCS.Enter;
            try
              i:=FSendQueueRead mod length(FSendQueue);
              s:=FSendQueue[i].Data;
              FSendQueue[i].Data:='';
              Inc(FSendQueueRead);
            finally
              FCS.Leave;
            end;
            SendWS(s);
          end;
        end;
        if Assigned(FParent.Callbacks.OnDisconnect) then
          FParent.Callbacks.OnDisconnect(Self);
      end;
    end;
  except

  end;
  FSocket.Free;
  FHeader.Free;
  FReply.Free;
end;

constructor TWebsocketClientThread.Create(AClient: TSocket;
  AParent: TWebsocketListenerThread);
begin
  FWSVersion:=wvNone;
  FParent:=AParent;
  FSocket:=TTCPBlockSocket.Create;
  FSocket.Socket:=AClient;
  FHeader:=THTTPRequest.Create;
  FReply:=THTTPReply.Create;
  inherited Create(False);
  FreeOnTerminate:=True;
  FCS:=TCriticalSection.Create;
  FRemoteAddress:=FSocket.GetRemoteSinIP();
end;

destructor TWebsocketClientThread.Destroy;
begin
  inherited Destroy;
  FCS.Free;
end;

procedure TWebsocketClientThread.Send(const data: ansistring; Binary: Boolean);
begin
  FCS.Enter;
  try
    FSendQueue[FSendQueueWrite mod Length(FSendQueue)].data:=data;
    FSendQueue[FSendQueueWrite mod Length(FSendQueue)].binary:=Binary;
    FSendQueueWrite:=FSendQueueWrite + 1;
  finally
    FCS.Leave;
  end;
end;

{ TWebsocketListenerThread }

procedure TWebsocketListenerThread.Execute;
var
  ClientSock: TSocket;
  FSock: TTCPBlockSocket;
begin
  FSock:=TTCPBlockSocket.Create;
  with FSock do
  begin
    CreateSocket;
    SetLinger(true, 1000);
    bind(FIP, FPort);
    listen;
    if Assigned(Callbacks.OnServerStart) then
      Callbacks.OnServerStart(FIP, FPort, LastError = 0);
    repeat
      try
      if canread(500) then
      begin
        ClientSock:=accept;
        if LastError = 0 then
        begin
          TWebsocketClientThread.Create(ClientSock, Self);
          // FParent.Accept(ClientSock, FSSL);
        end;
      end;
      except
        on e: Exception do Writeln(e.Message);
      end;
    until Terminated;
    FSock.CloseSocket;
  end;
  FSock.Free;
  if Assigned(Callbacks.OnTerminate) then
    Callbacks.OnTerminate();
end;

constructor TWebsocketListenerThread.Create(ACallbacks: TWebserverCallbacks;
  AIP, APort, AWebRoot: ansistring);
begin
  FCallbacks:=ACallbacks;
  GlobalShutdown:=False;
  FIP:=AIP;
  FPort:=APort;
  FWebRoot:=AWebRoot;
  inherited Create(False);
end;

destructor TWebsocketListenerThread.Destroy;
begin
  GlobalShutdown:=True;
  inherited Destroy;
end;

end.

