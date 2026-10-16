unit Controls;
{$mode delphi}
// Minimal Controls replacement for the Android port
interface
uses
  Classes, Types;

type
  TMouseButton = (mbLeft, mbRight, mbMiddle, mbExtra1, mbExtra2);
  TCursor = -32768..32767;
  TCaption = string;

  TKeyEvent = procedure(Sender: TObject; var Key: Word; Shift: TShiftState) of object;
  TKeyPressEvent = procedure(Sender: TObject; var Key: Char) of object;
  TMouseEvent = procedure(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer) of object;
  TMouseMoveEvent = procedure(Sender: TObject; Shift: TShiftState; X, Y: Integer) of object;
  TMouseWheelEvent = procedure(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean) of object;

  TModalResult = Integer;

  TControl = class(TComponent)
  private
    fLeft, fTop, fWidth, fHeight: Integer;
    fVisible: Boolean;
  public
    function ClientRect: TRect;
    function ClientToScreen(const aPoint: TPoint): TPoint;
    function ScreenToClient(const aPoint: TPoint): TPoint;
    procedure SetBounds(aLeft, aTop, aWidth, aHeight: Integer); virtual;
    property Left: Integer read fLeft write fLeft;
    property Top: Integer read fTop write fTop;
    property Width: Integer read fWidth write fWidth;
    property Height: Integer read fHeight write fHeight;
    property Visible: Boolean read fVisible write fVisible;
  end;

  TWinControl = class(TControl)
  public
    Handle: PtrUInt;
    procedure SetFocus; virtual;
  end;

  TMouse = class
  private
    function GetCursorPos: TPoint;
    procedure SetCursorPos(const aValue: TPoint);
  public
    property CursorPos: TPoint read GetCursorPos write SetCursorPos;
  end;

const
  // Windows/LCLType constants used by engine code (e.g. KM_ControlsBase)
  MINSHORT = $8000;
  MAXSHORT = $7FFF;

  crDefault = TCursor(0);

  crNone = TCursor(-1);
  crArrow = TCursor(-2);
  crCross = TCursor(-3);
  crIBeam = TCursor(-4);
  crSize = TCursor(-22);
  crSizeNESW = TCursor(-6);
  crSizeNS = TCursor(-7);
  crSizeNWSE = TCursor(-8);
  crSizeWE = TCursor(-9);
  crHourGlass = TCursor(-11);
  crHandPoint = TCursor(-21);

  mrNone = 0;
  mrOK = 1;
  mrCancel = 2;
  mrAbort = 3;
  mrRetry = 4;
  mrIgnore = 5;
  mrYes = 6;
  mrNo = 7;
  mrAll = 8;
  mrNoToAll = 9;
  mrYesToAll = 10;
  mrClose = 11;

var
  Mouse: TMouse;

implementation
uses
  KMAndroidHost;

{ TControl }
function TControl.ClientRect: TRect;
begin
  Result := Rect(0, 0, fWidth, fHeight);
end;

function TControl.ClientToScreen(const aPoint: TPoint): TPoint;
begin
  Result := aPoint;
end;

function TControl.ScreenToClient(const aPoint: TPoint): TPoint;
begin
  Result := aPoint;
end;

procedure TControl.SetBounds(aLeft, aTop, aWidth, aHeight: Integer);
begin
  fLeft := aLeft;
  fTop := aTop;
  fWidth := aWidth;
  fHeight := aHeight;
end;

{ TWinControl }
procedure TWinControl.SetFocus;
begin
end;

{ TMouse }
function TMouse.GetCursorPos: TPoint;
begin
  Result := gHostCursorPos;
end;

procedure TMouse.SetCursorPos(const aValue: TPoint);
begin
  // Cursor can not be moved on a touch screen
end;

initialization
  Mouse := TMouse.Create;

finalization
  Mouse.Free;

end.
