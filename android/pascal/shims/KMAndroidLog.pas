unit KMAndroidLog;
{$mode delphi}
// Logging into Android logcat (tag "KaM")
interface

procedure ALog(const aText: string);

implementation

const
  ANDROID_LOG_INFO = 4;

function __android_log_write(prio: Integer; tag, text: PAnsiChar): Integer; cdecl; external 'log';

procedure ALog(const aText: string);
var
  s: AnsiString;
begin
  s := UTF8Encode(aText);
  __android_log_write(ANDROID_LOG_INFO, 'KaM', PAnsiChar(s));
end;

end.
