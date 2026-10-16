unit KMAndroidHost;
{$mode delphi}
// State shared between the Android host (JNI glue) and LCL replacement units
interface
uses
  Types;

type
  TKMHostMessageProc = procedure(const aTitle, aText: UnicodeString);
  TKMHostClipboardSet = procedure(const aText: UnicodeString);
  TKMHostClipboardGet = function: UnicodeString;
  TKMHostOpenURL = procedure(const aURL: UnicodeString);
  TKMHostQuit = procedure;
  TKMHostPlayVideo = procedure(const aPath: UnicodeString; aVolume: Integer; aStretch: Boolean);
  TKMHostStopVideo = procedure;

var
  // Pointer position in render area coordinates
  gHostCursorPos: TPoint;
  // Pressed state of virtual keys (Windows VK codes)
  gHostKeyDown: array [0..255] of Boolean;
  gHostScreenWidth: Integer = 1920;
  gHostScreenHeight: Integer = 1080;
  gHostAppActive: Boolean = True;
  // Debug switches read from <data>/dbg.txt (render bisecting on device)
  gAndroidDbgMask: Cardinal = 0;
  // Called right after GL entry points are loaded
  gOnGLInitialized: procedure;



  gHostShowMessage: TKMHostMessageProc;
  gHostClipboardSet: TKMHostClipboardSet;
  gHostClipboardGet: TKMHostClipboardGet;
  gHostOpenURL: TKMHostOpenURL;
  gHostQuit: TKMHostQuit;
  gHostPlayVideo: TKMHostPlayVideo;
  gHostStopVideo: TKMHostStopVideo;



implementation

end.
