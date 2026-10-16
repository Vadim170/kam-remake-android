unit KM_NetUDPLNet;
{$I KaM_Remake.inc}
interface
uses
  Classes, Math, SysUtils, LNet, KM_CommonTypes;


type
  TNotifyAddressDataEvent = procedure(const aAddress: string; aData: Pointer; aLength: Cardinal) of object;

  TKMNetUDPLNet = class
  private
    fUDP: TLUdp;

    fOnError: TGetStrProc;
    fOnRecieveData: TNotifyAddressDataEvent;
    procedure HandleReceive(aSocket: TLSocket);
    procedure HandleError(const aMsg: AnsiString; aSocket: TLSocket);
  public
    constructor Create;
    destructor Destroy; override;
    procedure SendPacket(const aAddress: string; const aPort: Word; aData: Pointer; aLength: Cardinal);
    procedure Listen(const aPort: Word);
    procedure StopListening;
    procedure UpdateStateIdle;
    property OnError: TGetStrProc write fOnError;
    property OnRecieveData: TNotifyAddressDataEvent write fOnRecieveData;
  end;


implementation


constructor TKMNetUDPLNet.Create;
begin
  Inherited Create;

  fUDP := TLUdp.Create(nil);
  fUDP.OnError := HandleError;
  fUDP.Timeout := 1;
end;


destructor TKMNetUDPLNet.Destroy;
begin
  if fUDP<>nil then fUDP.Free;

  Inherited;
end;


procedure TKMNetUDPLNet.Listen(const aPort:Word);
begin
  fUDP.OnReceive := HandleReceive;
  fUDP.Listen(aPort);
  fUDP.CallAction;
end;


procedure TKMNetUDPLNet.StopListening;
begin
  fUDP.Disconnect;
  fUDP.OnReceive := nil;
end;


procedure TKMNetUDPLNet.SendPacket(const aAddress: string; const aPort: Word; aData: Pointer; aLength: Cardinal);
begin
  fUDP.Send(aData^, aLength, aAddress + ':' + IntToStr(aPort));
end;


procedure TKMNetUDPLNet.HandleReceive(aSocket: TLSocket);
const
  BUFFER_SIZE = 10240; //10kb
var
  P: Pointer;
  L: Integer; //L could be -1 when no data is available
begin
  GetMem(P, BUFFER_SIZE+1); //+1 to avoid RangeCheckError when L = BUFFER_SIZE
  L := fUDP.Get(P^, BUFFER_SIZE, aSocket);

  if L > 0 then
    fOnRecieveData(aSocket.PeerAddress, P, L);

  FreeMem(P);
end;


procedure TKMNetUDPLNet.HandleError(const aMsg: AnsiString; aSocket: TLSocket);
begin
  fOnError('LNet UDP Error: ' + aMsg);
end;


procedure TKMNetUDPLNet.UpdateStateIdle;
begin
  if fUDP <> nil then fUDP.CallAction; //Process network events
end;


end.
