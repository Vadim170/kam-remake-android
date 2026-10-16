unit KM_IoXML;
{$I KaM_Remake.inc}
interface
uses
  Classes, SysUtils

  {$IFDEF WDC}
  , Xml.VerySimple // (Attributes can be only 'string', which is not convenient)
  {$ENDIF}
  {$IFDEF FPC}
  , laz2_DOM, laz2_XMLRead, laz2_XMLWrite
  {$ENDIF}
  ;

  // We might try NativeXML (compatible with Android and iOS ?)

type
  {$IFDEF WDC}
  TKMXmlDomDocument = TXmlVerySimple;
//  TKMXmlAttribute = Xml.VerySimple.TXmlAttribute;
  {$ENDIF}
  {$IFDEF FPC}
  TKMXmlDomDocument = TXMLDocument;
  {$ENDIF}

  TKMXmlNode = class;

  TKMSimpleVariant = record
  private
    // Internal representation is always a string
    fValue: string;
    {$IFDEF WDC}
    function ToSimpleVariant: TSimpleVariant;
    {$ENDIF}
  public
    class operator Implicit(const A: Boolean): TKMSimpleVariant;
    class operator Implicit(const A: Cardinal): TKMSimpleVariant;
    class operator Implicit(const A: Integer): TKMSimpleVariant;
    class operator Implicit(const A: Single): TKMSimpleVariant;
    class operator Implicit(const A: string): TKMSimpleVariant;
    class operator Implicit(const A: TDateTime): TKMSimpleVariant;
    function AsBoolean: Boolean; overload;
    function AsBoolean(aDefault: Boolean): Boolean; overload;
    function AsCardinal: Cardinal; overload;
    function AsCardinal(aDefault: Cardinal): Cardinal; overload;
    function AsDateTime: TDateTime;
    function AsFloat: Single; overload;
    function AsFloat(aDefault: Single): Single; overload;
    function AsInteger: Integer; overload;
    function AsInteger(aDefault: Integer): Integer; overload;
    function AsString: string; overload;
    function AsString(aDefault: string): string; overload;
  end;


  TKMXmlDocument = class
  private
    fDocument: TKMXmlDomDocument;
    fRoot: TKMXmlNode;
    function GetText: String;
    procedure SetText(const aText: string);
    procedure ApplyDefaultSettings;

    class constructor Create;
  public
    class var FDateFormat: TFormatSettings;

    constructor Create(const aRoot: string = 'Root');
    destructor Destroy; override;

    property Root: TKMXmlNode read fRoot;

    procedure LoadFromFile(const aFilename: string; aRoot: string  = 'Root'; aReadOnly: Boolean = True);
    procedure SaveToFile(const aFilename: string; aCompressed: Boolean = False);

    property Text: string read GetText write SetText;
  end;


  {$IFDEF WDC}
  TKMXmlNode = class(Xml.VerySimple.TXmlNode)
  {$ENDIF}
  {$IFDEF FPC}
  TKMXmlNode = class(TDOMElement)
  {$ENDIF}
  private

  protected
    function GetAttrib(const AttrName: String): TKMSimpleVariant;
    procedure SetAttrib(const AttrName: String; const AttrValue: TKMSimpleVariant);
    function GetChildsCount: Integer;
    function GetChild(const aIndex: Integer): TKMXmlNode;
  public
    function AddChild(const Name: String): TKMXmlNode; {$IFDEF WDC}reintroduce;{$ENDIF}
    function FindNode(const Name: String): TKMXmlNode; {$IFDEF FPC}reintroduce;{$ENDIF}
    function AddOrFindChild(const aChildNodeName: string): TKMXmlNode;
    function HasAttribute(const AttrName: String): Boolean; {$IFDEF WDC}reintroduce;{$ENDIF}
    function HasChild(const Name: String): Boolean; {$IFDEF WDC}reintroduce;{$ENDIF}
    {$IFDEF FPC}
    // Xml.VerySimple-compatible API (TKMXmlNode is used as a hard-cast of TDOMElement, so no fields allowed here)
    procedure SetAttribute(const AttrName: String; const AttrValue: TKMSimpleVariant); reintroduce;
    procedure Clear;
    {$ENDIF}
    property Attributes[const AttrName: String]: TKMSimpleVariant read GetAttrib write SetAttrib;
    property ChildsCount: Integer read GetChildsCount;
    property Childs[const aIndex: Integer]: TKMXmlNode read GetChild;
  end;


implementation
uses
  Variants, DateUtils, StrUtils;


{ TKMXMLDocument }
class constructor TKMXmlDocument.Create;
begin
  inherited;

  {$IFDEF WDC}
  //todo -cPractical: This code works not as expected. Review and fix
  // On FPC this does not compile at all, since there's no TFormatSettings.Create(string) at all
  FDateFormat := TFormatSettings.Create('dd/mm/yyyy');
  {$ENDIF}
  {$IFDEF FPC}
  FDateFormat := DefaultFormatSettings;
  {$ENDIF}
end;

constructor TKMXmlDocument.Create(const aRoot: string = 'Root');
begin
  inherited Create;

  fDocument := TKMXmlDomDocument.Create;

  ApplyDefaultSettings;

  {$IFDEF WDC}
  if aRoot <> '' then
    fRoot := TKMXmlNode(fDocument.AddChild(aRoot));
  {$ENDIF}

  {$IFDEF FPC}
  if aRoot <> '' then
  begin
    fRoot := TKMXmlNode(fDocument.CreateElement(aRoot));
    fDocument.AppendChild(fRoot);
  end;
  {$ENDIF}
end;


destructor TKMXmlDocument.Destroy;
begin
  fDocument.Free;

  inherited;
end;


procedure TKMXmlDocument.ApplyDefaultSettings;
begin
  {$IFDEF WDC}
  fDocument.Version := '1.0';
  fDocument.Encoding := 'UTF-8';
  fDocument.Options := [doNodeAutoIndent]; // Do not write BOM
  {$ENDIF}
  {$IFDEF FPC}
  fDocument.XMLVersion := '1.0';
  {$ENDIF}
end;


procedure TKMXmlDocument.LoadFromFile(const aFilename: string; aRoot: string  = 'Root'; aReadOnly: Boolean = True);
begin
  {$IFDEF WDC}
    // When no file exists we create an empty XML and let caller handle it
    // e.g. by reading default values from it
    if FileExists(aFilename) then
      fDocument.LoadFromFile(aFilename);
  {$ENDIF}
  {$IFDEF FPC}
    // When no file exists we create an empty XML and let caller handle it
    // e.g. by reading default values from it
    if FileExists(aFilename) then
    begin
      // ReadXMLFile creates a new document instance
      FreeAndNil(fDocument);
      fRoot := nil;
      try
        ReadXMLFile(fDocument, aFilename);
      except
        // Treat broken file as an empty one (same as missing file)
        FreeAndNil(fDocument);
      end;
      if fDocument = nil then
        fDocument := TKMXmlDomDocument.Create;
    end;
  {$ENDIF}

  // Set document Version and Encoding again
  // F.e. after loading empty file Version and Encoding properties are cleared
  ApplyDefaultSettings;

  {$IFDEF WDC}
    fRoot := TKMXmlNode(fDocument.ChildNodes.FindNode(aRoot));

    // Create root if it's missing, so that XML could be processed and default parameters created
    if fRoot = nil then
      fRoot := TKMXmlNode(fDocument.ChildNodes.Add(aRoot));
  {$ENDIF}
  {$IFDEF FPC}
    fRoot := nil;
    if (fDocument.DocumentElement <> nil) and (fDocument.DocumentElement.NodeName = aRoot) then
      fRoot := TKMXmlNode(fDocument.DocumentElement);

    // Create root if it's missing, so that XML could be processed and default parameters created
    if fRoot = nil then
    begin
      // XML document can have only one root element
      if fDocument.DocumentElement <> nil then
        fDocument.RemoveChild(fDocument.DocumentElement).Free;
      fRoot := TKMXmlNode(fDocument.CreateElement(aRoot));
      fDocument.AppendChild(fRoot);
    end;
  {$ENDIF}
end;


procedure TKMXmlDocument.SaveToFile(const aFilename: string; aCompressed: Boolean = False);
begin
  ForceDirectories(ExtractFilePath(ExpandFileName(aFilename)));

  {$IFDEF WDC}
  fDocument.SaveToFile(aFilename);
  {$ENDIF}
  {$IFDEF FPC}
  WriteXMLFile(fDocument, aFilename);
  {$ENDIF}
end;


function TKMXmlDocument.GetText: String;
{$IFDEF FPC}
var
  ss: TStringStream;
{$ENDIF}
begin
  {$IFDEF WDC}
  Result := fDocument.Xml;
  {$ENDIF}
  {$IFDEF FPC}
  ss := TStringStream.Create('');
  try
    WriteXMLFile(fDocument, ss);
    Result := ss.DataString;
  finally
    ss.Free;
  end;
  {$ENDIF}
end;


procedure TKMXmlDocument.SetText(const aText: string);
{$IFDEF FPC}
var
  ss: TStringStream;
  rootName: string;
{$ENDIF}
begin
  {$IFDEF WDC}
  fDocument.Xml := aText;
  {$ENDIF}
  {$IFDEF FPC}
  if fRoot <> nil then
    rootName := fRoot.NodeName
  else
    rootName := 'Root';

  ss := TStringStream.Create(aText);
  try
    FreeAndNil(fDocument);
    fRoot := nil;
    ReadXMLFile(fDocument, ss);
  finally
    ss.Free;
  end;

  if (fDocument.DocumentElement <> nil) and (fDocument.DocumentElement.NodeName = rootName) then
    fRoot := TKMXmlNode(fDocument.DocumentElement);
  {$ENDIF}
end;


{ TKMXmlNode }
function TKMXmlNode.AddChild(const Name: String): TKMXmlNode;
begin
  {$IFDEF WDC}
  Result := TKMXmlNode(inherited AddChild(Name));
  {$ENDIF}
  {$IFDEF FPC}
  Result := TKMXmlNode(OwnerDocument.CreateElement(Name));
  AppendChild(Result);
  {$ENDIF}
end;


function TKMXmlNode.FindNode(const Name: String): TKMXmlNode;
{$IFDEF FPC}
var
  node: TDOMNode;
{$ENDIF}
begin
  {$IFDEF WDC}
  Result := TKMXmlNode(ChildNodes.Find(Name));
  {$ENDIF}
  {$IFDEF FPC}
  // First child element with matching name (case-sensitive, same as Xml.VerySimple with default options)
  Result := nil;
  node := FirstChild;
  while node <> nil do
  begin
    if (node.NodeType = ELEMENT_NODE) and (node.NodeName = Name) then
      Exit(TKMXmlNode(node));
    node := node.NextSibling;
  end;
  {$ENDIF}
end;


{$IFDEF FPC}
procedure TKMXmlNode.SetAttribute(const AttrName: String; const AttrValue: TKMSimpleVariant);
begin
  SetAttrib(AttrName, AttrValue);
end;


procedure TKMXmlNode.Clear;
begin
  // Remove all child nodes and attributes
  while FirstChild <> nil do
    RemoveChild(FirstChild).Free;
  while (TDOMElement(Self).Attributes <> nil) and (TDOMElement(Self).Attributes.Length > 0) do
    TDOMElement(Self).RemoveAttributeNode(TDOMAttr(TDOMElement(Self).Attributes[0])).Free;
end;
{$ENDIF}


function TKMXmlNode.AddOrFindChild(const aChildNodeName: string): TKMXmlNode;
begin
  if not HasChild(aChildNodeName) then
    Result := AddChild(aChildNodeName)
  else
    Result := FindNode(aChildNodeName);
end;



function TKMXmlNode.HasAttribute(const AttrName: String): Boolean;
begin
  {$IFDEF WDC}
  Result := inherited HasAttribute(AttrName);
  {$ENDIF}
  {$IFDEF FPC}
  Result := TDOMElement(Self).hasAttribute(AttrName);
  {$ENDIF}
end;


function TKMXmlNode.HasChild(const Name: String): Boolean;
begin
  {$IFDEF WDC}
  Result := inherited HasChild(Name);
  {$ENDIF}
  {$IFDEF FPC}
  Result := FindNode(Name) <> nil;
  {$ENDIF}
end;


function TKMXmlNode.GetAttrib(const AttrName: String): TKMSimpleVariant;
{$IFDEF WDC}
var
  sv: TSimpleVariant;
{$ENDIF}
begin
  {$IFDEF WDC}
  sv := inherited GetAttr(AttrName);
  Result.fValue := sv.AsString;
  {$ENDIF}
  {$IFDEF FPC}
  // Returns '' for missing attributes, same as Xml.VerySimple
  Result.fValue := TDOMElement(Self).GetAttribute(AttrName);
  {$ENDIF}
end;


procedure TKMXmlNode.SetAttrib(const AttrName: String; const AttrValue: TKMSimpleVariant);
begin
  {$IFDEF WDC}
  inherited SetAttr(AttrName, AttrValue.ToSimpleVariant);
  {$ENDIF}
  {$IFDEF FPC}
  TDOMElement(Self).SetAttribute(AttrName, AttrValue.fValue);
  {$ENDIF}
end;


function TKMXmlNode.GetChildsCount: Integer;
{$IFDEF FPC}
var
  node: TDOMNode;
{$ENDIF}
begin
  {$IFDEF WDC}
  Result := ChildNodes.Count;
  {$ENDIF}
  {$IFDEF FPC}
  // Count element nodes only (whitespace text nodes could appear after parsing)
  Result := 0;
  node := FirstChild;
  while node <> nil do
  begin
    if node.NodeType = ELEMENT_NODE then
      Inc(Result);
    node := node.NextSibling;
  end;
  {$ENDIF}
end;


function TKMXmlNode.GetChild(const aIndex: Integer): TKMXmlNode;
{$IFDEF FPC}
var
  node: TDOMNode;
  idx: Integer;
{$ENDIF}
begin
  {$IFDEF WDC}
  Result := TKMXmlNode(ChildNodes[aIndex]);
  {$ENDIF}
  {$IFDEF FPC}
  Result := nil;
  idx := 0;
  node := FirstChild;
  while node <> nil do
  begin
    if node.NodeType = ELEMENT_NODE then
    begin
      if idx = aIndex then
        Exit(TKMXmlNode(node));
      Inc(idx);
    end;
    node := node.NextSibling;
  end;
  {$ENDIF}
end;


{ ToSimpleVariant}
{$IFDEF WDC}
function TKMSimpleVariant.ToSimpleVariant: TSimpleVariant;
begin
  Result := TSimpleVariant.New(fValue);
end;
{$ENDIF}


function TKMSimpleVariant.AsBoolean: Boolean;
begin
  Result := StrToBool(fValue);
end;


function TKMSimpleVariant.AsBoolean(aDefault: Boolean): Boolean;
begin
  Result := StrToBoolDef(fValue, aDefault);
end;


function TKMSimpleVariant.AsCardinal: Cardinal;
begin
  Result := StrToInt64(fValue);
end;


function TKMSimpleVariant.AsCardinal(aDefault: Cardinal): Cardinal;
begin
  Result := StrToInt64Def(fValue, aDefault);
end;


function TKMSimpleVariant.AsDateTime: TDateTime;
begin
  // This is very slow in Analyzer
  // VarToDateTime seems to be much faster and provide same accuracy
  // But we want to use our custom DateFormat and thus we will use StrToDateTime
  Result := StrToDateTimeDef(fValue, 0, TKMXmlDocument.FDateFormat);
end;


function TKMSimpleVariant.AsFloat: Single;
var
  str: string;
begin
  str := StringReplace(fValue, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  str := StringReplace(str, ',', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  Result := StrToFloat(str);
end;


function TKMSimpleVariant.AsFloat(aDefault: Single): Single;
var
  str: string;
begin
  str := StringReplace(fValue, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  str := StringReplace(str, ',', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  Result := StrToFloatDef(str, aDefault);
end;


function TKMSimpleVariant.AsInteger: Integer;
begin
  Result := StrToInt(fValue);
end;


function TKMSimpleVariant.AsInteger(aDefault: Integer): Integer;
begin
  Result := StrToIntDef(fValue, aDefault);
end;


function TKMSimpleVariant.AsString: string;
begin
  Result := fValue;
end;


function TKMSimpleVariant.AsString(aDefault: string): string;
begin
  if fValue <> '' then
    Result := fValue
  else
    Result := aDefault;
end;


class operator TKMSimpleVariant.Implicit(const A: Boolean): TKMSimpleVariant;
const
  BOOL_STR: array [Boolean] of string = ('False', 'True');
begin
  Result.fValue := BOOL_STR[A];
end;


class operator TKMSimpleVariant.Implicit(const A: Cardinal): TKMSimpleVariant;
begin
  Result.fValue := '$' + IntToHex(A, 8);
end;


class operator TKMSimpleVariant.Implicit(const A: Integer): TKMSimpleVariant;
begin
  Result.fValue := IntToStr(A);
end;


class operator TKMSimpleVariant.Implicit(const A: Single): TKMSimpleVariant;
var
  str: string;
  fs: TFormatSettings;
begin
  {$IFDEF WDC}
  fs := TFormatSettings.Create;
  {$ENDIF}
  {$IFDEF FPC}
  fs := DefaultFormatSettings;
  {$ENDIF}
  fs.DecimalSeparator := '.';


  str := FormatFloat('0.0000', A, fs);

  Result.fValue := str;
end;


class operator TKMSimpleVariant.Implicit(const A: string): TKMSimpleVariant;
begin
  Result.fValue := A;
end;

class operator TKMSimpleVariant.Implicit(const A: TDateTime): TKMSimpleVariant;
begin
  // Still prone to localization issues
  //Result.fValue := FormatDateTime('yyyy.mm.dd hh:nn:ss', A);

  // Custom code ensures we ALWAYS get the same format
  // This format could be system specific, so we better specify date format
  Result.fValue := DateTimeToStr(A, TKMXmlDocument.FDateFormat);
end;


end.
