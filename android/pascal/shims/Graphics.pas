unit Graphics;
{$mode delphi}
// Minimal Graphics replacement for the Android port.
// TBitmap is a plain 32bit in-memory image, enough for resource export helpers
interface
uses
  Classes, SysUtils;

type
  TColor = -$7FFFFFFF-1..$7FFFFFFF;
  TPixelFormat = (pfDevice, pf1bit, pf4bit, pf8bit, pf15bit, pf16bit, pf24bit, pf32bit, pfCustom);
  TBitmapHandleType = (bmDIB, bmDDB);
  TBrushStyle = (bsSolid, bsClear, bsHorizontal, bsVertical, bsFDiagonal, bsBDiagonal, bsCross, bsDiagCross, bsImage, bsPattern);

  TPen = class
  public
    Color: TColor;
    Width: Integer;
  end;

  TBrush = class
  public
    Color: TColor;
    Style: TBrushStyle;
  end;

  TBitmap = class;

  TCanvas = class
  private
    fOwner: TBitmap;
    fPen: TPen;
    fBrush: TBrush;
    function GetPixel(X, Y: Integer): TColor;
    procedure SetPixel(X, Y: Integer; aValue: TColor);
  public
    constructor Create(aOwner: TBitmap);
    destructor Destroy; override;
    procedure Rectangle(X1, Y1, X2, Y2: Integer);
    property Pixels[X, Y: Integer]: TColor read GetPixel write SetPixel;
    property Pen: TPen read fPen;
    property Brush: TBrush read fBrush;
  end;

  TBitmap = class
  private
    fWidth, fHeight: Integer;
    fData: array of Cardinal; // BGRA, as Windows DIB
    fCanvas: TCanvas;
    procedure Realloc(aWidth, aHeight: Integer);
    procedure SetWidth(aValue: Integer);
    procedure SetHeight(aValue: Integer);
    function GetScanLine(aRow: Integer): Pointer;
  public
    PixelFormat: TPixelFormat;
    HandleType: TBitmapHandleType;
    constructor Create;
    destructor Destroy; override;
    procedure SaveToFile(const aFilename: string);
    function Handle: PtrUInt;
    function MaskHandle: PtrUInt;
    procedure Mask(aColor: TColor);
    procedure ReleaseMaskHandle;
    property Width: Integer read fWidth write SetWidth;
    property Height: Integer read fHeight write SetHeight;
    property ScanLine[aRow: Integer]: Pointer read GetScanLine;
    property Canvas: TCanvas read fCanvas;
  end;

const
  clBlack = TColor($000000);
  clMaroon = TColor($000080);
  clGreen = TColor($008000);
  clOlive = TColor($008080);
  clNavy = TColor($800000);
  clPurple = TColor($800080);
  clTeal = TColor($808000);
  clGray = TColor($808080);
  clSilver = TColor($C0C0C0);
  clRed = TColor($0000FF);
  clLime = TColor($00FF00);
  clYellow = TColor($00FFFF);
  clBlue = TColor($FF0000);
  clFuchsia = TColor($FF00FF);
  clAqua = TColor($FFFF00);
  clWhite = TColor($FFFFFF);
  clNone = TColor($1FFFFFFF);
  clDefault = TColor($20000000);

implementation
uses
  FPImage, FPWriteBMP, FPWritePNG;

{ TCanvas }
constructor TCanvas.Create(aOwner: TBitmap);
begin
  inherited Create;
  fOwner := aOwner;
  fPen := TPen.Create;
  fBrush := TBrush.Create;
end;

destructor TCanvas.Destroy;
begin
  fPen.Free;
  fBrush.Free;
  inherited;
end;

function TCanvas.GetPixel(X, Y: Integer): TColor;
var
  C: Cardinal;
begin
  Result := clNone;
  if (X < 0) or (Y < 0) or (X >= fOwner.fWidth) or (Y >= fOwner.fHeight) then Exit;
  C := fOwner.fData[Y * fOwner.fWidth + X];
  // BGRA -> TColor ($BBGGRR)
  Result := TColor(((C shr 16) and $FF) or (C and $FF00) or ((C and $FF) shl 16));
end;

procedure TCanvas.SetPixel(X, Y: Integer; aValue: TColor);
begin
  if (X < 0) or (Y < 0) or (X >= fOwner.fWidth) or (Y >= fOwner.fHeight) then Exit;
  fOwner.fData[Y * fOwner.fWidth + X] := $FF000000 or ((Cardinal(aValue) shr 16) and $FF) or (Cardinal(aValue) and $FF00) or ((Cardinal(aValue) and $FF) shl 16);
end;

procedure TCanvas.Rectangle(X1, Y1, X2, Y2: Integer);
var
  I: Integer;
begin
  for I := X1 to X2 - 1 do
  begin
    SetPixel(I, Y1, fPen.Color);
    SetPixel(I, Y2 - 1, fPen.Color);
  end;
  for I := Y1 to Y2 - 1 do
  begin
    SetPixel(X1, I, fPen.Color);
    SetPixel(X2 - 1, I, fPen.Color);
  end;
end;

{ TBitmap }
constructor TBitmap.Create;
begin
  inherited;
  fCanvas := TCanvas.Create(Self);
  PixelFormat := pf32bit;
end;

destructor TBitmap.Destroy;
begin
  fCanvas.Free;
  inherited;
end;

procedure TBitmap.Realloc(aWidth, aHeight: Integer);
begin
  fWidth := aWidth;
  fHeight := aHeight;
  SetLength(fData, fWidth * fHeight);
end;

procedure TBitmap.SetWidth(aValue: Integer);
begin
  Realloc(aValue, fHeight);
end;

procedure TBitmap.SetHeight(aValue: Integer);
begin
  Realloc(fWidth, aValue);
end;

function TBitmap.GetScanLine(aRow: Integer): Pointer;
begin
  Result := @fData[aRow * fWidth];
end;

procedure TBitmap.SaveToFile(const aFilename: string);
var
  img: TFPMemoryImage;
  writer: TFPCustomImageWriter;
  X, Y: Integer;
  C: Cardinal;
begin
  img := TFPMemoryImage.Create(fWidth, fHeight);
  if SameText(ExtractFileExt(aFilename), '.png') then
    writer := TFPWriterPNG.Create
  else
    writer := TFPWriterBMP.Create;
  try
    for Y := 0 to fHeight - 1 do
    for X := 0 to fWidth - 1 do
    begin
      C := fData[Y * fWidth + X];
      img.Colors[X, Y] := FPColor(((C shr 16) and $FF) * $101, ((C shr 8) and $FF) * $101, (C and $FF) * $101, (C shr 24) * $101);
    end;
    img.SaveToFile(aFilename, writer);
  finally
    writer.Free;
    img.Free;
  end;
end;

function TBitmap.Handle: PtrUInt;
begin
  Result := 0;
end;

function TBitmap.MaskHandle: PtrUInt;
begin
  Result := 0;
end;

procedure TBitmap.Mask(aColor: TColor);
begin
end;

procedure TBitmap.ReleaseMaskHandle;
begin
end;

end.
