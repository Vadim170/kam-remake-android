unit Clipbrd;
{$mode delphi}
// Minimal Clipbrd replacement for the Android port.
// Text goes to the Android clipboard via host; custom formats (e.g. MapEd terrain selection) are kept in-process
interface
uses
  Classes, SysUtils;

type
  TClipboardFormat = PtrUInt;

  TClipboard = class
  private
    fText: UnicodeString;
    fCustomFormats: array of TClipboardFormat;
    fCustomData: array of TBytes;
    function GetAsText: string;
    procedure SetAsText(const aValue: string);
    function FindCustom(aFormat: TClipboardFormat): Integer;
  public
    function HasFormat(aFormat: TClipboardFormat): Boolean;
    procedure SetFormat(aFormat: TClipboardFormat; aStream: TStream);
    function GetFormat(aFormat: TClipboardFormat; aStream: TStream): Boolean;
    procedure Clear;
    property AsText: string read GetAsText write SetAsText;
  end;

const
  CF_TEXT = 1;

function Clipboard: TClipboard;

implementation
uses
  KMAndroidHost;

var
  gClipboard: TClipboard;

function Clipboard: TClipboard;
begin
  if gClipboard = nil then
    gClipboard := TClipboard.Create;
  Result := gClipboard;
end;

function TClipboard.GetAsText: string;
begin
  if Assigned(gHostClipboardGet) then
    fText := gHostClipboardGet();
  Result := string(fText);
end;

procedure TClipboard.SetAsText(const aValue: string);
begin
  fText := UnicodeString(aValue);
  if Assigned(gHostClipboardSet) then
    gHostClipboardSet(fText);
end;

function TClipboard.FindCustom(aFormat: TClipboardFormat): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(fCustomFormats) do
    if fCustomFormats[I] = aFormat then
      Exit(I);
end;

function TClipboard.HasFormat(aFormat: TClipboardFormat): Boolean;
begin
  if aFormat = CF_TEXT then
    Result := GetAsText <> ''
  else
    Result := FindCustom(aFormat) <> -1;
end;

procedure TClipboard.SetFormat(aFormat: TClipboardFormat; aStream: TStream);
var
  idx: Integer;
begin
  idx := FindCustom(aFormat);
  if idx = -1 then
  begin
    idx := Length(fCustomFormats);
    SetLength(fCustomFormats, idx + 1);
    SetLength(fCustomData, idx + 1);
    fCustomFormats[idx] := aFormat;
  end;

  SetLength(fCustomData[idx], aStream.Size);
  aStream.Position := 0;
  if aStream.Size > 0 then
    aStream.ReadBuffer(fCustomData[idx][0], aStream.Size);
end;

function TClipboard.GetFormat(aFormat: TClipboardFormat; aStream: TStream): Boolean;
var
  idx: Integer;
begin
  idx := FindCustom(aFormat);
  Result := idx <> -1;
  if Result and (Length(fCustomData[idx]) > 0) then
    aStream.WriteBuffer(fCustomData[idx][0], Length(fCustomData[idx]));
end;

procedure TClipboard.Clear;
begin
  SetLength(fCustomFormats, 0);
  SetLength(fCustomData, 0);
end;

finalization
  gClipboard.Free;

end.
