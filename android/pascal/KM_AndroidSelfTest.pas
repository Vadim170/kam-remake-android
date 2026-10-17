unit KM_AndroidSelfTest;
{$I KaM_Remake.inc}
// Smoke test of game content on the device: starts missions one by one, simulates some game time with
// rendering, checks for exceptions/error messages and logs results ("KAMTEST ..." lines in logcat and
// <data>/Logs/selftest.txt). Started by the host with the launch parameter kam_selftest=<mode>:
//   campaigns      - first mission of every campaign + tutorials (default, fast)
//   campaigns-all  - every mission of every campaign
//   maps           - every single player map and tutorial
//   all            - campaigns-all + maps
//   only:<text>    - items of 'all' whose name contains <text> (e.g. only:Isles of Sydrian)
interface

procedure SelfTestStart(const aMode: string);
function SelfTestActive: Boolean;
// Called every frame before the game frame
procedure SelfTestFrame;

implementation
uses
  Classes, SysUtils, StrUtils, Math,
  KM_GameApp, KM_Game, KM_Defaults, KM_Campaigns, KM_CommonUtils,
  KMAndroidHost, KMAndroidLog;

const
  TICKS_PER_ITEM = 200;   // 20 s of game time at normal speed: mission start, AI and scripts run
  TICKS_PER_FRAME = 20;   // fast forward, but still render every frame
  MAX_ITEM_TIME_MS = 120000;

type
  TKMTestKind = (tkCampaign, tkMap);

  TKMTestItem = record
    Kind: TKMTestKind;
    Name: string;
    CampaignId: string;
    MissionIndex: Integer;
    Path: string;
  end;

  TKMTestState = (tsIdle, tsScanCampaigns, tsNextItem, tsRunning, tsDone);

  TKMSelfTest = class
  private
    fMode: string;
    fState: TKMTestState;
    fItems: array of TKMTestItem;
    fIndex: Integer;
    fTicksDone: Integer;
    fItemStart: QWord;
    fLastProgress: QWord;
    fScanDone: Boolean;
    fError: string;
    fResults: TStringList;
    fPassed, fFailed: Integer;
    procedure CampaignsScanned(Sender: TObject);
    procedure AddCampaignItems(aAllMissions: Boolean);
    procedure AddMapItems(const aFolder: string);
    procedure FinishItem(aOk: Boolean; const aReason: string);
    procedure Report(const aText: string);
  public
    constructor Create(const aMode: string);
    destructor Destroy; override;
    procedure Frame;
  end;

var
  gSelfTest: TKMSelfTest;
  fOldShowMessage: TKMHostMessageProc;


// Error dialogs of the game are failures during the test
procedure TestShowMessage(const aTitle, aText: UnicodeString);
begin
  ALog('KAMTEST message: ' + string(aText));
  if (gSelfTest <> nil) and (gSelfTest.fError = '') then
    gSelfTest.fError := string(aText);
end;


procedure SelfTestStart(const aMode: string);
begin
  if gSelfTest <> nil then Exit;
  gSelfTest := TKMSelfTest.Create(aMode);
  fOldShowMessage := gHostShowMessage;
  gHostShowMessage := TestShowMessage;
end;


function SelfTestActive: Boolean;
begin
  Result := (gSelfTest <> nil) and (gSelfTest.fState <> tsDone);
end;


procedure SelfTestFrame;
begin
  if gSelfTest <> nil then
    gSelfTest.Frame;
end;


{ TKMSelfTest }
constructor TKMSelfTest.Create(const aMode: string);
begin
  inherited Create;
  fMode := LowerCase(aMode);
  fResults := TStringList.Create;
  fState := tsScanCampaigns;
  Report('KAMTEST BEGIN mode=' + fMode);
  // Rescan campaigns and wait for the scanner thread
  gGameApp.Campaigns.Refresh(nil, nil, CampaignsScanned);
end;


destructor TKMSelfTest.Destroy;
begin
  fResults.Free;
  inherited;
end;


procedure TKMSelfTest.Report(const aText: string);
begin
  ALog(aText);
  fResults.Add(aText);
end;


procedure TKMSelfTest.CampaignsScanned(Sender: TObject);
begin
  fScanDone := True;
end;


procedure TKMSelfTest.AddCampaignItems(aAllMissions: Boolean);
var
  I, K, cnt: Integer;
  C: TKMCampaign;
begin
  for I := 0 to gGameApp.Campaigns.Count - 1 do
  begin
    C := gGameApp.Campaigns[I];
    cnt := IfThen(aAllMissions, C.Spec.MissionsCount, Min(1, C.Spec.MissionsCount));
    for K := 0 to cnt - 1 do
    begin
      SetLength(fItems, Length(fItems) + 1);
      with fItems[High(fItems)] do
      begin
        Kind := tkCampaign;
        CampaignId := string(C.Spec.IdStr);
        MissionIndex := K;
        Name := Format('campaign %s mission %d', [CampaignId, K + 1]);
      end;
    end;
  end;
end;


procedure TKMSelfTest.AddMapItems(const aFolder: string);
var
  sr: TSearchRec;
  dir: string;
begin
  dir := ExeDir + aFolder + PathDelim;
  if FindFirst(dir + '*', faDirectory, sr) = 0 then
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') or (sr.Attr and faDirectory = 0) then Continue;
      if FileExists(dir + sr.Name + PathDelim + sr.Name + '.dat') then
      begin
        SetLength(fItems, Length(fItems) + 1);
        with fItems[High(fItems)] do
        begin
          Kind := tkMap;
          Path := dir + sr.Name + PathDelim + sr.Name + '.dat';
          Name := aFolder + '/' + sr.Name;
        end;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;


procedure TKMSelfTest.FinishItem(aOk: Boolean; const aReason: string);
begin
  try
    if gGame <> nil then
      gGameApp.StopGame(grSilent);
  except
    on E: Exception do
    begin
      aOk := False;
      Report('KAMTEST exception while stopping: ' + E.Message);
    end;
  end;

  if aOk then
  begin
    Inc(fPassed);
    Report(Format('KAMTEST OK   %d/%d %s (%d ticks, %d ms)', [fIndex + 1, Length(fItems), fItems[fIndex].Name, fTicksDone, GetTickCount64 - fItemStart]));
  end else
  begin
    Inc(fFailed);
    Report(Format('KAMTEST FAIL %d/%d %s: %s', [fIndex + 1, Length(fItems), fItems[fIndex].Name, aReason]));
  end;
  Inc(fIndex);
  fState := tsNextItem;
end;


procedure TKMSelfTest.Frame;
var
  I: Integer;
  item: TKMTestItem;
begin
  case fState of
    tsScanCampaigns:
      if fScanDone then
      begin
        if (fMode = 'campaigns') or (fMode = 'campaigns-all') or (fMode = 'all') then
          AddCampaignItems(fMode <> 'campaigns');
        if fMode = 'campaigns' then
          AddMapItems('Tutorials');
        if (fMode = 'maps') or (fMode = 'all') then
        begin
          AddMapItems('Tutorials');
          AddMapItems('Maps');
        end;
        if Copy(fMode, 1, 5) = 'only:' then
        begin
          AddCampaignItems(True);
          AddMapItems('Tutorials');
          AddMapItems('Maps');
          for I := High(fItems) downto 0 do
            if Pos(Copy(fMode, 6, MaxInt), LowerCase(fItems[I].Name)) = 0 then
              Delete(fItems, I, 1);
        end;
        Report(Format('KAMTEST items=%d', [Length(fItems)]));
        fIndex := 0;
        fState := tsNextItem;
      end;

    tsNextItem:
      if fIndex >= Length(fItems) then
      begin
        Report(Format('KAMTEST DONE passed=%d failed=%d', [fPassed, fFailed]));
        try
          fResults.SaveToFile(ExeDir + 'Logs' + PathDelim + 'selftest.txt');
        except
          on E: Exception do
            ALog('KAMTEST can''t save results: ' + E.Message);
        end;
        gHostShowMessage := fOldShowMessage;
        fState := tsDone;
        if Assigned(gHostQuit) then
          gHostQuit;
      end else
      begin
        item := fItems[fIndex];
        ALog(Format('KAMTEST START %d/%d %s', [fIndex + 1, Length(fItems), item.Name]));
        fError := '';
        fTicksDone := 0;
        fItemStart := GetTickCount64;
        try
          case item.Kind of
            tkCampaign: gGameApp.NewGameCampaignMap(UnicodeString(item.CampaignId), item.MissionIndex);
            tkMap:      gGameApp.NewGameSingleMap(UnicodeString(item.Path), UnicodeString(ExtractFileName(ChangeFileExt(item.Path, ''))));
          end;
          if gGame = nil then
            FinishItem(False, 'game was not created' + IfThen(fError <> '', ': ' + fError, ''))
          else
            fState := tsRunning;
        except
          on E: Exception do
            FinishItem(False, E.ClassName + ': ' + E.Message);
        end;
      end;

    tsRunning:
      try
        if fError <> '' then
          FinishItem(False, fError)
        else
        if gGame = nil then
          // Mission may end by itself (scripts), which is fine
          FinishItem(True, '')
        else
        begin
          gGame.IsPaused := False;
          for I := 1 to TICKS_PER_FRAME do
          begin
            gGameApp.DoGameTick;
            Inc(fTicksDone);
            if (gGame = nil) or (fTicksDone >= TICKS_PER_ITEM) then Break;
          end;
          if GetTickCount64 - fLastProgress > 5000 then
          begin
            fLastProgress := GetTickCount64;
            ALog(Format('KAMTEST progress %s: %d ticks in %d ms', [fItems[fIndex].Name, fTicksDone, GetTickCount64 - fItemStart]));
          end;
          if fTicksDone >= TICKS_PER_ITEM then
            FinishItem(True, '')
          else
          if GetTickCount64 - fItemStart > MAX_ITEM_TIME_MS then
            FinishItem(False, Format('timeout after %d ticks', [fTicksDone]));
        end;
      except
        on E: Exception do
          FinishItem(False, E.ClassName + ': ' + E.Message);
      end;
  end;
end;


end.
