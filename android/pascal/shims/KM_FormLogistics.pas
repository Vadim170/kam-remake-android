unit KM_FormLogistics;
{$mode delphi}
// Android stub for the desktop logistics debug window (src/forms/KM_FormLogistics).
// FormLogistics is always nil on Android, so the engine never calls into it.
interface

type
  TFormLogistics = class
  public
    procedure VSTUpdate;
    procedure UpdateView(aHandsCnt: Integer; aCheckAll: Boolean);
    function IsEnabled: Boolean;
    procedure Clear;
  end;

var
  FormLogistics: TFormLogistics = nil;

implementation

procedure TFormLogistics.VSTUpdate;
begin
end;

procedure TFormLogistics.UpdateView(aHandsCnt: Integer; aCheckAll: Boolean);
begin
end;

function TFormLogistics.IsEnabled: Boolean;
begin
  Result := False;
end;

procedure TFormLogistics.Clear;
begin
end;

end.
