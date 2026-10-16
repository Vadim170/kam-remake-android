unit Dialogs;
{$mode delphi}
// Minimal Dialogs replacement for the Android port. Messages are shown by the Android host
interface
uses
  Controls;

type
  TMsgDlgType = (mtWarning, mtError, mtInformation, mtConfirmation, mtCustom);
  TMsgDlgBtn = (mbYes, mbNo, mbOK, mbCancel, mbAbort, mbRetry, mbIgnore, mbAll, mbNoToAll, mbYesToAll, mbHelp, mbClose);
  TMsgDlgButtons = set of TMsgDlgBtn;

procedure ShowMessage(const aMsg: string);
function MessageDlg(const aMsg: string; aDlgType: TMsgDlgType; aButtons: TMsgDlgButtons; aHelpCtx: LongInt): TModalResult; overload;
function MessageDlg(const aCaption, aMsg: string; aDlgType: TMsgDlgType; aButtons: TMsgDlgButtons; aHelpCtx: LongInt): TModalResult; overload;

implementation
uses
  KMAndroidHost, KMAndroidLog;

procedure ShowMessage(const aMsg: string);
begin
  ALog('ShowMessage: ' + aMsg);
  if Assigned(gHostShowMessage) then
    gHostShowMessage('KaM Remake', UnicodeString(aMsg));
end;

function MessageDlg(const aMsg: string; aDlgType: TMsgDlgType; aButtons: TMsgDlgButtons; aHelpCtx: LongInt): TModalResult;
begin
  Result := MessageDlg('KaM Remake', aMsg, aDlgType, aButtons, aHelpCtx);
end;

function MessageDlg(const aCaption, aMsg: string; aDlgType: TMsgDlgType; aButtons: TMsgDlgButtons; aHelpCtx: LongInt): TModalResult;
begin
  ALog('MessageDlg: ' + aMsg);
  if Assigned(gHostShowMessage) then
    gHostShowMessage(UnicodeString(aCaption), UnicodeString(aMsg));
  // Dialogs are non-blocking on Android, so pick the affirmative answer
  if mbYes in aButtons then
    Result := mrYes
  else
    Result := mrOK;
end;

end.
