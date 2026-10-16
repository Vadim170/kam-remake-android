unit LCLIntf;
{$mode delphi}
// Minimal LCLIntf replacement for the Android port
interface
uses
  Types, LCLType;

function GetKeyState(nVirtKey: Integer): SmallInt;
function GetCursorPos(out lpPoint: TPoint): Boolean;
function SetCursorPos(X, Y: Integer): Boolean;
function OpenURL(const aURL: string): Boolean;
function OpenDocument(const aPath: string): Boolean;
function GetTickCount: Cardinal;
function GetDoubleClickTime: Cardinal;

implementation
uses
  SysUtils, KMAndroidHost;

function GetKeyState(nVirtKey: Integer): SmallInt;
begin
  Result := 0;
  if (nVirtKey >= 0) and (nVirtKey <= 255) and gHostKeyDown[nVirtKey] then
    Result := SmallInt($8000);
end;

function GetCursorPos(out lpPoint: TPoint): Boolean;
begin
  lpPoint := gHostCursorPos;
  Result := True;
end;

function SetCursorPos(X, Y: Integer): Boolean;
begin
  // There is no mouse cursor to move on a touch screen
  Result := True;
end;

function OpenURL(const aURL: string): Boolean;
begin
  if Assigned(gHostOpenURL) then
    gHostOpenURL(UnicodeString(aURL));
  Result := True;
end;

function OpenDocument(const aPath: string): Boolean;
begin
  // Host opens local files with a system viewer (FileProvider) and URLs in a browser
  Result := Assigned(gHostOpenURL);
  if Result then
    gHostOpenURL(UnicodeString(aPath));
end;

function GetTickCount: Cardinal;
begin
  Result := Cardinal(GetTickCount64);
end;

function GetDoubleClickTime: Cardinal;
begin
  // Windows default double-click interval (ms)
  Result := 500;
end;


end.
