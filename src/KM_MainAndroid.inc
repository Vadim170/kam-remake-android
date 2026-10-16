// Android implementation of KM_Main (included from KM_Main.pas when ANDROID is defined)
// There are no forms on Android: Java GLSurfaceView owns the GL context and drives frames,
// input arrives through KM_AndroidHost (JNI glue)
interface
uses
  Classes, Types,
  KM_Defaults, KM_Maps, KM_MainSettings, KM_Resolutions, KM_Video,
  KM_WindowParams, KM_GameAppSettings, KM_RenderControl, KM_GameTypes;


type
  // Stand-in for the desktop TFormMain. Game code calls into it on game start/end and similar events
  TKMFormMainStub = class
  private
    fRenderArea: TKMRenderControl;
  public
    SuppressAltForMenu: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure ControlsReset;
    procedure ControlsRefill;
    procedure SetExportGameStats(aValue: Boolean);
    procedure GameStarted(aMode: TKMGameMode);
    procedure GameEnded(aMode: TKMGameMode);
    procedure SetMySpecHandIndex(aHandIndex: Integer);
    procedure SetEntitySelected(aEntityUID: Integer; aEntity2UID: Integer = 0);
    procedure Defocus;
    property RenderArea: TKMRenderControl read fRenderArea;
  end;

  TKMMain = class
  private
    fFormMain: TKMFormMainStub;
    fGameTickInterval: Cardinal;
    fTickSchedule, fUpdateStateSchedule: Cardinal;
    fLastRenderTime, fOldFrameTimes, fFrameCount: Cardinal;
    fResolutions: TKMResolutions;
    fMapCacheUpdater: TTMapsCacheUpdater;
    fFPS: Single;
    fFPSString: String;
    fStarted: Boolean;

    procedure UpdateFPS(aLatestFrameTime: Cardinal);
    procedure MapCacheUpdate;
    procedure HandleLoadingStep;
    procedure HandleLoadingText(const aText: UnicodeString);
  public
    constructor Create;
    destructor Destroy; override;

    // Android entry points
    function Start(aWidth, aHeight: Integer): Boolean;
    procedure Frame;
    procedure SurfaceResized(aWidth, aHeight: Integer);
    procedure AppPause;
    procedure AppResume;
    property Started: Boolean read fStarted;

    // API used by the game code (same as on desktop)
    procedure Stop(Sender: TObject);
    procedure ForceResize;
    procedure Resize(aWidth, aHeight: Integer);
    procedure Render;
    procedure ShowAbout;
    property FormMain: TKMFormMainStub read fFormMain;

    procedure ApplyCursorRestriction;
    function GetScreenBounds(out aBounds: TRect): Boolean;
    function IsFormActive: Boolean;
    function ClientRect(aPixelsCntToReduce: Integer = 0): TRect;
    function ClientToScreen(aPoint: TPoint): TPoint;
    function ReinitRender(aReturnToOptions: Boolean): Boolean;

    property FPSString: String read fFPSString;

    function IsDebugChangeAllowed: Boolean;

    function LockMutex: Boolean;
    procedure UnlockMutex;

    procedure HandleStatusBarText(aPanelIndex: TKMStatusBarPanel; aText: string);

    procedure SetGameTickInterval(aInterval: Cardinal);
    property GameTickInterval: Cardinal read fGameTickInterval;

    property Resolutions: TKMResolutions read fResolutions;
  end;


var
  gMain: TKMMain;


implementation
uses
  SysUtils, SysConst, StrUtils, Math,
  KromUtils, KM_FileIO,
  KM_GameApp, KM_System,
  KM_ResTexts, KM_KeysSettings, KM_Music,
  KM_Log, KM_CommonUtils, KM_Points,
  KM_CommonExceptions, KM_MapTypes, KM_GameSettings,
  KMAndroidHost, KMAndroidLog;


{$OVERFLOWCHECKS OFF}
function AddWithOverflow(A, B: Cardinal): Cardinal; inline;
begin
  Result := A + B;
end;
{$OVERFLOWCHECKS ON}


{ TKMFormMainStub }
constructor TKMFormMainStub.Create;
begin
  inherited;
  fRenderArea := TKMRenderControl.Create(nil);
end;


destructor TKMFormMainStub.Destroy;
begin
  fRenderArea.Free;
  inherited;
end;


procedure TKMFormMainStub.ControlsReset; begin end;
procedure TKMFormMainStub.ControlsRefill; begin end;
procedure TKMFormMainStub.SetExportGameStats(aValue: Boolean); begin end;
procedure TKMFormMainStub.GameStarted(aMode: TKMGameMode); begin end;
procedure TKMFormMainStub.GameEnded(aMode: TKMGameMode); begin end;
procedure TKMFormMainStub.SetMySpecHandIndex(aHandIndex: Integer); begin end;
procedure TKMFormMainStub.SetEntitySelected(aEntityUID: Integer; aEntity2UID: Integer = 0); begin end;
procedure TKMFormMainStub.Defocus; begin end;


// Assertion error handler
procedure CustomAssertErrorHandler(const Message, Filename: ShortString; LineNumber: LongInt; ErrorAddr: Pointer);
var
  fileNameOnly: string;
begin
  fileNameOnly := ExtractFileName(string(Filename));

  if Message <> '' then
    raise EAssertionFailed.CreateFmt(SAssertError, [string(Message), fileNameOnly, LineNumber]) at ErrorAddr
  else
    raise EAssertionFailed.CreateFmt(SAssertError, [SAssertionFailed, fileNameOnly, LineNumber]) at ErrorAddr;
end;


{ TKMMain }
constructor TKMMain.Create;
begin
  inherited;
  fGameTickInterval := 100;
  fFormMain := TKMFormMainStub.Create;
end;


destructor TKMMain.Destroy;
begin
  fFormMain.Free;
  inherited;
end;


procedure TKMMain.HandleLoadingStep;
begin
  //No splash form on Android, loading screen is shown by the Android host
end;


procedure TKMMain.HandleLoadingText(const aText: UnicodeString);
begin
  ALog('Loading: ' + string(aText));
end;


// ExeDir must be set by the host before Start (game data root folder)
function TKMMain.Start(aWidth, aHeight: Integer): Boolean;
var
  logsPath: UnicodeString;
  time: Cardinal;
begin
  Result := True;
  time := TimeGet;

  AssertErrorProc := @CustomAssertErrorHandler;

  Randomize;

  logsPath := ExeDir + 'Logs' + PathDelim + 'KaM_' + FormatDateTime('yyyy-mm-dd_hh-nn-ss-zzz', Now) + '.log';
  CreateDir(ExeDir + 'Logs' + PathDelim);
  gLog := TKMLog.Create(logsPath);
  gLog.DeleteOldLogs(LOGS_DELETE_WHEN_OLDER_THAN);
  gLog.AddTime('Game Load started (Android)');

  fFormMain.RenderArea.SetBounds(0, 0, aWidth, aHeight);

  fResolutions := TKMResolutions.Create;

  gGameAppSettings := TKMGameAppSettings.Create(aWidth, aHeight);
  // Android app is always fullscreen, the window is managed by the OS
  gMainSettings.FullScreen := False;

  gVideoPlayer := TKMVideoPlayer.Create(True);

  if not ReinitRender(False) then
    Exit(False);

  gSystem := TKMSystem.Create(0);

  MapCacheUpdate;

  // Same as desktop TFormMain: intro videos on startup (if enabled in game options)
  if (gGameSettings <> nil) and gGameSettings.Video.PlayOnStartup then
  begin
    gVideoPlayer.AddVideo(CAMPAIGNS_FOLDER_NAME + PathDelim + 'The Peasants Rebellion' + PathDelim + 'Logo', vfkStarting);
    gVideoPlayer.AddVideo('KaM', vfkStarting);
    gVideoPlayer.Play;
  end;

  fStarted := True;
  gLog.AddTime('Game Load Done in ' + IntToStr(TimeSince(time)));
end;


procedure TKMMain.HandleStatusBarText(aPanelIndex: TKMStatusBarPanel; aText: string);
begin
  //No status bar on Android
end;


procedure TKMMain.Stop(Sender: TObject);
begin
  try
    if gLog <> nil then
      gLog.AddTime('Stopping game application...');
    FreeThenNil(gSystem);
    FreeThenNil(fResolutions);

    if fMapCacheUpdater <> nil then
      fMapCacheUpdater.Stop;

    if gKeySettings <> nil then
      gKeySettings.SaveToXML;

    FreeThenNil(gGameApp);
    FreeThenNil(gGameAppSettings);

    FreeAndNil(gVideoPlayer);

    FreeThenNil(gLog);
  except
    on E: Exception do
      ALog('Exception while closing game app: ' + E.Message);
  end;

  fStarted := False;
  // Ask the Android host to finish the activity
  if Assigned(gHostQuit) then
    gHostQuit;
end;


procedure TKMMain.AppPause;
begin
  gHostAppActive := False;
  // Pause single player game when app goes to background
  if (gGameApp <> nil) and (gGameApp.Game <> nil)
  and not gGameApp.Game.Params.IsMultiPlayerOrSpec
  and not gGameApp.Game.Params.IsMapEditor
  and not gGameApp.Game.Params.IsReplay then
    gGameApp.Game.IsPaused := True;

  if gMusic <> nil then
    gMusic.Pause;

  // Android may kill a background app without notice: persist settings now
  try
    if gGameAppSettings <> nil then
      gGameAppSettings.SaveSettings;
    if gKeySettings <> nil then
      gKeySettings.SaveToXML;
  except
    on E: Exception do
      ALog('Saving settings on pause failed: ' + E.Message);
  end;
end;


procedure TKMMain.AppResume;
begin
  gHostAppActive := True;
  if gMusic <> nil then
    gMusic.Resume;
end;


procedure TKMMain.UpdateFPS(aLatestFrameTime: Cardinal);
begin
  if gMainSettings = nil then Exit;

  Inc(fOldFrameTimes, aLatestFrameTime);
  Inc(fFrameCount);
  if fOldFrameTimes >= FPS_INTERVAL then
  begin
    fFPS := 1000 / (fOldFrameTimes / fFrameCount);
    if gGameApp <> nil then
      gGameApp.SendFPSMeasurement(Round(fFPS));

    fFPSString := Format('%.1f FPS', [fFPS]);
    fOldFrameTimes := 0;
    fFrameCount := 0;
  end;
end;


// Called by GLSurfaceView for every frame. Does all due game ticks, UI update and render
procedure TKMMain.Frame;
const
  UI_UPDATE_INTERVAL = 100;
  MAX_TICKS_PER_FRAME = 10; //Don't freeze the UI if the device can't keep up with the game speed
var
  ticksDone: Integer;
  timeSinceTick, timeSinceUpdateUI, renderDelta: Cardinal;
begin
  if (gGameApp = nil) or not fStarted then Exit;

  ticksDone := 0;
  timeSinceTick := TimeSince(fTickSchedule);
  while (timeSinceTick >= fGameTickInterval) and (ticksDone < MAX_TICKS_PER_FRAME) do
  begin
    gGameApp.DoGameTick;
    if gGameApp = nil then Exit;
    Inc(ticksDone);
    fTickSchedule := AddWithOverflow(fTickSchedule, fGameTickInterval);
    timeSinceTick := TimeSince(fTickSchedule);
  end;
  // Too far behind - skip the backlog instead of fast-forwarding later
  if timeSinceTick >= fGameTickInterval then
    fTickSchedule := TimeGet;

  timeSinceUpdateUI := TimeSince(fUpdateStateSchedule);
  if timeSinceUpdateUI >= UI_UPDATE_INTERVAL then
  begin
    gGameApp.UpdateState;
    if gGameApp = nil then Exit;
    fUpdateStateSchedule := AddWithOverflow(fUpdateStateSchedule, (timeSinceUpdateUI div UI_UPDATE_INTERVAL) * UI_UPDATE_INTERVAL);
  end;

  renderDelta := TimeSince(fLastRenderTime);
  fLastRenderTime := TimeGet;
  UpdateFPS(renderDelta);

  gGameApp.UpdateStateIdle(renderDelta);
  gGameApp.Render;
end;


procedure TKMMain.SurfaceResized(aWidth, aHeight: Integer);
begin
  fFormMain.RenderArea.SetBounds(0, 0, aWidth, aHeight);
  Resize(aWidth, aHeight);
end;


function TKMMain.ReinitRender(aReturnToOptions: Boolean): Boolean;
begin
  Result := True;

  FreeThenNil(gGameApp); //Saves all settings into ini file in midst
  gGameApp := TKMGameApp.Create(fFormMain.RenderArea,
                                fFormMain.RenderArea.Width,
                                fFormMain.RenderArea.Height,
                                gMainSettings.VSync,
                                HandleLoadingStep,
                                HandleLoadingText,
                                HandleStatusBarText);

  gGameApp.AfterConstruction(aReturnToOptions);

  //Preload game resources while in menu to make 1st game start faster
  gGameApp.PreloadGameResources;

  gLog.AddTime('Render area: %dx%d', [fFormMain.RenderArea.Width, fFormMain.RenderArea.Height]);

  ForceResize;
end;


function TKMMain.LockMutex: Boolean;
begin
  Result := True;
end;


procedure TKMMain.UnlockMutex;
begin
end;


procedure TKMMain.MapCacheUpdate;
begin
  // Thread frees itself automatically
  fMapCacheUpdater := TTMapsCacheUpdater.Create([mkSP, mkMP, mkDL]);
end;


function TKMMain.IsDebugChangeAllowed: Boolean;
begin
  Result := (gGameApp.Game = nil)
            or not gGameApp.Game.Params.IsMultiPlayerOrSpec
            or MULTIPLAYER_CHEATS;
end;


function TKMMain.ClientRect(aPixelsCntToReduce: Integer = 0): TRect;
begin
  Result := fFormMain.RenderArea.ClientRect;
  Inc(Result.Left, aPixelsCntToReduce);
  Inc(Result.Top, aPixelsCntToReduce);
  Dec(Result.Right, aPixelsCntToReduce);
  Dec(Result.Bottom, aPixelsCntToReduce);
end;


function TKMMain.ClientToScreen(aPoint: TPoint): TPoint;
begin
  Result := aPoint;
end;


function TKMMain.GetScreenBounds(out aBounds: TRect): Boolean;
begin
  aBounds := fFormMain.RenderArea.ClientRect;
  Result := True;
end;


function TKMMain.IsFormActive: Boolean;
begin
  Result := gHostAppActive;
end;


procedure TKMMain.Render;
begin
  if Self = nil then Exit;

  gGameApp.Render;
end;


procedure TKMMain.ForceResize;
begin
  Resize(fFormMain.RenderArea.Width, fFormMain.RenderArea.Height);
end;


procedure TKMMain.Resize(aWidth, aHeight: Integer);
begin
  if (Self = nil) or (gGameApp = nil) then Exit;

  gGameApp.Resize(aWidth, aHeight);
end;


procedure TKMMain.SetGameTickInterval(aInterval: Cardinal);
begin
  if Self = nil then Exit;

  fGameTickInterval := aInterval;
end;


procedure TKMMain.ShowAbout;
begin
end;


procedure TKMMain.ApplyCursorRestriction;
begin
  //No cursor on a touch screen
end;
