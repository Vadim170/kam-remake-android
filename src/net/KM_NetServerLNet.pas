unit KM_NetServerLNet;
{$I KaM_Remake.inc}
interface
uses
  Classes, SysUtils, lNet, KM_CommonTypes;


{ This unit knows nothing about KaM, it's just a puppet in hands of KM_ServerControl,
doing all the low level work on TCP. So we can replace this unit with other TCP client
without KaM even noticing. }

const
  MAX_SEND_BUFFER = 1048576; //1 MB


type
  TKMClientInfo = class
  public
    Tag: Integer;
    Buffer: array of byte;
    BufferLen: Cardinal;
    constructor Create(aTag: Integer);
    procedure AttemptSend(aSocket: TLSocket);
    procedure PutInBuffer(aData:pointer; aLength:cardinal);
    function BufferFull: Boolean;
  end;

  THandleEvent = procedure (aHandle: SmallInt) of object;
  TNotifyDataEvent = procedure(aHandle: SmallInt; aData:pointer; aLength:cardinal)of object;

  TKMNetServerLNet = class
  private
    fSocketServer: TLTCP;
    fLastTag:integer;
    fListening: Boolean;
    fOnError: TGetStrProc;
    fOnClientConnect: THandleEvent;
    fOnClientDisconnect: THandleEvent;
    fOnDataAvailable: TNotifyDataEvent;
    procedure ClientConnect(aSocket: TLSocket);
    procedure ClientDisconnect(aSocket: TLSocket);
    procedure ReceiveData(aSocket: TLSocket);
    procedure CanSend(aSocket: TLSocket);
    procedure HandleError(const aMsg: AnsiString; aSocket: TLSocket);
    function GetMaxHandle: SmallInt;
  public
    constructor Create;
    destructor Destroy; override;
    procedure StartListening(aPort: Word);
    procedure StopListening;
    procedure SendData(aHandle: SmallInt; aData:pointer; aLength:cardinal);
    procedure Kick(aHandle: SmallInt);
    procedure UpdateStateIdle;
    function IsValidHandle(aHandle: Integer): Boolean;
    function GetIP(aHandle: Integer): string;
    property OnError: TGetStrProc write fOnError;
    property OnClientConnect: THandleEvent write fOnClientConnect;
    property OnClientDisconnect: THandleEvent write fOnClientDisconnect;
    property OnDataAvailable: TNotifyDataEvent write fOnDataAvailable;
  end;


implementation
uses
  Math;


//Tagging starts with some number away from -2 -1 0 used as sender/recipient constants
//and off from usual players indexes 1..8, so we could not confuse them by mistake
const
  FIRST_TAG = 15;


{ TKMClientInfo }
constructor TKMClientInfo.Create(aTag: Integer);
begin
  inherited Create;
  Tag := aTag;
end;


procedure TKMClientInfo.AttemptSend(aSocket: TLSocket);
var
  lenSent: Integer;
begin
  if BufferLen <= 0 then Exit;

  lenSent := aSocket.Send(Buffer[0], BufferLen);

  if lenSent > 0 then
  begin
    BufferLen := BufferLen - lenSent;
    if BufferLen > 0 then
      Move(Buffer[lenSent], Buffer[0], BufferLen);
  end;
end;


procedure TKMClientInfo.PutInBuffer(aData:pointer; aLength:cardinal);
begin
  SetLength(Buffer, BufferLen + aLength);
  Move(aData^, Buffer[BufferLen], aLength);
  BufferLen := BufferLen + aLength;
end;


function TKMClientInfo.BufferFull: Boolean;
begin
  Result := BufferLen >= MAX_SEND_BUFFER;
end;


{ TKMNetServerLNet }
constructor TKMNetServerLNet.Create;
begin
  Inherited Create;
  fLastTag := FIRST_TAG-1; //First client will be fLastTag+1
end;


destructor TKMNetServerLNet.Destroy;
begin
  StopListening;
  if fSocketServer<> nil then fSocketServer.Free;
  Inherited;
end;


procedure TKMNetServerLNet.StartListening(aPort: Word);
begin
  FreeAndNil(fSocketServer);
  fSocketServer := TLTCP.Create(nil);
  fSocketServer.OnError := HandleError;
  fSocketServer.OnAccept := ClientConnect;
  fSocketServer.OnDisconnect := ClientDisconnect;
  fSocketServer.OnReceive := ReceiveData;
  fSocketServer.OnCanSend := CanSend;
  //This is the time it will wait in CallAction for the OS to respond, it's better than calling Sleep(1)
  //This value could be higher, it won't cause delays since it's just a timeout on waiting for network events
  fSocketServer.Timeout := 100;
  fSocketServer.ReuseAddress := True; //Allows us to overwrite an old connection in the wait state rather than saying the port is still in use
  if not fSocketServer.Listen(aPort) then
    raise Exception.Create('Server failed to start');
  fListening := True;
end;


procedure TKMNetServerLNet.StopListening;
begin
  if fSocketServer <> nil then
  begin
    //We have to disconnect all the clients too
    fSocketServer.IterReset;
    while fSocketServer.IterNext do
    begin
      if fSocketServer.Iterator.UserData <> nil then
      begin
        TKMClientInfo(fSocketServer.Iterator.UserData).Free;
        fSocketServer.Iterator.UserData := nil;
      end;
      fSocketServer.Iterator.Disconnect(True);
    end;
    fSocketServer.Disconnect(True);
  end;
  FreeAndNil(fSocketServer);
  fLastTag := FIRST_TAG-1;
  fListening := False;
end;


//Someone has connected to us
procedure TKMNetServerLNet.ClientConnect(aSocket: TLSocket);
begin
  //Identify index of the Client, so we can address it
  if fLastTag = GetMaxHandle then fLastTag := FIRST_TAG-1; //I'll be surprised if this is ever necessary
  inc(fLastTag);
  aSocket.UserData := TKMClientInfo.Create(fLastTag);
  fOnClientConnect(fLastTag);
  aSocket.SetState(ssNoDelay, True); //Send packets ASAP (disables Nagle's algorithm)
end;


procedure TKMNetServerLNet.ClientDisconnect(aSocket: TLSocket);
begin
  if aSocket.UserData = nil then Exit;
  fOnClientDisconnect(TKMClientInfo(aSocket.UserData).Tag);
  TKMClientInfo(aSocket.UserData).Free;
  aSocket.UserData := nil;
end;


//We recieved data from someone
procedure TKMNetServerLNet.ReceiveData(aSocket: TLSocket);
const
  BUFFER_SIZE = 10240; //10kb
var
  P: Pointer;
  L: Integer; //L could be -1 when no data is available
begin
  if aSocket.UserData = nil then
  begin
    aSocket.Disconnect(True); //Sometimes disconnecting them fails the first time(?) LNet bug?
    //fOnError('Received data from an unknown client');
    Exit;
  end;

  GetMem(P, BUFFER_SIZE+1); //+1 to avoid RangeCheckError when L = BufferSize
  L := aSocket.Get(P^, BUFFER_SIZE);

  if L > 0 then //if L=0 then exit;
    fOnDataAvailable(TKMClientInfo(aSocket.UserData).Tag, P, L);

  FreeMem(P);
end;


procedure TKMNetServerLNet.HandleError(const aMsg: AnsiString; aSocket: TLSocket);
begin
  fOnError('LNet: ' + aMsg);
  if (aSocket <> nil) and not aSocket.Connected then
    ClientDisconnect(aSocket); //Sometimes this is the only event we get when a client disconnects (LNet bug?)
end;


procedure TKMNetServerLNet.CanSend(aSocket: TLSocket);
begin
  if aSocket.UserData = nil then Exit;
  TKMClientInfo(aSocket.UserData).AttemptSend(aSocket);
end;


//Make sure we send data to specified client
procedure TKMNetServerLNet.SendData(aHandle: SmallInt; aData: Pointer; aLength: Cardinal);
begin
  fSocketServer.IterReset;
  while fSocketServer.IterNext do
    if fSocketServer.Iterator.Connected then //Sometimes this occurs just before ClientDisconnect
      if (fSocketServer.Iterator.UserData <> nil) and (TKMClientInfo(fSocketServer.Iterator.UserData).Tag = aHandle) then
      begin
        if TKMClientInfo(fSocketServer.Iterator.UserData).BufferFull then
        begin
          fOnError('Send buffer full for client '+IntToStr(TKMClientInfo(fSocketServer.Iterator.UserData).Tag));
          Exit;
        end;
        TKMClientInfo(fSocketServer.Iterator.UserData).PutInBuffer(aData, aLength);
        TKMClientInfo(fSocketServer.Iterator.UserData).AttemptSend(fSocketServer.Iterator);
        Exit;
      end;
end;


procedure TKMNetServerLNet.Kick(aHandle: SmallInt);
var
  iter: TLSocket;
begin
  fSocketServer.IterReset;
  while fSocketServer.IterNext do
    if (fSocketServer.Iterator.UserData <> nil) and (TKMClientInfo(fSocketServer.Iterator.UserData).Tag = aHandle) then
    begin
      //Found the client that must be kicked
      iter := fSocketServer.Iterator; //Calling ClientDisconnect can reset Iterator due to sending a message, so we must remember it (don't use it after this line)
      //Seems to be a bug in LNet where ClientDisconnect is not called sometimes? So call it ourself just in case
      ClientDisconnect(iter);
      if iter.ConnectionStatus in [scConnected, scConnecting, scDisconnecting] then
        //We always use forceful disconnects otherwise sockets can be left in FIN_WAIT2 state forever. See:
        //http://stackoverflow.com/questions/9819745/how-tcp-stack-distinguish-close-and-shutdown
        iter.Disconnect(True)
      else
        fOnError('Warning: Attempted to kick a client that is not connected');
      Exit; //Only one client should have this handle
    end;
  //If we reached here we didn't find a match
  fOnError('Warning: Attempted to kick a client that has already disconnected');
  fOnClientDisconnect(aHandle); //Client has already disconnected somehow, so send the event to ensure they are removed
end;


function TKMNetServerLNet.GetMaxHandle: SmallInt;
begin
  Result := 32767;
end;


// Take in Integer to check it against actual small range
function TKMNetServerLNet.IsValidHandle(aHandle: Integer): Boolean;
begin
  // This is rather poor check that can be refactored to check against real fMaxHandle
  Result := InRange(aHandle, FIRST_TAG, GetMaxHandle);
end;


procedure TKMNetServerLNet.UpdateStateIdle;
begin
  if fSocketServer <> nil then
    fSocketServer.CallAction; //Process network events

  if fListening and not fSocketServer.Connected then
    raise Exception.Create('Server is no longer listening! Server will restart.');
end;


function TKMNetServerLNet.GetIP(aHandle: Integer): string;
begin
  Result := '';
  fSocketServer.IterReset;
  while fSocketServer.IterNext do
    if (fSocketServer.Iterator.UserData <> nil) and (TKMClientInfo(fSocketServer.Iterator.UserData).Tag = aHandle) then
      Exit(fSocketServer.Iterator.PeerAddress); // Only one client should have this handle
end;


end.

