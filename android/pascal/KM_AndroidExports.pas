unit KM_AndroidExports;
{$I KaM_Remake.inc}
// C API of the engine for the Android host (libkamhost.so, JNI glue).
// All calls must come from the GL thread, except the KMAndroidHost state setters.
// Touch input is translated here into the mouse events the original game UI expects:
//  - tap on UI or map = left click
//  - one finger drag on UI = left button drag (sliders, scrollbars, minimap)
//  - one finger drag on map = scroll the map (or left button drag while a build/editor tool is active)
//  - long press on map = right button press; keep holding and move to pick troop direction, release to finish
//  - two finger tap = right click
//  - pinch = zoom, two finger drag = scroll
interface

type
  TKMHostCallbacks = record
    ShowMessage: procedure(aTitle, aText: PAnsiChar); cdecl;
    ClipboardSet: procedure(aText: PAnsiChar); cdecl;
    ClipboardGet: function: PAnsiChar; cdecl; // Returned string is owned by the host and valid until next call
    OpenURL: procedure(aURL: PAnsiChar); cdecl;
    Quit: procedure; cdecl;
    PlayVideo: procedure(aPath: PAnsiChar; aVolume, aStretch: Integer); cdecl;
    StopVideo: procedure; cdecl;
  end;
  PKMHostCallbacks = ^TKMHostCallbacks;

const
  TOUCH_DOWN = 0;
  TOUCH_MOVE = 1;
  TOUCH_UP = 2;
  TOUCH_CANCEL = 3;
  TOUCH_POINTER_DOWN = 5;
  TOUCH_POINTER_UP = 6;

  KEY_DOWN = 0;
  KEY_UP = 1;

procedure kam_set_callbacks(aCallbacks: PKMHostCallbacks); cdecl;
function kam_init(aDataDir: PAnsiChar; aWidth, aHeight: Integer): Integer; cdecl;
procedure kam_frame; cdecl;
procedure kam_resize(aWidth, aHeight: Integer); cdecl;
procedure kam_pause; cdecl;
procedure kam_resume; cdecl;
procedure kam_shutdown; cdecl;
procedure kam_touch(aAction, aPointerCount: Integer; X0, Y0, X1, Y1: Single); cdecl;
procedure kam_mouse(aAction, aButton, X, Y: Integer); cdecl;
procedure kam_wheel(aSteps, X, Y: Integer); cdecl;
procedure kam_key(aAction, aVirtualKey, aShift: Integer); cdecl;
procedure kam_char(aUnicodeChar: Integer); cdecl;
procedure kam_back; cdecl;
function kam_text_input_active: Integer; cdecl;
procedure kam_video_finished; cdecl;
function kam_in_game: Integer; cdecl;
function kam_text_input_bottom: Integer; cdecl;
function kam_text_field_tapped: Integer; cdecl;
procedure kam_selftest(aMode: PAnsiChar); cdecl;

implementation
uses
  Classes, SysUtils, Math, Types, Controls, LCLType, BaseUnix,
  KM_Main, KM_GameApp, KM_Defaults, KM_Points, KM_Cursor,
  KM_InterfaceDefaults, KM_InterfaceGame, KM_InterfaceGamePlay, KM_InterfaceMapEditor, KM_Game, KM_Viewport,
  KM_Controls, KM_ControlsEdit,
  KM_Log, dglOpenGL, KM_ResSprites, KM_ResTypes, KM_Video, KM_Render,
  KM_AndroidSelfTest,
  KMAndroidHost, KMAndroidLog;

const
  TAP_SLOP = 14;          // px (render resolution) finger can move and still be a tap
  LONG_PRESS_MS = 450;    // hold time to become a right button press
  TWO_FINGER_TAP_MS = 300;

type
  TKMTouchState = (tsIdle, tsUIDrag, tsMapPending, tsMapPan, tsMapDragLeft, tsRightHold, tsPinch, tsConsumed,
                   tsSidebarPending, tsSidebarScroll);

var
  gCallbacks: TKMHostCallbacks;
  fTouchState: TKMTouchState = tsIdle;
  fDownPos, fLastPos: TPointF;
  fDownTime: QWord;
  fButtons: TShiftState = [];
  // Pinch
  fPinchStartDist, fPinchStartZoom: Single;
  fPinchLastMid: TPointF;
  fPinchStartTime: QWord;
  fPinchMoved: Boolean;
  fClipboardText: UnicodeString;
  fTextFieldTapped: Boolean;


function MakePointF(aX, aY: Single): TPointF;
begin
  Result.X := aX;
  Result.Y := aY;
end;


function CellPx(aViewport: TKMViewport): Single;
begin
  Result := CELL_SIZE_PX * aViewport.Zoom;
end;


procedure HostShowMessage(const aTitle, aText: UnicodeString);
begin
  if Assigned(gCallbacks.ShowMessage) then
    gCallbacks.ShowMessage(PAnsiChar(UTF8Encode(aTitle)), PAnsiChar(UTF8Encode(aText)));
end;

procedure HostClipboardSet(const aText: UnicodeString);
begin
  if Assigned(gCallbacks.ClipboardSet) then
    gCallbacks.ClipboardSet(PAnsiChar(UTF8Encode(aText)));
end;

function HostClipboardGet: UnicodeString;
begin
  Result := '';
  if Assigned(gCallbacks.ClipboardGet) then
    Result := UTF8Decode(gCallbacks.ClipboardGet());
end;

procedure HostOpenURL(const aURL: UnicodeString);
begin
  if Assigned(gCallbacks.OpenURL) then
    gCallbacks.OpenURL(PAnsiChar(UTF8Encode(aURL)));
end;

procedure HostPlayVideo(const aPath: UnicodeString; aVolume: Integer; aStretch: Boolean);
begin
  if Assigned(gCallbacks.PlayVideo) then
    gCallbacks.PlayVideo(PAnsiChar(UTF8Encode(aPath)), aVolume, Ord(aStretch));
end;

procedure HostStopVideo;
begin
  if Assigned(gCallbacks.StopVideo) then
    gCallbacks.StopVideo();
end;

procedure HostQuit;
begin
  if Assigned(gCallbacks.Quit) then
    gCallbacks.Quit();
end;


procedure kam_set_callbacks(aCallbacks: PKMHostCallbacks); cdecl;
begin
  gCallbacks := aCallbacks^;
  gHostShowMessage := HostShowMessage;
  gHostClipboardSet := HostClipboardSet;
  gHostClipboardGet := HostClipboardGet;
  gHostOpenURL := HostOpenURL;
  gHostQuit := HostQuit;
  gHostPlayVideo := HostPlayVideo;
  gHostStopVideo := HostStopVideo;
end;


{$IFDEF ANDROID_GLDEBUG}
var
  fOrigPopMatrix: TglPopMatrix;
  fOrigPopAttrib: TglPopAttrib;

// Debug: crash with a stack trace on GL stack underflow
procedure DbgCheckUnderflow(const aWhat: string);
begin
  if glGetError = GL_STACK_UNDERFLOW then
  begin
    ALog('GL stack underflow in ' + aWhat + ', crashing for stack trace');
    PInteger(nil)^ := 0;
  end;
end;

procedure DbgPopMatrix; cdecl;
begin
  glGetError;
  fOrigPopMatrix();
  DbgCheckUnderflow('glPopMatrix');
end;

procedure DbgPopAttrib; cdecl;
begin
  glGetError;
  fOrigPopAttrib();
  DbgCheckUnderflow('glPopAttrib');
end;

procedure InstallGLDebugHooks;
begin
  if not FileExists(ExeDir + 'glhooks.txt') then Exit;
  fOrigPopMatrix := glPopMatrix;
  fOrigPopAttrib := glPopAttrib;
  glPopMatrix := DbgPopMatrix;
  glPopAttrib := DbgPopAttrib;
  ALog('GL debug hooks installed');
end;

{$ENDIF}

{$IFDEF ANDROID_MEMDEBUG}
var
  fOldMM: TMemoryManager;

procedure LogBigAlloc(aSize: PtrUInt);
var
  bp, addr: Pointer;
  I: Integer;
  s: string;
begin
  s := Format('HUGE ALLOC %d MB, kam_frame=%p stack:', [aSize shr 20, Pointer(@kam_frame)]);
  bp := get_frame;
  for I := 0 to 25 do
  begin
    if bp = nil then Break;
    addr := get_caller_addr(bp);
    s := s + ' ' + HexStr(addr);
    bp := get_caller_frame(bp);
  end;
  ALog(s);
end;

function DbgGetMem(aSize: PtrUInt): Pointer;
begin
  if aSize > 512 shl 20 then
  begin
    LogBigAlloc(aSize);
    Exit(nil);
  end;
  Result := fOldMM.GetMem(aSize);
end;

function DbgReAllocMem(var p: Pointer; aSize: PtrUInt): Pointer;
begin
  if aSize > 512 shl 20 then
  begin
    LogBigAlloc(aSize);
    Exit(nil);
  end;
  Result := fOldMM.ReAllocMem(p, aSize);
end;

procedure InstallMemDebug;
var
  mm: TMemoryManager;
begin
  GetMemoryManager(fOldMM);
  mm := fOldMM;
  mm.GetMem := DbgGetMem;
  mm.ReAllocMem := DbgReAllocMem;
  SetMemoryManager(mm);
end;
{$ENDIF}

function kam_init(aDataDir: PAnsiChar; aWidth, aHeight: Integer): Integer; cdecl;
begin
  {$IFDEF ANDROID_MEMDEBUG}
  InstallMemDebug;
  {$ENDIF}
  Result := 0;
  try
    // Engine threads use TThread.Synchronize/Queue, which run on MainThreadID when it calls CheckSynchronize.
    // The library was loaded on the Java UI thread, but the engine lives on the GL thread
    MainThreadID := GetCurrentThreadId;
    // Network code must not be killed by writes to closed sockets
    fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
    // Touch screen has no hovering cursor: scrolling the map by holding the cursor at the screen edge
    // would trigger from the last touch point. It is re-enabled when a physical mouse is used
    IGNORE_MOUSE_SCROLLING := True;
    ExeDir := IncludeTrailingPathDelimiter(UTF8Decode(aDataDir));
    gHostScreenWidth := aWidth;
    gHostScreenHeight := aHeight;
    ALog(Format('kam_init: %s %dx%d', [string(ExeDir), aWidth, aHeight]));

    gMain := TKMMain.Create;
    {$IFDEF ANDROID_GLDEBUG}
    gOnGLInitialized := InstallGLDebugHooks;
    {$ENDIF}
    if gMain.Start(aWidth, aHeight) then
      Result := 1;
  except
    on E: Exception do
    begin
      ALog('kam_init failed: ' + E.ClassName + ': ' + E.Message);
      HostShowMessage('KaM Remake', UnicodeString('Error starting the game:' + sLineBreak + E.Message));
    end;
  end;
end;


procedure CheckLongPress; forward;

var
  fLastGLErrorLog: QWord;

{$IFDEF ANDROID_GLDEBUG}
var
  fLastGLStateLog: QWord;

procedure LogGLState;
const
  CAPS: array [0..11] of GLenum = (GL_DEPTH_TEST, GL_STENCIL_TEST, GL_ALPHA_TEST, GL_BLEND, GL_SCISSOR_TEST, GL_TEXTURE_2D, GL_CULL_FACE, GL_LIGHTING,
                                   GL_CLIP_PLANE0, GL_CLIP_PLANE1, GL_CLIP_PLANE2, GL_CLIP_PLANE3);
  NAMES: array [0..11] of string = ('depth', 'stencil', 'alpha', 'blend', 'scissor', 'tex2d', 'cull', 'light', 'clip0', 'clip1', 'clip2', 'clip3');
var
  I: Integer;
  s: string;
  v: array [0..15] of GLint;
  f: array [0..15] of GLfloat;
begin
  if GetTickCount64 - fLastGLStateLog < 5000 then Exit;
  fLastGLStateLog := GetTickCount64;
  s := '';
  for I := 0 to High(CAPS) do
    if glIsEnabled(CAPS[I]) then s := s + NAMES[I] + ' ';
  glGetIntegerv(GL_BLEND_SRC, @v[0]); glGetIntegerv(GL_BLEND_DST, @v[1]);
  s := s + Format('blend=%x/%x ', [v[0], v[1]]);
  glGetIntegerv(GL_MATRIX_MODE, @v[0]); s := s + Format('mm=%x ', [v[0]]);
  glGetIntegerv(GL_MODELVIEW_STACK_DEPTH, @v[0]); glGetIntegerv(GL_PROJECTION_STACK_DEPTH, @v[1]);
  s := s + Format('stack=%d/%d ', [v[0], v[1]]);
  glGetIntegerv(GL_VIEWPORT, @v[0]); s := s + Format('vp=%d,%d,%d,%d ', [v[0], v[1], v[2], v[3]]);
  glGetFloatv(GL_CURRENT_COLOR, @f[0]); s := s + Format('col=%.2f,%.2f,%.2f,%.2f ', [f[0], f[1], f[2], f[3]]);
  glGetFloatv(GL_PROJECTION_MATRIX, @f[0]); s := s + Format('proj=%.4f,%.4f,%.4f,%.4f ', [f[0], f[5], f[10], f[14]]);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, @v[0]); s := s + Format('tex=%d ', [v[0]]);
  glGetIntegerv(GL_ACTIVE_TEXTURE, @v[0]); glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE, @v[1]);
  s := s + Format('active=%x client=%x ', [v[0], v[1]]);
  glGetIntegerv(GL_COLOR_WRITEMASK, @v[0]); s := s + Format('mask=%d%d%d%d ', [v[0], v[1], v[2], v[3]]);
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, @v[0]); s := s + Format('vbo=%d ', [v[0]]);
  glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, @v[0]); s := s + Format('env=%x ', [v[0]]);
  for I := 0 to 3 do
    if glIsEnabled(GL_TEXTURE_COORD_ARRAY) then s := s + 'tcarray ';
  v[0] := 0; v[1] := 0;
  for I := 0 to High(gGFXData[rxGUI]) do
  begin
    if gGFXData[rxGUI, I].Tex.TexID <> 0 then Inc(v[0]);
    if gGFXData[rxGUI, I].PxWidth <> 0 then Inc(v[1]);
  end;
  s := s + Format('gui=%d tex=%d px=%d ', [Length(gGFXData[rxGUI]), v[0], v[1]]);
  if Length(gGFXData[rxGUI]) > 3 then
    with gGFXData[rxGUI, 3] do
      s := s + Format('gui3: tex=%d isTex=%d uv=%.3f,%.3f-%.3f,%.3f px=%dx%d', [Tex.TexID, Ord(glIsTexture(Tex.TexID)), Tex.u1, Tex.v1, Tex.u2, Tex.v2, PxWidth, PxHeight]);
  ALog('GL state: ' + s);
  if gMain <> nil then ALog('FPS: ' + gMain.FPSString);
end;

// Debug aid: report GL errors (at most once per 2 seconds)
var
  fLastDbgRead: QWord;

procedure ReadDbgMask;
var
  sl: TStringList;
begin
  if GetTickCount64 - fLastDbgRead < 2000 then Exit;
  fLastDbgRead := GetTickCount64;
  if not FileExists(ExeDir + 'dbg.txt') then
  begin
    gAndroidDbgMask := 0;
    Exit;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExeDir + 'dbg.txt');
    gAndroidDbgMask := StrToIntDef(Trim(sl.Text), 0);
  finally
    sl.Free;
  end;
end;

// Debug: draw the GUI atlas in a corner to check textured rendering state
procedure DrawTestQuad;
begin
  if gAndroidDbgMask and 64 = 0 then Exit;
  TKMRender.BindTexture(1);
  glColor4f(1, 1, 1, 1);
  glBegin(GL_QUADS);
    glTexCoord2f(0, 0); glVertex2f(300, 600);
    glTexCoord2f(1, 0); glVertex2f(800, 600);
    glTexCoord2f(1, 1); glVertex2f(800, 1100);
    glTexCoord2f(0, 1); glVertex2f(300, 1100);
  glEnd;
  TKMRender.BindTexture(0);
end;

procedure LogGLErrors;
var
  err: GLenum;
  s: string;
begin
  DrawTestQuad;
  ReadDbgMask;
  if GetTickCount64 - fLastGLErrorLog < 2000 then Exit;
  s := '';
  err := glGetError;
  while (err <> GL_NO_ERROR) and (Length(s) < 200) do
  begin
    s := s + IntToHex(err, 4) + ' ';
    err := glGetError;
  end;
  if s <> '' then
  begin
    fLastGLErrorLog := GetTickCount64;
    ALog('GL errors: ' + s);
  end;
  LogGLState;
end;

{$ENDIF}

procedure kam_frame; cdecl;
begin
  if (gMain = nil) or not gMain.Started then Exit;
  try
    CheckSynchronize;
    CheckLongPress;
    if SelfTestActive then
      SelfTestFrame;
    gMain.Frame;
    {$IFDEF ANDROID_GLDEBUG}
    LogGLErrors;
    {$ENDIF}
  except
    on E: Exception do
    begin
      ALog('Exception in frame: ' + E.ClassName + ': ' + E.Message);
      if gLog <> nil then
        gLog.AddTime('Exception: ' + E.Message);
      HostShowMessage('KaM Remake', UnicodeString('Error: ' + E.Message));
    end;
  end;
end;


procedure kam_resize(aWidth, aHeight: Integer); cdecl;
begin
  gHostScreenWidth := aWidth;
  gHostScreenHeight := aHeight;
  if gMain <> nil then
    gMain.SurfaceResized(aWidth, aHeight);
end;


procedure kam_pause; cdecl;
begin
  if gMain <> nil then
    gMain.AppPause;
end;


procedure kam_resume; cdecl;
begin
  if gMain <> nil then
    gMain.AppResume;
end;


procedure kam_shutdown; cdecl;
begin
  if (gMain <> nil) and gMain.Started then
    gMain.Stop(nil);
end;


{ Mouse emulation }

function MousePt(const P: TPointF): TPoint;
begin
  Result := Point(Round(P.X), Round(P.Y));
end;


procedure SendMove(const P: TPointF);
var
  pt: TPoint;
begin
  if gGameApp = nil then Exit;
  pt := MousePt(P);
  gHostCursorPos := pt;
  gGameApp.MouseMove(fButtons, pt.X, pt.Y);
end;


procedure SendDown(aButton: TMouseButton; const P: TPointF);
var
  pt: TPoint;
begin
  if gGameApp = nil then Exit;
  pt := MousePt(P);
  gHostCursorPos := pt;
  case aButton of
    mbLeft:   begin Include(fButtons, ssLeft);   gHostKeyDown[VK_LBUTTON] := True; end;
    mbRight:  begin Include(fButtons, ssRight);  gHostKeyDown[VK_RBUTTON] := True; end;
    mbMiddle: begin Include(fButtons, ssMiddle); gHostKeyDown[VK_MBUTTON] := True; end;
  end;
  // Same as desktop TFormMain: middle button is handled as a key (drag scrolling)
  if aButton = mbMiddle then
    gGameApp.KeyDown(VK_MBUTTON, fButtons, True)
  else
    gGameApp.MouseDown(aButton, fButtons, pt.X, pt.Y);
end;


procedure SendUp(aButton: TMouseButton; const P: TPointF);
var
  pt: TPoint;
  shift: TShiftState;
begin
  if gGameApp = nil then Exit;
  pt := MousePt(P);
  gHostCursorPos := pt;
  // Same as desktop TFormMain: the released button is included in Shift for MouseUp
  // (e.g. message scrolls check ssLeft to tell open from delete)
  shift := fButtons;
  case aButton of
    mbLeft:   begin Include(shift, ssLeft);   Exclude(fButtons, ssLeft);   gHostKeyDown[VK_LBUTTON] := False; end;
    mbRight:  begin Include(shift, ssRight);  Exclude(fButtons, ssRight);  gHostKeyDown[VK_RBUTTON] := False; end;
    mbMiddle: begin Include(shift, ssMiddle); Exclude(fButtons, ssMiddle); gHostKeyDown[VK_MBUTTON] := False; end;
  end;
  if aButton = mbMiddle then
    gGameApp.KeyUp(VK_MBUTTON, shift)
  else
    gGameApp.MouseUp(aButton, shift, pt.X, pt.Y);
end;


function ActiveControls: TKMMasterControl;
begin
  Result := nil;
  if (gGameApp <> nil) and (gGameApp.ActiveInterface <> nil) then
    Result := gGameApp.ActiveInterface.MyControls;
end;


// Interface (gameplay or map editor) whose left toolbar can be scrolled under the point
function ScrollableSidebarAt(const P: TPointF): TObject;
begin
  Result := nil;
  if (gGame = nil) or (gGameApp = nil) then Exit;
  if (gGame.GamePlayInterface <> nil) and (gGameApp.ActiveInterface = gGame.GamePlayInterface)
  and gGame.GamePlayInterface.IsOverScrollableSidebar(Round(P.X), Round(P.Y)) then
    Result := gGame.GamePlayInterface
  else
  if (gGame.MapEditorInterface <> nil) and (gGameApp.ActiveInterface = gGame.MapEditorInterface)
  and gGame.MapEditorInterface.IsOverScrollableSidebar(Round(P.X), Round(P.Y)) then
    Result := gGame.MapEditorInterface;
end;


procedure ScrollSidebarOf(aInterface: TObject; aDelta: Integer);
begin
  if aInterface is TKMGamePlayInterface then
    TKMGamePlayInterface(aInterface).ScrollSidebar(aDelta)
  else
  if aInterface is TKMMapEdInterface then
    TKMMapEdInterface(aInterface).ScrollSidebar(aDelta);
end;


var
  fScrollTarget: TObject;


function GameViewport: TKMViewport;
begin
  Result := nil;
  if (gGameApp <> nil) and (gGameApp.ActiveInterface is TKMUserInterfaceGame) then
    Result := TKMUserInterfaceGame(gGameApp.ActiveInterface).Viewport;
end;


// Is there an UI control under the point (anything that is not the game map)
function IsOverUI(const P: TPointF): Boolean;
var
  ctrls: TKMMasterControl;
  pt: TPoint;
begin
  // Without the game map (menus) everything is UI
  if GameViewport = nil then Exit(True);
  ctrls := ActiveControls;
  if ctrls = nil then Exit(True);
  pt := MousePt(P);
  Result := ctrls.HitControl(pt.X, pt.Y) <> nil;
end;


// Some cursor modes (roads, fields, map editor brushes) are applied by dragging with the left button
function MapToolActive: Boolean;
begin
  Result := (gCursor <> nil) and (gCursor.Mode <> cmNone);
end;


procedure PanViewport(dX, dY: Single);
var
  vp: TKMViewport;
  pos: TKMPointF;
begin
  vp := GameViewport;
  if vp = nil then Exit;
  pos := vp.Position;
  pos.X := pos.X - dX / CellPx(vp);
  pos.Y := pos.Y - dY / CellPx(vp);
  vp.Position := pos;
end;


procedure ZoomViewport(aZoom: Single; const aMid: TPointF);
var
  vp: TKMViewport;
  centerX, centerY: Single;
  mapX, mapY: Single;
  pos: TKMPointF;
begin
  vp := GameViewport;
  if vp = nil then Exit;
  centerX := vp.ViewRect.Left + vp.ViewportClip.X / 2;
  centerY := vp.ViewRect.Top + vp.ViewportClip.Y / 2;
  // Keep the map point under fingers in place
  mapX := vp.Position.X + (aMid.X - centerX) / CellPx(vp);
  mapY := vp.Position.Y + (aMid.Y - centerY) / CellPx(vp);
  vp.Zoom := aZoom;
  pos.X := mapX - (aMid.X - centerX) / CellPx(vp);
  pos.Y := mapY - (aMid.Y - centerY) / CellPx(vp);
  vp.Position := pos;
end;


function Dist(const A, B: TPointF): Single;
begin
  Result := Hypot(A.X - B.X, A.Y - B.Y);
end;


procedure ReleaseButtons(const P: TPointF);
begin
  if ssLeft in fButtons then SendUp(mbLeft, P);
  if ssRight in fButtons then SendUp(mbRight, P);
end;


procedure CheckLongPress;
begin
  if (fTouchState = tsMapPending) and (GetTickCount64 - fDownTime >= LONG_PRESS_MS) then
  begin
    // Right button press, held until finger is lifted (allows to pick troops direction)
    SendMove(fDownPos);
    SendDown(mbRight, fDownPos);
    fTouchState := tsRightHold;
  end;
end;


procedure StartPinch(const P0, P1: TPointF);
var
  vp: TKMViewport;
begin
  vp := GameViewport;
  if vp = nil then
  begin
    fTouchState := tsConsumed;
    Exit;
  end;
  fPinchStartDist := Max(Dist(P0, P1), 1);
  fPinchStartZoom := vp.Zoom;
  fPinchLastMid := MakePointF((P0.X + P1.X) / 2, (P0.Y + P1.Y) / 2);
  fPinchStartTime := GetTickCount64;
  fPinchMoved := False;
  fTouchState := tsPinch;
end;


procedure kam_touch(aAction, aPointerCount: Integer; X0, Y0, X1, Y1: Single); cdecl;
var
  P0, P1, mid: TPointF;
begin
  if (gGameApp = nil) or (gMain = nil) or not gMain.Started then Exit;
  try
    P0 := MakePointF(X0, Y0);
    P1 := MakePointF(X1, Y1);

    case aAction of
      TOUCH_DOWN:
        begin
          fDownPos := P0;
          fLastPos := P0;
          fDownTime := GetTickCount64;
          SendMove(P0);
          if ScrollableSidebarAt(P0) <> nil then
            // Decide on first move: vertical drag scrolls the sidebar, otherwise it is a click/drag
            fTouchState := tsSidebarPending
          else
          if IsOverUI(P0) then
          begin
            SendDown(mbLeft, P0);
            fTouchState := tsUIDrag;
          end
          else
          if MapToolActive then
          begin
            SendDown(mbLeft, P0);
            fTouchState := tsMapDragLeft;
          end
          else
            fTouchState := tsMapPending;
        end;

      TOUCH_POINTER_DOWN:
        if aPointerCount >= 2 then
          case fTouchState of
            tsMapPending, tsMapPan:
              StartPinch(P0, P1);
            tsMapDragLeft:
              begin
                // Second finger cancels the tool drag and lets the map be moved/zoomed
                SendUp(mbLeft, fLastPos);
                StartPinch(P0, P1);
              end;
          end;

      TOUCH_MOVE:
        case fTouchState of
          tsSidebarPending:
            if Dist(P0, fDownPos) > TAP_SLOP then
            begin
              if Abs(P0.Y - fDownPos.Y) >= Abs(P0.X - fDownPos.X) then
              begin
                fTouchState := tsSidebarScroll;
                fScrollTarget := ScrollableSidebarAt(fDownPos);
                ScrollSidebarOf(fScrollTarget, Round(fLastPos.Y - P0.Y));
              end
              else
              begin
                // Horizontal drag (e.g. a slider): press where the finger went down and drag
                SendDown(mbLeft, fDownPos);
                SendMove(P0);
                fTouchState := tsUIDrag;
              end;
              fLastPos := P0;
            end;
          tsSidebarScroll:
            begin
              if (gGame <> nil) and (gGameApp.ActiveInterface = fScrollTarget) then
                ScrollSidebarOf(fScrollTarget, Round(fLastPos.Y - P0.Y));
              fLastPos := P0;
            end;
          tsUIDrag, tsMapDragLeft, tsRightHold:
            begin
              SendMove(P0);
              fLastPos := P0;
            end;
          tsMapPending:
            if Dist(P0, fDownPos) > TAP_SLOP then
            begin
              fTouchState := tsMapPan;
              PanViewport(P0.X - fLastPos.X, P0.Y - fLastPos.Y);
              fLastPos := P0;
            end;
          tsMapPan:
            begin
              PanViewport(P0.X - fLastPos.X, P0.Y - fLastPos.Y);
              fLastPos := P0;
            end;
          tsPinch:
            if aPointerCount >= 2 then
            begin
              mid := MakePointF((P0.X + P1.X) / 2, (P0.Y + P1.Y) / 2);
              if (Abs(Dist(P0, P1) - fPinchStartDist) > TAP_SLOP) or (Dist(mid, fPinchLastMid) > TAP_SLOP) then
                fPinchMoved := True;
              if fPinchMoved then
              begin
                ZoomViewport(fPinchStartZoom * Dist(P0, P1) / fPinchStartDist, mid);
                PanViewport(mid.X - fPinchLastMid.X, mid.Y - fPinchLastMid.Y);
                fPinchLastMid := mid;
              end;
            end;
        end;

      TOUCH_POINTER_UP:
        if fTouchState = tsPinch then
        begin
          // Quick two finger tap without movement = right click
          if not fPinchMoved and (GetTickCount64 - fPinchStartTime < TWO_FINGER_TAP_MS) then
          begin
            SendMove(fDownPos);
            SendDown(mbRight, fDownPos);
            SendUp(mbRight, fDownPos);
          end;
          fTouchState := tsConsumed;
        end;

      TOUCH_UP:
        begin
          case fTouchState of
            tsSidebarPending:
              begin
                // Tap on the sidebar = left click
                SendDown(mbLeft, fDownPos);
                SendUp(mbLeft, fDownPos);
              end;
            tsUIDrag, tsMapDragLeft:
              begin
                SendMove(P0);
                SendUp(mbLeft, P0);
                // Remember taps on text fields: the host shows the soft keyboard only then
                if (ActiveControls <> nil) and (ActiveControls.HitControl(Round(P0.X), Round(P0.Y)) is TKMSelectableEdit) then
                  fTextFieldTapped := True;
              end;
            tsMapPending:
              begin
                // Tap on the map = left click
                SendDown(mbLeft, fDownPos);
                SendUp(mbLeft, fDownPos);
              end;
            tsRightHold:
              begin
                SendMove(P0);
                SendUp(mbRight, P0);
              end;
          end;
          fTouchState := tsIdle;
        end;

      TOUCH_CANCEL:
        begin
          ReleaseButtons(fLastPos);
          fTouchState := tsIdle;
        end;
    end;
  except
    on E: Exception do
      ALog('Exception in touch: ' + E.Message);
  end;
end;


// Physical mouse (USB/Bluetooth) or emulated by the host
procedure kam_mouse(aAction, aButton, X, Y: Integer); cdecl;
var
  btn: TMouseButton;
begin
  if gGameApp = nil then Exit;
  IGNORE_MOUSE_SCROLLING := False;
  case aButton of
    1: btn := mbRight;
    2: btn := mbMiddle;
    else btn := mbLeft;
  end;
  case aAction of
    TOUCH_DOWN: begin SendMove(MakePointF(X, Y)); SendDown(btn, MakePointF(X, Y)); end;
    TOUCH_MOVE: SendMove(MakePointF(X, Y));
    TOUCH_UP:   SendUp(btn, MakePointF(X, Y));
  end;
end;


procedure kam_wheel(aSteps, X, Y: Integer); cdecl;
var
  handled: Boolean;
begin
  if gGameApp = nil then Exit;
  handled := False;
  gGameApp.MouseWheel(fButtons, aSteps, X, Y, handled);
end;


function ShiftFromFlags(aShift: Integer): TShiftState;
begin
  Result := [];
  if aShift and 1 <> 0 then Include(Result, ssShift);
  if aShift and 2 <> 0 then Include(Result, ssCtrl);
  if aShift and 4 <> 0 then Include(Result, ssAlt);
end;


procedure kam_key(aAction, aVirtualKey, aShift: Integer); cdecl;
var
  key: Word;
begin
  if (gGameApp = nil) or (aVirtualKey < 0) or (aVirtualKey > 255) then Exit;
  key := aVirtualKey;
  case aAction of
    KEY_DOWN:
      begin
        gHostKeyDown[key] := True;
        gGameApp.KeyDown(key, ShiftFromFlags(aShift), True);
      end;
    KEY_UP:
      begin
        gHostKeyDown[key] := False;
        gGameApp.KeyUp(key, ShiftFromFlags(aShift));
      end;
  end;
end;


procedure kam_char(aUnicodeChar: Integer); cdecl;
var
  s: AnsiString;
  I: Integer;
begin
  if gGameApp = nil then Exit;
  {$IFDEF UNICODE}
  gGameApp.KeyPress(Char(aUnicodeChar));
  {$ELSE}
  // Non-unicode build: Char is a byte, feed the UTF-8 sequence
  s := UTF8Encode(UnicodeString(WideChar(aUnicodeChar)));
  for I := 1 to Length(s) do
    gGameApp.KeyPress(s[I]);
  {$ENDIF}
end;


procedure kam_back; cdecl;
begin
  kam_key(KEY_DOWN, VK_ESCAPE, 0);
  kam_key(KEY_UP, VK_ESCAPE, 0);
end;


function kam_text_input_active: Integer; cdecl;
var
  ctrls: TKMMasterControl;
begin
  Result := 0;
  ctrls := ActiveControls;
  if (ctrls <> nil) and (ctrls.CtrlFocus is TKMSelectableEdit) then
    Result := 1;
end;


procedure kam_video_finished; cdecl;
begin
  if gVideoPlayer <> nil then
    gVideoPlayer.HostVideoFinished;
end;


// 1 when a game (map with the gameplay sidebar) is shown, 0 in menus. Menus need the full 1024x720 design size
function kam_in_game: Integer; cdecl;
begin
  Result := 0;
  // Only while the game map with its sidebar is on screen (not the loading page or other menu pages)
  if (gGameApp <> nil) and (gGameApp.Game <> nil) and (gGameApp.ActiveInterface is TKMUserInterfaceGame) then
    Result := 1;
  // Mission results and statistics need the menu screen size
  if (Result = 1) and (gGame.GamePlayInterface <> nil)
  and (gGameApp.ActiveInterface = gGame.GamePlayInterface)
  and gGame.GamePlayInterface.IsFullScreenPageVisible then
    Result := 0;
end;


// Bottom edge (render coordinates) of the focused text field, -1 if none. Used to keep it above the soft keyboard
function kam_text_input_bottom: Integer; cdecl;
var
  ctrls: TKMMasterControl;
begin
  Result := -1;
  ctrls := ActiveControls;
  if (ctrls <> nil) and (ctrls.CtrlFocus is TKMSelectableEdit) then
  begin
    Result := ctrls.CtrlFocus.AbsTop + ctrls.CtrlFocus.Height;
    // Field in the scrollable sidebar below the screen edge: scroll the sidebar to show it first
    if (Result > gHostScreenHeight) and (gGame <> nil) and (gGameApp.ActiveInterface is TKMUserInterfaceGame) then
    begin
      ScrollSidebarOf(gGameApp.ActiveInterface, Result - gHostScreenHeight + 4);
      Result := ctrls.CtrlFocus.AbsTop + ctrls.CtrlFocus.Height;
    end;
  end;
end;


// 1 once after the user tapped a text field
function kam_text_field_tapped: Integer; cdecl;
begin
  Result := Ord(fTextFieldTapped);
  fTextFieldTapped := False;
end;


// Starts the content smoke test (see KM_AndroidSelfTest)
procedure kam_selftest(aMode: PAnsiChar); cdecl;
begin
  if (gMain <> nil) and gMain.Started then
    SelfTestStart(string(aMode));
end;


end.
