unit Forms;
{$mode delphi}
// Minimal Forms replacement for the Android port
interface
uses
  Classes, Types, Controls;

type
  TFormStyle = (fsNormal, fsMDIChild, fsMDIForm, fsStayOnTop, fsSplash, fsSystemStayOnTop);
  TPosition = (poDesigned, poDefault, poDefaultPosOnly, poDefaultSizeOnly, poScreenCenter, poDesktopCenter, poMainFormCenter, poOwnerFormCenter, poWorkAreaCenter);
  TWindowState = (wsNormal, wsMinimized, wsMaximized, wsFullScreen);
  TBorderStyle = (bsNone, bsSingle, bsSizeable, bsDialog, bsToolWindow, bsSizeToolWin);

  TForm = class(TWinControl)
  public
    Caption: string;
    procedure Show;
    procedure Hide;
    procedure Close;
  end;

  TMonitor = class
  public
    Left, Top, Width, Height: Integer;
  end;

  TScreen = class
  private
    fMonitor: TMonitor;
    fCursor: TCursor;
    function GetWidth: Integer;
    function GetHeight: Integer;
    function GetMonitor(aIndex: Integer): TMonitor;
    function GetMonitorCount: Integer;
  public
    Cursors: array [-32..255] of PtrUInt;
    constructor Create;
    destructor Destroy; override;
    property Width: Integer read GetWidth;
    property Height: Integer read GetHeight;
    property MonitorCount: Integer read GetMonitorCount;
    property Monitors[aIndex: Integer]: TMonitor read GetMonitor;
    property Cursor: TCursor read fCursor write fCursor;
  end;

  TApplication = class
  private
    function GetActive: Boolean;
    function GetExeName: string;
  public
    Title: string;
    procedure ProcessMessages;
    procedure Terminate;
    procedure Minimize;
    property Active: Boolean read GetActive;
    property ExeName: string read GetExeName;
  end;

var
  Application: TApplication;
  Screen: TScreen;

implementation
uses
  KMAndroidHost;

{ TForm }
procedure TForm.Show;
begin
  Visible := True;
end;

procedure TForm.Hide;
begin
  Visible := False;
end;

procedure TForm.Close;
begin
end;

{ TScreen }
constructor TScreen.Create;
begin
  inherited;
  fMonitor := TMonitor.Create;
end;

destructor TScreen.Destroy;
begin
  fMonitor.Free;
  inherited;
end;

function TScreen.GetWidth: Integer;
begin
  Result := gHostScreenWidth;
end;

function TScreen.GetHeight: Integer;
begin
  Result := gHostScreenHeight;
end;

function TScreen.GetMonitorCount: Integer;
begin
  Result := 1;
end;

function TScreen.GetMonitor(aIndex: Integer): TMonitor;
begin
  fMonitor.Left := 0;
  fMonitor.Top := 0;
  fMonitor.Width := gHostScreenWidth;
  fMonitor.Height := gHostScreenHeight;
  Result := fMonitor;
end;

{ TApplication }
function TApplication.GetActive: Boolean;
begin
  Result := gHostAppActive;
end;

function TApplication.GetExeName: string;
begin
  Result := ParamStr(0);
end;

procedure TApplication.ProcessMessages;
begin
end;

procedure TApplication.Terminate;
begin
end;

procedure TApplication.Minimize;
begin
end;

initialization
  Application := TApplication.Create;
  Screen := TScreen.Create;

finalization
  Screen.Free;
  Application.Free;

end.
