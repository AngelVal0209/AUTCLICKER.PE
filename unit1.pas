unit unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Spin,
  LCLType, Windows, MMSystem, IniFiles;

const
  WM_HOTKEY = $0312;
  HOTID_L = 1;
  HOTID_R = 2;
  HOTID_W = 3;
  MOD_NOREPEAT = $4000;
  HOTKEY_INI: array[0..2] of string = ('L', 'R', 'W');

function KeyName(vk: Word): string;

type
  TClicThread = class(TThread)
  private
    FCount: Int64;
  protected
    procedure Execute; override;
  end;

  TMainForm = class(TForm)
    gbInterval: TGroupBox;
    sedH: TSpinEdit;
    lblH: TLabel;
    sedMin: TSpinEdit;
    lblMin: TLabel;
    sedS: TSpinEdit;
    lblS: TLabel;
    sedMs: TSpinEdit;
    lblMs: TLabel;
    chkRand: TCheckBox;
    sedRand: TSpinEdit;
    lblRandMs: TLabel;
    gbRepeat: TGroupBox;
    rbVeces: TRadioButton;
    sedVeces: TSpinEdit;
    lblVeces: TLabel;
    rbHasta: TRadioButton;
    gbCursor: TGroupBox;
    rbCur: TRadioButton;
    rbPick: TRadioButton;
    lblX: TLabel;
    sedX: TSpinEdit;
    lblY: TLabel;
    sedY: TSpinEdit;
    gbHot: TGroupBox;
    lblVKL: TLabel;
    lblVKR: TLabel;
    lblVKW: TLabel;
    btnHotSet: TButton;
    btnStart: TButton;
    btnStop: TButton;
    btnRec: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure OnStartClick(Sender: TObject);
    procedure OnStopClick(Sender: TObject);
    procedure OnHotSetClick(Sender: TObject);
    procedure OnRecClick(Sender: TObject);
    procedure OnPosChange(Sender: TObject);
  public
    hotVK: array[0..2] of Word;
    function SetHotKey(idx: Integer; vk: Word): Boolean;
  private
    FOn: array[0..2] of Boolean;
    worker: TClicThread;
    FIntMs, FRandMs, FLimite: Int64;
    FRandOn, FPick: Boolean;
    FPickX, FPickY: Integer;
    function IntervalMs: Int64;
    function ClickCount: Int64;
    procedure Snapshot;
    function WorkerAlive: Boolean;
    procedure Toggle(id: Integer);
    procedure SetAll(OnOff: Boolean);
    procedure StopWorker;
    procedure ThreadDone(Sender: TObject);
    procedure UpdateUI;
    procedure SaveConfig;
    procedure LoadConfig;
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

var
  MainForm: TMainForm;

implementation

uses
  unit2, unit3;

{$R *.lfm}

function KeyName(vk: Word): string;
begin
  case vk of
    VK_ESCAPE: Result := 'Esc';
    VK_SPACE: Result := 'Espacio';
    VK_RETURN: Result := 'Enter';
    VK_TAB: Result := 'Tab';
    VK_F1..VK_F12: Result := 'F' + IntToStr(vk - VK_F1 + 1);
  else
    if (vk >= Ord('A')) and (vk <= Ord('Z')) then Result := Chr(vk)
    else if (vk >= Ord('0')) and (vk <= Ord('9')) then Result := Chr(vk)
    else Result := IntToHex(vk, 2);
  end;
end;

function TMainForm.IntervalMs: Int64;
begin
  Result := Int64(sedH.Value) * 3600000 + Int64(sedMin.Value) * 60000
          + Int64(sedS.Value) * 1000 + Int64(sedMs.Value);
end;

procedure TClicThread.Execute;
var
  next: array[0..2] of Int64;
  i: Integer;
  d, u: Cardinal;
  limite, iv, ri, rms: Int64;
  ron, pick: Boolean;
  px, py: Integer;
begin
  limite := MainForm.FLimite;
  iv := MainForm.FIntMs;
  ron := MainForm.FRandOn;
  rms := MainForm.FRandMs;
  pick := MainForm.FPick;
  px := MainForm.FPickX;
  py := MainForm.FPickY;
  for i := 0 to 2 do next[i] := 0;
  FCount := 0;
  while not Terminated do
  begin
    if (limite >= 0) and (FCount >= limite) then Break;
    for i := 0 to 2 do
      if MainForm.FOn[i] and (GetTickCount64 >= next[i]) then
      begin
        case i of
          0: begin d := $02; u := $04; end;
          1: begin d := $08; u := $10; end;
        else
          begin d := $20; u := $40; end;
        end;
        if pick then
          SetCursorPos(px, py);
        Mouse_Event(d, 0, 0, 0, 0);
        Mouse_Event(u, 0, 0, 0, 0);
        Inc(FCount);
        ri := iv;
        if ron then
        begin
          ri := iv + Random(2 * rms + 1) - rms;
          if ri < 1 then ri := 1;
        end;
        next[i] := GetTickCount64 + ri;
      end;
    Sleep(1);
  end;
end;

function TMainForm.ClickCount: Int64;
begin
  if rbVeces.Checked then Result := sedVeces.Value
  else Result := -1;
end;

procedure TMainForm.Snapshot;
begin
  FIntMs := IntervalMs;
  FRandOn := chkRand.Checked;
  FRandMs := sedRand.Value;
  FLimite := ClickCount;
  FPick := rbPick.Checked;
  FPickX := sedX.Value;
  FPickY := sedY.Value;
end;

function TMainForm.WorkerAlive: Boolean;
begin
  Result := (worker <> nil) and not worker.Finished;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  Randomize;
  hotVK[0] := VK_F6;
  hotVK[1] := VK_F7;
  hotVK[2] := VK_F8;
  LoadConfig;
  timeBeginPeriod(1);
  for i := 0 to 2 do
    if not RegisterHotKey(Handle, i + 1, MOD_NOREPEAT, hotVK[i]) then
      MessageDlg('No se pudo registrar la hotkey ' + KeyName(hotVK[i]) +
        ', elige otra en Hotkey setting', mtWarning, [mbOK], 0);
  UpdateUI;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  StopWorker;
  UnregisterHotKey(Handle, HOTID_L);
  UnregisterHotKey(Handle, HOTID_R);
  UnregisterHotKey(Handle, HOTID_W);
  timeEndPeriod(1);
  SaveConfig;
end;

procedure TMainForm.Toggle(id: Integer);
begin
  if IntervalMs < 1 then Exit;
  FOn[id] := not FOn[id];
  if not WorkerAlive and (FOn[0] or FOn[1] or FOn[2]) then
  begin
    Snapshot;
    worker := TClicThread.Create(False);
    worker.FreeOnTerminate := True;
    worker.OnTerminate := @ThreadDone;
  end
  else if not (FOn[0] or FOn[1] or FOn[2]) then
    StopWorker;
  UpdateUI;
end;

procedure TMainForm.SetAll(OnOff: Boolean);
begin
  FOn[0] := OnOff;
  FOn[1] := OnOff;
  FOn[2] := OnOff;
  if OnOff and not WorkerAlive then
  begin
    Snapshot;
    worker := TClicThread.Create(False);
    worker.FreeOnTerminate := True;
    worker.OnTerminate := @ThreadDone;
  end
  else if not OnOff then
    StopWorker;
  UpdateUI;
end;

procedure TMainForm.StopWorker;
begin
  if worker = nil then Exit;
  worker.Terminate;
  worker.WaitFor;
  worker := nil;
  UpdateUI;
end;

procedure TMainForm.ThreadDone(Sender: TObject);
begin
  if worker = Sender then worker := nil;
  UpdateUI;
end;

procedure TMainForm.UpdateUI;
var
  run: Boolean;
begin
  run := WorkerAlive;
  btnStart.Enabled := not run;
  btnStop.Enabled := run;
  if run and FOn[0] then
    lblVKL.Caption := 'Left: ' + KeyName(hotVK[0]) + ' (activo)'
  else
    lblVKL.Caption := 'Left: ' + KeyName(hotVK[0]);
  if run and FOn[1] then
    lblVKR.Caption := 'Right: ' + KeyName(hotVK[1]) + ' (activo)'
  else
    lblVKR.Caption := 'Right: ' + KeyName(hotVK[1]);
  if run and FOn[2] then
    lblVKW.Caption := 'Middle: ' + KeyName(hotVK[2]) + ' (activo)'
  else
    lblVKW.Caption := 'Middle: ' + KeyName(hotVK[2]);
end;

function TMainForm.SetHotKey(idx: Integer; vk: Word): Boolean;
var
  id: Cardinal;
begin
  id := idx + 1;
  UnregisterHotKey(Handle, id);
  if RegisterHotKey(Handle, id, MOD_NOREPEAT, vk) then
  begin
    hotVK[idx] := vk;
    Result := True;
  end
  else
  begin
    RegisterHotKey(Handle, id, MOD_NOREPEAT, hotVK[idx]);
    Result := False;
  end;
  UpdateUI;
  SaveConfig;
end;

procedure TMainForm.OnStartClick(Sender: TObject);
begin
  if WorkerAlive then Exit;
  if IntervalMs < 1 then
  begin
    MessageDlg('El intervalo debe ser mayor a 0 ms', mtWarning, [mbOK], 0);
    Exit;
  end;
  if rbPick.Checked and ((sedX.Value < 0) or (sedY.Value < 0) or
     (sedX.Value >= GetSystemMetrics(0)) or (sedY.Value >= GetSystemMetrics(1))) then
  begin
    MessageDlg('Coordenadas fuera de la pantalla', mtWarning, [mbOK], 0);
    Exit;
  end;
  FOn[0] := True;
  Snapshot;
  worker := TClicThread.Create(False);
  worker.FreeOnTerminate := True;
  worker.OnTerminate := @ThreadDone;
  UpdateUI;
end;

procedure TMainForm.OnStopClick(Sender: TObject);
begin
  SetAll(False);
end;

procedure TMainForm.OnPosChange(Sender: TObject);
begin
  sedX.Enabled := rbPick.Checked;
  sedY.Enabled := rbPick.Checked;
end;

procedure TMainForm.OnHotSetClick(Sender: TObject);
var
  dlg: THotDlg;
begin
  dlg := THotDlg.Create(nil);
  try
    dlg.ShowModal;
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.OnRecClick(Sender: TObject);
var
  dlg: TRecDlg;
begin
  dlg := TRecDlg.Create(nil);
  try
    dlg.ShowModal;
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.WndProc(var Message: TMessage);
var
  id: Integer;
begin
  if Message.Msg = WM_HOTKEY then
  begin
    id := Cardinal(Message.wParam) - 1;
    if (id >= 0) and (id <= 2) then Toggle(id)
    else inherited WndProc(Message);
  end
  else
    inherited WndProc(Message);
end;

procedure TMainForm.SaveConfig;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
  try
    ini.WriteInteger('Interval', 'H', sedH.Value);
    ini.WriteInteger('Interval', 'Min', sedMin.Value);
    ini.WriteInteger('Interval', 'S', sedS.Value);
    ini.WriteInteger('Interval', 'Ms', sedMs.Value);
    ini.WriteBool('Interval', 'Rand', chkRand.Checked);
    ini.WriteInteger('Interval', 'RandMs', sedRand.Value);
    ini.WriteBool('Repeat', 'Veces', rbVeces.Checked);
    ini.WriteInteger('Repeat', 'Count', sedVeces.Value);
    ini.WriteInteger('Cursor', 'Mode', Ord(rbPick.Checked));
    ini.WriteInteger('Cursor', 'X', sedX.Value);
    ini.WriteInteger('Cursor', 'Y', sedY.Value);
    ini.WriteInteger('Hotkeys', HOTKEY_INI[0], hotVK[0]);
    ini.WriteInteger('Hotkeys', HOTKEY_INI[1], hotVK[1]);
    ini.WriteInteger('Hotkeys', HOTKEY_INI[2], hotVK[2]);
  finally
    ini.Free;
  end;
end;

procedure TMainForm.LoadConfig;
var
  ini: TIniFile;
  k: Word;
  i: Integer;
begin
  ini := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
  try
    sedH.Value := ini.ReadInteger('Interval', 'H', 0);
    sedMin.Value := ini.ReadInteger('Interval', 'Min', 0);
    sedS.Value := ini.ReadInteger('Interval', 'S', 0);
    sedMs.Value := ini.ReadInteger('Interval', 'Ms', 100);
    chkRand.Checked := ini.ReadBool('Interval', 'Rand', False);
    sedRand.Value := ini.ReadInteger('Interval', 'RandMs', 40);
    rbVeces.Checked := ini.ReadBool('Repeat', 'Veces', False);
    sedVeces.Value := ini.ReadInteger('Repeat', 'Count', 1);
    rbPick.Checked := ini.ReadInteger('Cursor', 'Mode', 0) <> 0;
    sedX.Value := ini.ReadInteger('Cursor', 'X', 0);
    sedY.Value := ini.ReadInteger('Cursor', 'Y', 0);
    for i := 0 to 2 do
    begin
      k := Word(ini.ReadInteger('Hotkeys', HOTKEY_INI[i], hotVK[i]));
      if k <> 0 then hotVK[i] := k;
    end;
  finally
    ini.Free;
  end;
end;

end.