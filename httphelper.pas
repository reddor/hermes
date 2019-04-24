unit httphelper;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  { THTTPRequestFields }

  THTTPRequestFields = class
  private
    FCount: Integer;
    FRequests: array of record
      Name,
      Value: ansistring;
    end;
    function GetHeader(const index: ansistring): ansistring;
    function Find(const Name: ansistring): ansistring;
    procedure SetHeader(const index: ansistring; AValue: ansistring);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Name, Value: ansistring);
    procedure Clear;
    function Exists(Name: ansistring): Integer;
    procedure Get(Index: Integer; out Name, Value: ansistring);
    function Generate: ansistring;

    property Count: Integer read FCount;
    property Requests[const index: ansistring]: ansistring read GetHeader write SetHeader; default;
  end;

  THTTPRangeSegment = record
    min, max: int64;
  end;

  THTTPPostData = class;

  { THTTPRequest }
  THTTPRequest = class
  private
    FAction: ansistring;
    FCookies: THTTPRequestFields;
    FURL: ansistring;
    FVersion: ansistring;
    FHeader: THTTPRequestFields;
    FParameters: ansistring;
    FRangeSegments: array of THTTPRangeSegment;
    FPostData: THTTPPostData;
    function GetRangeCount: Integer;
    function GetRangeSegment(Index: Integer): THTTPRangeSegment;
  public
    constructor Create;
    destructor Destroy; override;
    function Read(Buffer: PByteArray; BufferSize: LongWord): Integer;
    { returns size of ranges, or -1 if ranges are invalid }
    function ValidateRange(FileSize: Int64): Int64;
    function Generate: ansistring;

    function GetCookies(aTimeout: ansistring = ''): ansistring;
    property POSTData: THTTPPostData read FPostData;
    property Action: ansistring read FAction write FAction;
    property Version: ansistring read FVersion write FVersion;
    property Url: ansistring read FURL write FURL;
    property Parameters: ansistring read FParameters write FParameters;
    property Header: THTTPRequestFields read FHeader;
    property RangeCount: Integer read GetRangeCount;
    property Range[Index: Integer]: THTTPRangeSegment read GetRangeSegment;
    property Cookies: THTTPRequestFields read FCookies;
  end;

  { THTTPPostData }

  THTTPPostData = class
  private
    FRequest: THTTPRequest;
    FEntities: THTTPRequestFields;
  public
    constructor Create(Request: THTTPRequest);
    destructor Destroy; override;
    procedure Clear;
    function readstr(var str: ansistring): Boolean;
    property Entities: THTTPRequestFields read FEntities write FEntities;
  end;

  { THTTPReply }

  THTTPReply = class
  private
    FResponse: ansistring;
    FVersion: ansistring;
    FHeader: THTTPRequestFields;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear(Version: ansistring);

    function Build(Response: ansistring): ansistring;
    function Read(Reply: ansistring): Boolean;
    property Header: THTTPRequestFields read FHeader;
    property Response: ansistring read FResponse write FResponse;
    property Version: ansistring read FVersion write FVersion;
  end;


function FileExistsAndAge(const TheFile: ansistring; out Time: TDateTime): Boolean;
function FileLastModified(const TheFile: ansistring): TDateTime;
function DateTimeToHTTPTime(Time: TDateTime): ansistring;
function HTTPTimeToDateTime(Time: ansistring): TDateTime;

function URLDecode(const Input: ansistring): ansistring;
function URLPathToAbsolutePath(const Url, BaseDir: ansistring; out Path: ansistring): Boolean;
procedure GetHTTPStatusCode(ErrorCode: Word; out Title, Description: ansistring);

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Math,
  DateUtils;

const
  HexChars: string[16] = '0123456789abcdef';


procedure GetHTTPStatusCode(ErrorCode: Word; out Title, Description: ansistring);
begin
  Description:='';
  case ErrorCode of
    100: Title:='Continue';
    101: Title:='Switching Protocols';
    102: Title:='Processing';
    200: Title:='OK';
    201: Title:='Created';
    202: Title:='Accepted';
    203: Title:='Non-Authoritative Information';
    204: Title:='No content';
    205: Title:='Reset Content';
    206: Title:='Partial Content';
    207: Title:='Multi-Status';
    208: Title:='Already reported';
    226: Title:='IM used';

    300:begin
      Title:='Multiple Choices';
      Description:='Multiple options are available for this resource';
    end;
    301:begin
      Title:='Moved';
      Description:='The resource has moved.';
    end;
    302:begin
      Title:='Found';
      Description:='The resource has moved temporarily, see other.';
    end;
    303:begin
      Title:='See other';
      Description:='The resource you requested is available elsewhere.';
    end;
    304: Title:='Not modified';
    305:begin
      Title:='Use Proxy';
      Description:='This resource is only available through a proxy.';
    end;
    306: Title:='Switch Proxy';
    307:begin
      Title:='Temporary Redirect';
      Description:='The request should be repeated with another URI.';
    end;
    308:begin
      Title:='Permanent Redirect';
      Description:='The request should be repeated with another URI.';
    end;

    400:begin
      Title:='Bad Request';
      Description:='The server could not decipher your request.';
    end;
    401:begin
      Title:='Unauthorized';
      Description:='Authorization is required to view this resource.';
    end;
    402:begin
      Title:='Payment Required';
      Description:='Reserved for future use.';
    end;
    403:begin
      Title:='Forbidden';
      Description:='You do not have the right permissions to view this resource.';
    end;
    404:begin
      Title:='Not Found';
      Description:='The resource could not be found.';
    end;
    405:begin
      Title:='Method not allowed';
      Description:='This request method is not supported for this resource.';
    end;
    406:begin
      Title:='Not acceptable';
      Description:='The resource is not acceptable for you.';
    end;
    407:begin
      Title:='Proxy Authentication Required';
      Description:='You must first authenticate yourself with the proxy.';
    end;
    408:begin
      Title:='Request Timeout';
      Description:='You did not produce a request within a time that the server deems socially acceptable.';
    end;
    409:begin
      Title:='Conflict';
      Description:='Your request could not be processed because of a conflict within the request.';
    end;
    410:begin
      Title:='Gone';
      Description:='This resource is gone forever.';
    end;
    411:begin
      Title:='Length Required';
      Description:='Your request did not specify the length of your content.';
    end;
    412:begin
      Title:='Precondition Failed';
      Description:='The preconditions in your request could not be fulfilled.';
    end;
    413:begin
      Title:='Payload Too Large';
      Description:='Your request is larger than what the server is willing to handle.';
    end;
    414:begin
      Title:='URI Too Long';
      Description:='The URI in your request is too long.';
    end;
    415:begin
      Title:='Unsupported Media Type';
      Description:='The media type you supplied is not supported for this resource.';
    end;
    416:begin
      Title:='Range Not Satisfiable';
      Description:='The range you requested cannot be served.';
    end;
    417:begin
      Title:='Expectation Failed';
      Description:='The server cannot fulfill the requirements in your request.';
    end;
    418:begin
      Title:='I''m a teapot';
      Description:='The requested entity body is short and stout.';
    end;
    421:begin
      Title:='Misdirected Request';
      Description:='Your request was directed at a server that is not able to produce a response.';
    end;
    422:begin
      Title:='Unprocessable Entity';
      Description:='Your request was well-formed but contained semantic errors';
    end;
    423:begin
      Title:='Locked';
      Description:='This resource is locked.';
    end;
    424:begin
      Title:='Failed Dependency';
      Description:='Your request failed because a previous request failed.';
    end;
    426:begin
      Title:='Upgrade Required';
      Description:='You should upgrade to a better protocol.';
    end;
    428:begin
      Title:='Precondition Required';
      Description:='Your request must be conditional.';
    end;
    429:begin
      Title:='Too Many Requests';
      Description:='You have exceeded the maximum number of requests for a given time.';
    end;
    431:begin
      Title:='Request Header Fields Too Large';
      Description:='The header fields in your request are too large.';
    end;
    451:begin
      Title:='Unavailable For Legal Reasons';
      Description:='The resource you are trying to access is not available in your country because of legal reasons.';
    end;

    500:begin
      Title:='Internal Server Error';
      Description:='There is something wrong with the server.';
    end;
    501:begin
      Title:='Not Implemented';
      Description:='The server does not undestand your request';
    end;
    502:begin
      Title:='Bad Gateway';
      Description:='The server received an invalid response from the upstream server.';
    end;
    503:begin
      Title:='Service Unavailable';
      Description:='The server is currently unavailable.';
    end;
    504:begin
      Title:='Gateway Timeout';
      Description:='The upstream server did not response in a timely matter.';
    end;
    505:begin
      Title:='HTTP Version Not Supported';
      Description:='The server does not support the HTTP protocol version in your request.';
    end;
    506:begin
      Title:='Variant Also Negotiates';
      Description:='For more information, read RFC 2295!';
    end;
    507:begin
      Title:='Insufficient Storage';
      Description:='The server is unable to store the representation needed to complete the request.';
    end;
    508:begin
      Title:='Loop Detected';
      Description:='The server detected an infinite loop while trying to process your request.';
    end;
    510:begin
      Title:='Not Extended';
      Description:='Your request cannot be fulfilled without further extensions.';
    end;
    511:begin
      Title:='Network Authentication Required';
      Description:='I''m a captive portal!';
    end;

    else
      begin
        Title:='Error '+IntToStr(ErrorCode);
        Description:='Unknown error code';
      end;
  end;
end;

function URLDecode(const Input: ansistring): ansistring;
var
  i, j, k: Integer;
begin
  result:=Input; // StringReplace(Input, '+', ' ', [rfReplaceAll]);
  i:=Pos('%', result);
  while (i>0) and (i<=Length(result)-2) do
  begin
    j:=(Pos(lowerCase(result[i+1]), HexChars)-1);
    k:=(Pos(lowercase(result[i+2]), HexChars)-1);
    if(j<0)or(k<0) then
      Break; // invalid url encoding
    result[i]:=Chr(j*16 + k);
    Delete(result, i+1, 2);
    i:=Pos('%', result);
  end;
end;

{ returns true if url-path is valid, returns BaseDir + Url. returns false if
  url path is invalid (e.g. "/../../etc/passwd") }
function URLPathToAbsolutePath(const Url, BaseDir: ansistring; out Path: ansistring): Boolean;
var
  s: string;
  i, j: Integer;
begin
  result:=False;

  s:=Url;
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
    while (j>0)and(s[i] <> '/') do
      Dec(j);
    if j=0 then
      Exit;
    Delete(s, j, 3+i-j);
  end;
  Path:=BaseDir + s;
  result:=True;
end;

function GetElementFromString(const Str, Element: ansistring): string;
var
  i, j, k: Integer;
  isQuoted: Boolean;
begin
  isQuoted := False;
  result := '';
  isQuoted := False;
  i := 1;
  j := 1;
  if Str = '' then Exit;
  repeat
    if Str[i] ='"' then
      isQuoted := not isQuoted;

    if (Str[i] = Element[j]) and (not isQuoted) then
    begin
      inc(j);
      if j > Length(Element) then
      begin
        if i + 1 < Length(Str) then
          if Str[i+1] = '=' then
          begin
            j := i + 2;
            k := j;
            while (k <= length(Str)) and (Str[k]<>';') do
              inc(k);

            result := Copy(Str, j, k - j);
            if Length(result)>1 then
            if (result[1] = '"')and(result[length(result)] = '"') then
              result := Copy(Result, 2, Length(Result)-2);
            Exit;
          end;
      end;
    end else
      j := 1;

    inc(i);
  until i>Length(str);
end;

{$IFDEF MSWINDOWS}
function FileLastModified(const TheFile: ansistring): TDateTime;
var
  FileH : THandle;
  LocalFT : TFileTime;
  DosFT : DWORD;
  FindData : TWIN32FindDataA;
begin
  Result := 0;
  LocalFT.dwHighDateTime:=0;
  LocalFT.dwLowDateTime:=0;
  DosFT:=0;
  FileH := FindFirstFileA(PAnsiChar(TheFile), {%H-}FindData);
  if FileH <> INVALID_HANDLE_VALUE then begin
   Windows.FindClose(FileH) ;
   if (FindData.dwFileAttributes AND
       FILE_ATTRIBUTE_DIRECTORY) = 0 then
    begin
     FileTimeToLocalFileTime(FindData.ftLastWriteTime,LocalFT) ;
     FileTimeToDosDateTime(LocalFT,LongRec(DosFT).Hi,LongRec(DosFT).Lo);
     Result := FileDateToDateTime(DosFT) ;
    end;
  end;
end;
{$ELSE}
function FileLastModified(const TheFile: ansistring): TDateTime;
begin
  result := FileDateToDateTime(FileAge(TheFile));
end;
{$ENDIF}

{ check if file exists and return file size if so }
function FileExistsAndAge(const TheFile: ansistring; out Time: TDateTime): Boolean;
var
  x: longint;
begin
  x:=FileAge(TheFile);
  if x=-1 then
  begin
    result:=False;
    Exit;
  end;
  result:=True;
  Time:=FileDateToDateTime(x);
end;

function DateTimeToHTTPTime(Time: TDateTime): ansistring;
const
  Days: array[1..7] of string = ('Mon','Tue','Wed','Thu', 'Fri', 'Sat', 'Sun');
  Months: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  year,month,day,hour,minute,second,ms: word;

  function LeadingZero(const Input: Word): string;
  begin
    if (Input<10) then
      result := '0'+IntToStr(Input)
    else
      Result := IntToStr(Input);
  end;

begin
  DecodeDateTime(Time, year, month, day, hour, minute, second, ms);

  result := ansistring( Days[DayOfTheWeek(Time)]+', ' + LeadingZero(Day)+' '+
            Months[month] + ' ' + IntToStr(year)+' '+
            LeadingZero(hour)+':'+LeadingZero(minute)+':'+LeadingZero(second)+' GMT' );
end;

function HTTPTimeToDateTime(Time: ansistring): TDateTime;
const
  Months = 'JanFebMarAprMayJunJulAugSepOctNovDec';

var
  year,month,day,hour,minute,second: word;
  curPos: Integer;

  function GetValue: string;
  var
    i: Integer;
  begin
    i := curPos + 1;
    while (i < length(Time)) and (Time[i]<>' ') and (Time[i]<>':') do
      inc(i);
    Result := Copy(string(Time), curPos+1, (i - curPos - 1));
    curPos := i;
  end;

begin
  curPos := pos(ansistring(', '), Time)+1;

  day := StrToIntDef(GetValue, 1);
  month := 1 + pos(GetValue, Months) div 3;
  year := StrToIntDef(GetValue, 1985);
  hour := StrToIntDef(GetValue, 12);
  minute := StrToIntDef(GetValue, 0);
  second := StrToIntDef(GetValue, 12);

  Result := EncodeDateTime(year, month, day, hour, minute, second, 0)
end;

{ THTTPRequestFields }

procedure THTTPRequestFields.Add(const Name, Value: ansistring);
var
  i: Integer;
begin
  i := Exists(Name);
  if (i<>-1)and(Name<>'Set-Cookie') then
  begin
    FRequests[i].Value := Value;
    Exit;
  end;

  if Length(FRequests)<=FCount then
    setlength(FRequests, FCount + 16);

  FRequests[FCount].Name := Name;
  FRequests[FCount].Value := Value;
  Inc(FCount);
end;

procedure THTTPRequestFields.Clear;
begin
  FCount := 0;
  SetLength(FRequests, 16);
end;

function THTTPRequestFields.Find(const Name: ansistring): ansistring;
var
  i: Integer;
begin
  for i:=0 to FCount-1 do
    if FRequests[i].Name = Name then
    begin
      Result := FRequests[i].Value;
      Exit;
    end;

  result := '';
end;

procedure THTTPRequestFields.SetHeader(const index: ansistring;
  AValue: ansistring);
begin
  Add(Index, AValue);
end;

constructor THTTPRequestFields.Create;
begin
  Clear;
end;

destructor THTTPRequestFields.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function THTTPRequestFields.GetHeader(const index: ansistring): ansistring;
begin
  result := Find(index);
end;

procedure THTTPRequestFields.Get(Index: Integer; out Name, Value: ansistring);
begin
  if (Index<0)or(Index>=FCount) then
    Exit;

  Name := FRequests[Index].Name;
  Value := FRequests[Index].Value;
end;

function THTTPRequestFields.Generate: ansistring;
var
  i: Integer;
begin
  result:='';
  if FCount = 0 then
    Exit;
  result:=FRequests[0].Name+': '+FRequests[0].Value;

  for i:=1 to FCount-1 do
    result:=result + #13#10 + FRequests[i].Name + ': '+ FRequests[i].Value;
end;

function THTTPRequestFields.Exists(Name: ansistring): Integer;
var
  i: Integer;
begin
  result := -1;
  for i:=0 to FCount-1 do
    if FRequests[i].Name = Name then
  begin
    Result:= i;
    Exit;
  end;
end;

{ THTTPRequest }

constructor THTTPRequest.Create;
begin
  FAction:='GET';
  FVersion:='HTTP/1.1';
  FHeader := THTTPRequestFields.Create;
  FPostData := THTTPPostData.Create(Self);
  FCookies := THTTPRequestFields.Create;
end;

destructor THTTPRequest.Destroy;
begin
  FHeader.Free;
  FPostData.Free;
  FCookies.Free;
  Setlength(FRangeSegments, 0);
  inherited;
end;

function THTTPRequest.Read(Buffer: PByteArray; BufferSize: LongWord): Integer;
var
  strpos: Integer;
  s: ansistring;
  i, j: Integer;

  function GetLine: ansistring;
  var
    i, start: integer;
  begin
    start:=strpos;
    i:=strpos;
    while (i<BufferSize) and (Buffer^[i]<>13) do
      Inc(i);
    Setlength(Result, i-start);
    if (i-strpos>0) then
      Move(Buffer^[Start], Result[1], i-strpos);
    strpos:=i+1;
    if (BufferSize>strpos) and (Buffer^[strpos] = 10) then
      Inc(strpos);
  end;

begin
  result := -1;
  strpos:=0;
  Setlength(FRangeSegments, 0);

  FPostData.Clear;
  FCookies.Clear;

  s:=GetLine;

  j:=-1;
  for i:=1 to Min(10, Length(s)) do
    if s[i] = ' ' then
    begin
     j:=i;
     Break;
    end;
  if j=-1 then
    Exit;

  FAction:=Copy(s, 1, j-1);
  i:=j;

  i:=i+1;
  j:=i+1;
  while (j<Length(s))and(s[j]<>' ') do
  begin
    inc(j);
  end;

  FURL:=Copy(s, i, j-i);
  if Pos('?', FURL)>0 then
  begin
    FParameters := Copy(FURL, Pos('?', FURL)+1, length(FURL));
    Delete(FURL, pos('?', FURL), Length(FURL));
  end else
    FParameters:='';

  FURL:=URLDecode(FUrl);
  i:=j+1;

  FVersion := Copy(s, i, Length(s));
  FHeader.Clear;

  if (FVersion <> 'HTTP/1.0') and (FVersion <> 'HTTP/1.1') then
    Exit;

  repeat
    s := getline;
    if pos(': ', s)>0 then
    begin
      FHeader.Add(Copy(s, 1, Pos(': ', s)-1), Copy(s, pos(': ', s)+2, length(s)));
    end else
      Break;
  until (s = ''); // blank line => header done

  if s<>'' then
    Exit;

  if FHeader.Exists('Cookie')<>-1 then
  begin
    s := FHeader['Cookie'];
    while length(s)>0 do
    begin
      i:=Pos('=', s);
      j:=Pos(';', s);
      if (i>=j)and(j<>0)then
        Break;
      if j>0 then
      begin
        FCookies.Add(Trim(Copy(s, 1, i-1)), Trim(Copy(s, i+1, j-(i+1))));
        delete(s, 1, j);
      end else
      begin
        FCookies.Add(Trim(Copy(s, 1, i-1)), Trim(Copy(s, i+1, Length(s))));
        s:='';
      end;
    end;
  end;

  if FHeader.Exists('Range')<>-1 then
  try
    s := FHeader['Range'];
    if pos('BYTES', Uppercase(s))=1 then
    begin
      if pos('=', s)>pos(' ', s) then
        Delete(s, 1, pos('=', s))
      else
        Delete(s, 1, pos(' ', s));
      repeat
        i := Length(FRangeSegments);
        setlength(FRangeSegments, i + 1);
        FRangeSegments[i].min := StrToIntDef(Copy(s, 1, pos('-', s)-1), -1);
        Delete(s, 1, pos('-', s));
        if pos(',', s)>0 then
        begin
          FRangeSegments[i].max := StrToIntDef(Copy(s, 1, pos(',', s)-1), -1);
          Delete(s, 1, pos(',', s));
        end else
        begin
          if s = '' then
            FRangeSegments[i].max := -1
          else
            FRangeSegments[i].max := StrToInt(s);
          Break;
        end;
      until s = '';
    end;
  except
    Setlength(FRangeSegments, 0);
  end;

  result:=strpos;
end;

function THTTPRequest.ValidateRange(FileSize: Int64): Int64;
var
  i: Integer;
begin
  result:=0;
  for i:=0 to RangeCount-1 do
  begin
    if (FRangeSegments[i].min = -1) and (FRangeSegments[i].max = -1) then
    begin
      result:=-1;
      Exit;
    end else
    if (FRangeSegments[i].min = -1) then
    begin
      FRangeSegments[i].min:=FileSize - FRangeSegments[i].max;
      FRangeSegments[i].max:=FileSize - 1;
    end else
    if (FRangeSegments[i].max = -1) then
    begin
      FRangeSegments[i].max:=FileSize-1;
    end;
    if (FRangeSegments[i].min >= FileSize) or (FRangeSegments[i].max >= FileSize) then
    begin
      Result:=-1;
      Exit;
    end;
    Inc(Result, 1 + FRangeSegments[i].max - FRangeSegments[i].min);
  end;
end;

function THTTPRequest.Generate: ansistring;
begin
  result:=FAction + ' ' + FURL;

  if FParameters<>'' then
    result:=result + '?' + FParameters;

  result:=result + ' '+FVersion + #13#10 +
          FHeader.Generate;

  result:=result + #13#10#13#10;
end;

function THTTPRequest.GetRangeCount: Integer;
begin
  result := length(FRangeSegments);
end;

function THTTPRequest.GetRangeSegment(Index: Integer): THTTPRangeSegment;
begin
  if (Index>=0)and(Index<RangeCount) then
    result := FRangeSegments[Index]
  else
  begin
    result.min := 0;
    result.max := 0;
  end;
end;

function THTTPRequest.GetCookies(aTimeout: ansistring): ansistring;
var i: Integer;
    name, val: ansistring;
begin
  result:='';
  if aTimeout<>'' then
    FCookies.Requests['Expires']:=aTimeout;

  for i:=0 to FCookies.Count-1 do
  begin
    FCookies.Get(i, name, val);
    if i>0 then
      result:=result+'; '+name+'='+val
    else
      result:=name+'='+val;
  end;
end;

{ THTTPReply }

function THTTPReply.Build(Response: ansistring): ansistring;
var
  i, Len: Integer;

procedure AddStr(const str: ansistring);
var
  l: Integer;
begin
  l:=Length(str);
  Move(str[1], result[Len], l);
  Inc(Len, l);
end;

begin
  Len:=Length(FVersion) + Length(Response) + 5;

  for i:=0 to FHeader.Count-1 do
    Len:=Len + Length(FHeader.FRequests[i].Name) + Length(FHeader.FRequests[i].Value) + 4;
  Setlength(Result, Len);
  Len:=1;
  AddStr(FVersion);
  AddStr(' ');
  AddStr(Response);
  AddStr(#13#10);
  for i:=0 to FHeader.Count-1 do
  begin
    AddStr(FHeader.FRequests[i].Name);
    AddStr(': ');
    AddStr(FHeader.FRequests[i].Value);
    AddStr(#13#10);
  end;
  AddStr(#13#10);
end;

function THTTPReply.Read(Reply: ansistring): Boolean;
var
  s: ansistring;
  i: Integer;
  function GetLine: ansistring;
  var
    i: Integer;
  begin
    i:=pos(#13#10, Reply);
    if i>0 then
    begin
      result:=Copy(Reply, 1, i-1);
      Delete(Reply, 1, i+1);
    end else
    begin
      result:=Reply;
      Reply:='';
    end;
  end;
begin
  FHeader.Clear;

  result:=False;
  s:=GetLine;
  FVersion:=Copy(s, 1, Pos(' ', s)-1);
  Delete(s, 1, Length(FVersion)+1);
  FResponse:=s;
  repeat
    s:=GetLine;
    if s='' then
      Break;
    i:=Pos(': ', s);
    if i>0 then
    begin
      FHeader.Add(Copy(s, 1, i-1), Trim(Copy(s, i+2, Length(s))));
    end else
      Exit;
  until s='';
  result:=True;
end;

procedure THTTPReply.Clear(Version: ansistring);
begin
  FHeader.Clear;
  FVersion := Version;  
end;

constructor THTTPReply.Create;
begin
  FHeader := THTTPRequestFields.Create;
end;

destructor THTTPReply.Destroy;
begin
  FHeader.Clear;
  FHeader.Free;
  inherited;
end;

{ THTTPPostData }

procedure THTTPPostData.Clear;
begin
  FEntities.Clear;
end;

function THTTPPostData.readstr(var str: ansistring): Boolean;
var
  len, i, j: Integer;
  boundary, s, s2, filename, dataname: string;
begin
  len := StrToIntDef(FRequest.header['Content-Length'], 0);
  s := FRequest.header['Content-Type'];
  result:=False;

  if pos('multipart/form-data;', s)=1 then
  begin
    boundary := '--' + Copy(s, pos('boundary=', s) + 9, length(s));
    Delete(str, 1, pos(boundary, str)+Length(boundary) + 1);

    repeat
      repeat
        i:=pos(#13#10, str);
        if i=1 then
          Delete(str, 1, 2);
      until i<>1;
      j:=pos(boundary, str);
      s:=Copy(str, 1, i-1);

      filename:=GetElementFromString(s, 'filename');
      dataname:=GetElementFromString(s, 'name');

      Inc(i, 4);
      s2:=Copy(str, i, j - i - 2);
      Delete(str, 1, j + Length(boundary)-1);

      if filename<>'' then
      begin
        // file uploaded, not supported
        result:=False;
      end else
      if dataname<>'' then
      begin
        FEntities.Add(dataname, s2);
      end;
    until (Length(str)<2) or (str[1]='-')and(str[2]='-');
    if pos('--'#13#10, str)=1 then
    begin
      delete(str, 1, 4);
      result:=True;
    end;
  end else
  if s = 'application/x-www-form-urlencoded' then
  begin
    if Length(str)>=len then
    begin
      s:=Copy(str, 1, len)+'&';
      Delete(str, 1, len);
      while pos('&', s)>0 do
      begin
        s2:=Copy(s, 1, pos('&', s)-1);
        Delete(s, 1, pos('&', s));
        if pos('=', s2)>0 then
        begin
          dataname:=Copy(s2, 1, pos('=', s2)-1);
          Delete(s2, 1, pos('=', s2));
          FEntities.Add(dataname, URLDecode(s2));
        end;
      end;
      result:=True;
    end;
  end
end;

constructor THTTPPostData.Create(Request: THTTPRequest);
begin
  FRequest := Request;
  FEntities := THTTPRequestFields.Create;
end;

destructor THTTPPostData.Destroy;
begin
  FEntities.Clear;
  FEntities.Free;
  inherited;
end;

end.
