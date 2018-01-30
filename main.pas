// TODO app icon

unit main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, Math, DateUtils, StdCtrls, MPlayer, Grids, MMSystem, IniFiles;

type
  TButtonState = (bsIdle, bsWait, bsFire, bsSuccess, bsFalseStart);
  TMainForm = class(TForm)
    tmrCountdown: TTimer;
    lstHistory: TListBox;
    btnReset: TButton;
    pnlStateIndicator: TPanel;
    pnlControls: TPanel;
    grdStats: TStringGrid;
    pnlStats: TPanel;
    procedure tmrCountdownTimer(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure btnResetClick(Sender: TObject);
    procedure pnlStateIndicatorMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure grdStatsDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure FormActivate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    procedure StopCurrentSound();
    procedure PlaySoundResource(ResourceId:String);
    procedure RenderStats();
    procedure ResetForm();
    procedure SetState(NewState:TButtonState);
    function GetStateDescription():String;
    procedure OnUserResponse();
    procedure OnKeyPress(Key: Char);
  public
    { Public declarations }
  end;

const
  cStateMachine: array[TButtonState] of TButtonState = (bsWait, bsFalseStart, bsSuccess, bsIdle, bsIdle);
  cStateColors: array[TButtonState] of TColor = (clWhite, $008CE6F0, $00B48246, $00578B2E, $005C5CCD);
  cStateLabelColors: array[TButtonState] of TColor = (clBlack, clBlack, clWhite, clWhite, clWhite);
  cStateSounds: array[TButtonState] of String = ('', '', 'snd_gong', '', 'snd_fstart');
  cStateInterruptSound: array[TButtonState] of Boolean = (true, true, true, false, false);

var
  MainForm: TMainForm;
  mButtonState: TButtonState;
  mReactionTimeStart: LongWord;
  mReactionTimes: array of Integer;
  mGongSecMin: Double;
  mGongSecMax: Double;

implementation

{$R *.dfm}

procedure QuickSort(var A: array of Integer; iLo, iHi: Integer);
var
  Lo, Hi, Pivot, T: Integer;
begin
  Lo := iLo;
  Hi := iHi;
  Pivot := A[(Lo + Hi) div 2];
  repeat
    while A[Lo] < Pivot do Inc(Lo) ;
    while A[Hi] > Pivot do Dec(Hi) ;
    if Lo <= Hi then
    begin
      T := A[Lo];
      A[Lo] := A[Hi];
      A[Hi] := T;
      Inc(Lo) ;
      Dec(Hi) ;
    end;
  until Lo > Hi;
  if Hi > iLo then QuickSort(A, iLo, Hi) ;
  if Lo < iHi then QuickSort(A, Lo, iHi) ;
end;

function MedianValue(var Values: array of Integer):Integer;
var
  NumValues: Integer;
begin
  NumValues := Length(Values);
  Result := 0;
  if (NumValues > 0) then
  begin
    QuickSort(Values, 0, High(Values));
    if (Odd(NumValues)) then Result := Values[Ceil(NumValues / 2 - 1)]
    else Result := Round((Values[Ceil(NumValues / 2 - 1)] + Values[Ceil(NumValues / 2)]) / 2);
  end;
end;

function SecToMsec(Seconds: Double): Double;
begin
  Result := Seconds * 1000;
end;

function AddMsUnits(Ms: String): String;
begin
  Result := Ms + ' ms';
end;

function FormatTime(Ms: Integer): String;
begin
  Result := AddMsUnits(IntToStr(Ms));
end;

function FormatTimeShort(Ms: Integer):String;
begin
  Result := AddMsUnits(IntToStr(Ms));
  if (Ms >= 1000) then Result := ':(';
end;

procedure TMainForm.StopCurrentSound();
begin
  PlaySound(nil, 0, 0);
end;

procedure TMainForm.PlaySoundResource(ResourceId: String);
begin
  PlaySound(PAnsiChar(ResourceId), HInstance, SND_RESOURCE or SND_ASYNC);
end;

function TMainForm.GetStateDescription(): String;
begin
  if (mButtonState = bsIdle) then Result := 'CLICK HERE (or press space)'
  else if (mButtonState = bsWait) then Result := 'WAIT...'
  else if (mButtonState = bsFire) then Result := 'PRESS THE BUTTON'
  else if (mButtonState = bsSuccess) then Result := lstHistory.Items.Strings[0]
  else if (mButtonState = bsFalseStart) then Result := 'FALSE START';
end;

procedure TMainForm.SetState(NewState: TButtonState);
begin
  mButtonState := NewState;
  pnlStateIndicator.Color := cStateColors[mButtonState];
  pnlStateIndicator.Font.Color := cStateLabelColors[mButtonState];
  pnlStateIndicator.Caption := GetStateDescription();
  if (cStateInterruptSound[mButtonState]) then StopCurrentSound();
  if (cStateSounds[mButtonState] <> '') then PlaySoundResource(cStateSounds[mButtonState]);
end;

procedure TMainForm.RenderStats();
const
  NoSelection: TGridRect = (Left: 0; Top: -1; Right: 0; Bottom: -1);
begin
   grdStats.Selection := NoSelection;
   grdStats.Cells[0, 1] := 'Attempts';
   grdStats.Cells[1, 1] := IntToStr(lstHistory.Items.Count);
   grdStats.Cells[0, 0] := 'Average';
   grdStats.Cells[1, 0] := FormatTime(Round(MedianValue(mReactionTimes)));
end;

procedure TMainForm.ResetForm();
begin
  mReactionTimeStart := 0;
  SetLength(mReactionTimes, 0);

  lstHistory.Left := Round((pnlControls.ClientWidth - lstHistory.Width) / 2);
  btnReset.Left := Round((pnlControls.ClientWidth - btnReset.Width) / 2);

  tmrCountdown.Enabled := False;
  lstHistory.Items.Clear;
  ActiveControl := nil;

  RenderStats();
  SetState(bsIdle);
end;

procedure TMainForm.OnUserResponse();
var
  newState: TButtonState;
  reactionTimeMs: Integer;
  latestTimeString: String;
begin
  newState := cStateMachine[mButtonState];
  if (newState = bsWait) then
  begin
    // TODO exponential (?) distribution
    tmrCountdown.Interval := Round(SecToMsec(Max(mGongSecMin, Random * mGongSecMax)));
    tmrCountdown.Enabled := True;
  end;
  if ((newState = bsSuccess) or (newState = bsFalseStart)) then
  begin
   tmrCountdown.Enabled := False;
   latestTimeString := 'FS';
   if (mReactionTimeStart > 0) then
   begin
    reactionTimeMs := MilliSecondOfTheDay(Now) - mReactionTimeStart;
    SetLength(mReactionTimes, Length(mReactionTimes) + 1);
    mReactionTimes[High(mReactionTimes)] := reactionTimeMs;
    latestTimeString := FormatTime(reactionTimeMs);
   end;
   mReactionTimeStart := 0;
   lstHistory.Items.Insert(0, latestTimeString);
   RenderStats;
  end;
  SetState(cStateMachine[mButtonState]);
end;

procedure TMainForm.OnKeyPress(Key: Char);
begin
 if (Key = ' ') then
 begin
  OnUserResponse();
 end;
end;

procedure TMainForm.pnlStateIndicatorMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  OnUserResponse();
end;

procedure TMainForm.FormKeyPress(Sender: TObject; var Key: Char);
begin
 OnKeyPress(Key);
end;

procedure TMainForm.tmrCountdownTimer(Sender: TObject);
begin
 if (mButtonState = bsWait) then
 begin
  SetState(bsFire);
  mReactionTimeStart := MilliSecondOfTheDay(Now);
 end;
 tmrCountdown.Enabled := False;
end;

procedure TMainForm.btnResetClick(Sender: TObject);
begin
  ResetForm();
end;

procedure TMainForm.FormActivate(Sender: TObject);
var
  formRectangle: TRect;
begin
  ResetForm();
  GetWindowRect(MainForm.Handle, formRectangle);
  SetCursorPos(
    formRectangle.Left + pnlStateIndicator.Left + Round(pnlStateIndicator.Width / 2),
    formRectangle.Top + pnlStateIndicator.Top + Round(pnlStateIndicator.Height / 2));
end;

procedure TMainForm.grdStatsDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
var
  Grid: TStringGrid;
begin
  Grid := Sender as TStringGrid;
  Grid.Canvas.FillRect(Rect);
  DrawText(Grid.Canvas.Handle, PAnsiChar(Grid.Cells[ACol, ARow]), Length(Grid.Cells[ACol, ARow]), Rect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TMainForm.FormCreate(Sender: TObject);
const
  iniSection = 'Settings';
  minSecDefault: Double = 1.1;
  maxSecDefault: Double = 2.9;
var
  minSec, maxSec: Double;
  Config: TIniFile;
begin
  Config := TIniFile.Create(StringReplace(Application.ExeName, '.exe', '.ini', []));
  try
    minSec := Config.ReadFloat(iniSection, 'GongSecMin', minSecDefault);
    maxSec := Config.ReadFloat(iniSection, 'GongSecMax', maxSecDefault);
    if (minSec = minSecDefault) then Config.WriteFloat(iniSection, 'GongSecMin', minSec);
    if (maxSec = maxSecDefault) then Config.WriteFloat(iniSection, 'GongSecMax', maxSec);
  finally
    Config.Free();
  end;

  mGongSecMin := minSec;
  mGongSecMax := maxSec;
end;

end.
