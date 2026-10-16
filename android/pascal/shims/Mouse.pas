unit Mouse;
{$mode delphi}
// Replacement for FPC console Mouse unit on Android: reports the host pointer position
interface

function GetMouseX: Word;
function GetMouseY: Word;

implementation
uses
  KMAndroidHost;

function GetMouseX: Word;
begin
  if gHostCursorPos.X < 0 then
    Result := 0
  else
    Result := gHostCursorPos.X;
end;

function GetMouseY: Word;
begin
  if gHostCursorPos.Y < 0 then
    Result := 0
  else
    Result := gHostCursorPos.Y;
end;

end.
