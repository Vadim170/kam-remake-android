unit KM_FpcCompat;
{$I KaM_Remake.inc}
// Minimal replacements for Delphi-only RTL classes, used when compiling with FPC
interface
{$IFDEF FPC}
uses
  Classes, SysUtils;

type
  // Subset of Delphi TStreamWriter: writes UTF8 text (with optional BOM) to a stream or a file
  TStreamWriter = class
  private
    fStream: TStream;
    fOwnsStream: Boolean;
    fNewLine: string;
    procedure WriteRaw(const aBytes: RawByteString);
  public
    constructor Create(aStream: TStream); overload;
    constructor Create(aStream: TStream; aEncoding: TEncoding); overload;
    constructor Create(const aFilename: string; aAppend: Boolean = False); overload;
    destructor Destroy; override;
    procedure Write(const aValue: AnsiString); overload;
    procedure Write(const aValue: UnicodeString); overload;
    procedure WriteLine; overload;
    procedure WriteLine(const aValue: AnsiString); overload;
    procedure WriteLine(const aValue: UnicodeString); overload;
    procedure Flush;
    procedure Close;
    property NewLine: string read fNewLine write fNewLine;
  end;

  // Subset of Delphi IOUtils.TFile
  TFile = class
  public
    // Returns file contents as UTF8 string (UTF8 BOM is skipped)
    class function ReadAllText(const aPath: string): string; static;
  end;
{$ENDIF}

implementation
{$IFDEF FPC}

{ TStreamWriter }
constructor TStreamWriter.Create(aStream: TStream);
begin
  inherited Create;
  fStream := aStream;
  fOwnsStream := False;
  fNewLine := sLineBreak;
end;


constructor TStreamWriter.Create(aStream: TStream; aEncoding: TEncoding);
var
  preamble: TBytes;
begin
  Create(aStream);
  if aEncoding <> nil then
  begin
    preamble := aEncoding.GetPreamble;
    if Length(preamble) > 0 then
      fStream.WriteBuffer(preamble[0], Length(preamble));
  end;
end;


constructor TStreamWriter.Create(const aFilename: string; aAppend: Boolean = False);
begin
  if aAppend and FileExists(aFilename) then
  begin
    Create(TFileStream.Create(aFilename, fmOpenReadWrite or fmShareDenyWrite));
    fStream.Seek(0, soEnd);
  end
  else
    Create(TFileStream.Create(aFilename, fmCreate));
  fOwnsStream := True;
end;


destructor TStreamWriter.Destroy;
begin
  Close;
  inherited;
end;


procedure TStreamWriter.WriteRaw(const aBytes: RawByteString);
begin
  if aBytes <> '' then
    fStream.WriteBuffer(aBytes[1], Length(aBytes));
end;


procedure TStreamWriter.Write(const aValue: AnsiString);
begin
  // AnsiStrings are expected to be UTF8-encoded
  WriteRaw(aValue);
end;


procedure TStreamWriter.Write(const aValue: UnicodeString);
begin
  WriteRaw(UTF8Encode(aValue));
end;


procedure TStreamWriter.WriteLine;
begin
  Write(fNewLine);
end;


procedure TStreamWriter.WriteLine(const aValue: AnsiString);
begin
  Write(aValue);
  WriteLine;
end;


procedure TStreamWriter.WriteLine(const aValue: UnicodeString);
begin
  Write(aValue);
  WriteLine;
end;


procedure TStreamWriter.Flush;
begin
  // Unbuffered
end;


{ TFile }
class function TFile.ReadAllText(const aPath: string): string;
var
  fs: TFileStream;
  raw: RawByteString;
begin
  fs := TFileStream.Create(aPath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(raw, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(raw[1], fs.Size);
  finally
    fs.Free;
  end;

  // Skip UTF8 BOM
  if (Length(raw) >= 3) and (raw[1] = #$EF) and (raw[2] = #$BB) and (raw[3] = #$BF) then
    Delete(raw, 1, 3);

  Result := UTF8Decode(raw);
end;


procedure TStreamWriter.Close;
begin
  if fOwnsStream then
    FreeAndNil(fStream);
  fStream := nil;
end;
{$ENDIF}

end.
