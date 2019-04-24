unit clientmanager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, websocketserver, syncobjs;

type

  { TClientManager }

  TClientManager = class
  private
    FCS: TCriticalSection;
    FClients: array of TWebsocketClientThread;
  public
    constructor Create;
    procedure AddClient(c: TWebsocketClientThread);
    procedure RemoveClient(c: TWebsocketClientThread);
    procedure Broadcast(msg: string);
  end;

implementation

{ TClientManager }

constructor TClientManager.Create;
begin
  FCS:=TCriticalSection.Create;
end;

procedure TClientManager.AddClient(c: TWebsocketClientThread);
var
  i: Integer;
begin
  FCS.Enter;
  try
    i:=Length(FClients);
    Setlength(FClients, i+1);
    FClients[i]:=c;
  finally
    FCS.Leave;
  end;
end;

procedure TClientManager.RemoveClient(c: TWebsocketClientThread);
var
  i: Integer;
begin
  FCS.Enter;
  try
    for i:=0 to Length(FClients) - 1 do
    if FClients[i] = c then
    begin
      FClients[i]:=FClients[Length(FClients)-1];
      Break;
    end;
    Setlength(FClients, Length(FClients) - 1);
  finally
    FCS.Leave;
  end;
end;

procedure TClientManager.Broadcast(msg: string);
var
  i: Integer;
begin
  FCS.Enter;
  try
    for i:=0 to Length(FClients)-1 do
      FClients[i].Send(msg, false);
  finally
  FCS.Leave;
  end;
end;

end.

