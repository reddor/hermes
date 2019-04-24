unit utils;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF MSWINDOWS}
  windows,
  {$ENDIF}
  Classes,
  SysUtils;

type
  TMonitorAbortCallback = function: Boolean;

function ReadFileString(Filename: ansistring): ansistring;
function WriteFileString(Filename, Data: ansistring): Boolean;
function GetFileSize(AFilename: ansistring): Integer;
procedure Error(Message: ansistring);

{$IFDEF MSWINDOWS}
function MonitorDirectory(ADirectory: ansistring; GracePeriod: Integer = 100; WaitTimeOut: DWORD = INFINITE; AbortCallback: TMonitorAbortCallback = nil): Boolean;
{$ENDIF}

var
  HaltOnError: Boolean = true;

implementation

function ReadFileString(Filename: ansistring): ansistring;
var
  f: File;
begin
  Assignfile(f, Filename);
  {$i-}Reset(f, 1);{$i+}
  if ioresult = 0 then
  begin
    Setlength(result, FileSize(f));
    BlockRead(f, result[1], FileSize(f));
    Closefile(f);
  end else
    result:='';
end;

function WriteFileString(Filename, Data: ansistring): Boolean;
var
  f: File;
begin
  result:=False;
  Assignfile(f, Filename);
  {$i-}Rewrite(f, 1);{$i+}
  if ioresult = 0 then
  begin
    BlockWrite(f, Data[1], Length(Data));
    Closefile(f);
    result:=True;
  end;
end;

procedure Error(Message: ansistring);
begin
  Writeln(StdErr, 'Error: ', Message);
  if HaltOnError then
    Halt(2);
end;

{$IFDEF MSWINDOWS}
function MonitorDirectory(ADirectory: ansistring; GracePeriod: Integer = 100; WaitTimeOut: DWORD = INFINITE; AbortCallback: TMonitorAbortCallback = nil): Boolean;
var
  Handle: THandle;
begin
  result:=False;
  Handle:=FindFirstChangeNotification(PAnsiChar(ADirectory), True,
    FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
    FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE);

  if Handle = INVALID_HANDLE_VALUE then
    Exit;

  repeat
    case WaitForSingleObject(Handle, WaitTimeOut) of
      WAIT_OBJECT_0:
      begin
        repeat
          FindNextChangeNotification(Handle);
        until WaitForSingleObject(Handle, GracePeriod) <> WAIT_OBJECT_0;
        result:=True;
        Break;
      end;
      WAIT_TIMEOUT:
        if (not Assigned(AbortCallback)) or not AbortCallback() then
        begin
          result:=True;
          Break;
        end;
      else begin
        result:=False;
        Break;
      end;
    end;
  until False;
  FindCloseChangeNotification(Handle);
end;
{$ENDIF}

function GetFileSize(AFilename: ansistring): Integer;
var
  f: File;
begin
  Assignfile(f, AFilename);
  {$i-}Reset(F, 1);{$i+}
  if ioresult = 0 then
  begin
    result:=FileSize(f);
    Closefile(f);
  end else
    result:=-1;
end;

end.

