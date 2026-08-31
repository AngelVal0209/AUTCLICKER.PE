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
  HOTID_HOLD_OFF = 4;
  MOD_NOREPEAT = $4000;
  HOTKEY_INI: array[0..3] of string = ('L', 'R', 'W', 'H');

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
    chkHold: TCheckBox;
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
    procedure OnHoldClick(Sender: TObject);
    procedure OnLiveChange(Sender: TObject);
  public
    hotVK: array[0..3] of Word;
    function SetHotKey(idx: Integer; vk: Word): Boolean;
  private
    FOn: array[0..2] of Boolean;
    FHoldMode: Boolean;
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
    procedure SetHoldMode(AOn: Boolean);
    procedure RegisterAllHotKeys;
    procedure UnregisterAllHotKeys;
    procedure RegisterClickHotKeys;
    procedure UnregisterClickHotKeys;
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

var
  MainForm: TMainForm;

implementation

uses
  unit2, unit3;

{$R *.lfm}

const
  WH_MOUSE_LL = 14;
  LLMHF_INJECTED = $00000001;
  HC_ACTION = 0;

type
  PMSLLHOOKSTRUCT = ^MSLLHOOKSTRUCT;
  MSLLHOOKSTRUCT = packed record
    pt: TPoint;
    mouseData: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: ULONG_PTR;
  end;

var
  hHook: THandle = 0;
  physL, physR: Boolean;

procedure SendClick(flag: DWORD); inline;
var inp: TInput;
begin
  FillChar(inp, SizeOf(inp), 0);
  inp._Type := INPUT_MOUSE;
  inp.mi.dwFlags := flag;
  SendInput(1, @inp, SizeOf(inp));
end;

function LowLevelMouseProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  p: PMSLLHOOKSTRUCT;
begin
  if (nCode = HC_ACTION) then
  begin
    p := PMSLLHOOKSTRUCT(Pointer(PtrUInt(lParam)));
    if (p^.flags and LLMHF_INJECTED) = 0 then
      case wParam of
        WM_LBUTTONDOWN: physL := True;
        WM_LBUTTONUP: physL := False;
        WM_RBUTTONDOWN: physR := True;
        WM_RBUTTONUP: physR := False;
      end;
  end;
  Result := CallNextHookEx(hHook, nCode, wParam, lParam);
end;

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
  hold: Boolean;
begin
  limite := MainForm.FLimite;
  iv := MainForm.FIntMs;
  // ponytail: clamp 10ms evita saturar cola y girotes por 200cps (quitar si necesitas <10ms)
  if iv < 10 then iv := 10;
  ron := MainForm.FRandOn;
  rms := MainForm.FRandMs;
  pick := MainForm.FPick;
  px := MainForm.FPickX;
  py := MainForm.FPickY;
  for i := 0 to 2 do next[i] := 0;
  FCount := 0;
  while not Terminated do
  begin
    hold := MainForm.FHoldMode;
    if hold then
    begin
      // physL/physR via hook LL (INJECTED=0) → suelta=para
      if physL and (GetTickCount64 >= next[0]) then
      begin
        if MainForm.FPick then SetCursorPos(MainForm.FPickX, MainForm.FPickY);
        SendClick($02); SendClick($04);
        Inc(FCount);
        ri := MainForm.FIntMs; if ri < 10 then ri := 10;
        if MainForm.FRandOn then begin ri := ri + Random(2 * MainForm.FRandMs + 1) - MainForm.FRandMs; if ri < 10 then ri := 10; end;
        next[0] := GetTickCount64 + ri;
      end;
      if physR and (GetTickCount64 >= next[1]) then
      begin
        if MainForm.FPick then SetCursorPos(MainForm.FPickX, MainForm.FPickY);
        SendClick($08); SendClick($10);
        Inc(FCount);
        ri := MainForm.FIntMs; if ri < 10 then ri := 10;
        if MainForm.FRandOn then begin ri := ri + Random(2 * MainForm.FRandMs + 1) - MainForm.FRandMs; if ri < 10 then ri := 10; end;
        next[1] := GetTickCount64 + ri;
      end;
      Sleep(1);
      Continue;
    end;
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
        SendClick(d); SendClick(u);
        Inc(FCount);
        ri := iv;
        if ron then
        begin
          ri := iv + Random(2 * rms + 1) - rms;
          if ri < 10 then ri := 10;
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

procedure TMainForm.RegisterAllHotKeys;
var i: Integer;
begin
  for i := 0 to 2 do
    if not RegisterHotKey(Handle, i + 1, MOD_NOREPEAT, hotVK[i]) then
      MessageDlg('No se pudo registrar la hotkey ' + KeyName(hotVK[i]) +
        ', elige otra en Hotkey setting', mtWarning, [mbOK], 0);
  // hold toggle siempre registrado (ej F) para prender/apagar como G
  if not RegisterHotKey(Handle, HOTID_HOLD_OFF, MOD_NOREPEAT, hotVK[3]) then
    MessageDlg('No se pudo registrar hotkey hold ' + KeyName(hotVK[3]), mtWarning, [mbOK], 0);
end;

procedure TMainForm.UnregisterAllHotKeys;
begin
  UnregisterHotKey(Handle, HOTID_L);
  UnregisterHotKey(Handle, HOTID_R);
  UnregisterHotKey(Handle, HOTID_W);
  UnregisterHotKey(Handle, HOTID_HOLD_OFF);
end;

procedure TMainForm.RegisterClickHotKeys;
var i: Integer;
begin
  for i := 0 to 2 do
    if not RegisterHotKey(Handle, i + 1, MOD_NOREPEAT, hotVK[i]) then
      MessageDlg('No se pudo registrar la hotkey ' + KeyName(hotVK[i]) +
        ', elige otra en Hotkey setting', mtWarning, [mbOK], 0);
end;

procedure TMainForm.UnregisterClickHotKeys;
begin
  UnregisterHotKey(Handle, HOTID_L);
  UnregisterHotKey(Handle, HOTID_R);
  UnregisterHotKey(Handle, HOTID_W);
end;

procedure TMainForm.SetHoldMode(AOn: Boolean);
begin
  FHoldMode := AOn;
  if AOn then
  begin
    UnregisterClickHotKeys;
    FOn[0] := False; FOn[1] := False; FOn[2] := False;
    btnHotSet.Enabled := False;
    if IntervalMs < 1 then
    begin
      MessageDlg('El intervalo debe ser mayor a 0 ms', mtWarning, [mbOK], 0);
      FHoldMode := False;
      chkHold.Checked := False;
      RegisterClickHotKeys;
      btnHotSet.Enabled := True;
      UpdateUI;
      Exit;
    end;
    // hook físico para hold continuo (injected no cuenta)
    if hHook <> 0 then UnhookWindowsHookEx(hHook);
    physL := False; physR := False;
    hHook := SetWindowsHookEx(WH_MOUSE_LL, @LowLevelMouseProc, HInstance, 0);
    if hHook = 0 then
      MessageDlg('No se pudo instalar hook de mouse hold', mtWarning, [mbOK], 0);
    if not WorkerAlive then
    begin
      Snapshot;
      worker := TClicThread.Create(False);
      worker.FreeOnTerminate := True;
      worker.OnTerminate := @ThreadDone;
    end;
  end
  else
  begin
    StopWorker;
    if hHook <> 0 then begin UnhookWindowsHookEx(hHook); hHook := 0; end;
    physL := False; physR := False;
    RegisterClickHotKeys;
    btnHotSet.Enabled := True;
  end;
  UpdateUI;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Randomize;
  hotVK[0] := VK_F6;
  hotVK[1] := VK_F7;
  hotVK[2] := VK_F8;
  hotVK[3] := VK_F1;
  LoadConfig;
  timeBeginPeriod(1);
  RegisterAllHotKeys;
  FHoldMode := False;
  // ponytail: live update para hold (suelta para parar, interval en caliente)
  sedH.OnChange := @OnLiveChange;
  sedMin.OnChange := @OnLiveChange;
  sedS.OnChange := @OnLiveChange;
  sedMs.OnChange := @OnLiveChange;
  sedRand.OnChange := @OnLiveChange;
  chkRand.OnChange := @OnLiveChange;
  sedX.OnChange := @OnLiveChange;
  sedY.OnChange := @OnLiveChange;
  UpdateUI;
end;

procedure TMainForm.OnLiveChange(Sender: TObject);
begin
  if FHoldMode then Snapshot;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
var
  i: Integer;
begin
  if worker <> nil then
  begin
    worker.Terminate;
    for i := 1 to 30 do
      if worker.Finished or (WaitForSingleObject(worker.Handle, 100) <> WAIT_TIMEOUT) then Break;
    worker := nil;
  end;
  if hHook <> 0 then begin UnhookWindowsHookEx(hHook); hHook := 0; end;
  UnregisterAllHotKeys;
  timeEndPeriod(1);
  SaveConfig;
end;

procedure TMainForm.Toggle(id: Integer);
begin
  if FHoldMode then Exit;
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
  if FHoldMode then Exit;
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
  // ponytail: muere en <=2ms normalmente; si esta trabado dentro de
  // Mouse_Event (inyeccion bloqueada por la app en primer plano) NO esperamos
  // mas: ThreadDone limpia cuando por fin termine. Nunca colgar la UI.
  if WaitForSingleObject(worker.Handle, 50) = WAIT_OBJECT_0 then
    worker := nil;
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
  if FHoldMode then
  begin
    // cuadradito activado -> hotkeys off, hold poll activo, suelta para parar
    btnStart.Enabled := False;
    btnStop.Enabled := False;
    btnHotSet.Enabled := False;
    chkHold.Enabled := True;
    chkHold.Caption := 'Mantener clic ACTIVO (suelta=para) - ' + KeyName(hotVK[3]);
    lblVKL.Caption := 'Left: mantén pulsado';
    lblVKR.Caption := 'Right: mantén pulsado';
    lblVKW.Caption := 'Middle: ' + KeyName(hotVK[2]) + ' (desactivado)';
    Exit;
  end;
  chkHold.Caption := 'Mantener clic = autoclic (suelta=para) - ' + KeyName(hotVK[3]);
  chkHold.Enabled := True;
  btnHotSet.Enabled := True;
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
  if idx = 3 then
  begin
    if FHoldMode then
    begin
      UnregisterHotKey(Handle, HOTID_HOLD_OFF);
      if RegisterHotKey(Handle, HOTID_HOLD_OFF, MOD_NOREPEAT, vk) then
      begin hotVK[3] := vk; Result := True; end
      else begin RegisterHotKey(Handle, HOTID_HOLD_OFF, MOD_NOREPEAT, hotVK[3]); Result := False; end;
    end else
      hotVK[3] := vk;
    UpdateUI;
    SaveConfig;
    if not FHoldMode then Result := True;
    Exit;
  end;
  if FHoldMode then begin Result := False; Exit; end;
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
  if FHoldMode then
  begin
    MessageDlg('Desactiva "Enable mouse hold" para usar Start/hotkeys', mtInformation, [mbOK], 0);
    Exit;
  end;
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
  if FHoldMode then
  begin
    chkHold.Checked := False;
    Exit;
  end;
  SetAll(False);
end;

procedure TMainForm.OnPosChange(Sender: TObject);
begin
  sedX.Enabled := rbPick.Checked;
  sedY.Enabled := rbPick.Checked;
  if FHoldMode then Snapshot;
end;

procedure TMainForm.OnHoldClick(Sender: TObject);
begin
  // sin confirmación: check = prende, uncheck = apaga, igual que hotkey G
  SetHoldMode(chkHold.Checked);
end;

procedure TMainForm.OnHotSetClick(Sender: TObject);
var
  dlg: THotDlg;
begin
  if FHoldMode then
  begin
    MessageDlg('Desactiva "Enable mouse hold" para editar hotkeys', mtInformation, [mbOK], 0);
    Exit;
  end;
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
  wasHold: Boolean;
begin
  if Message.Msg = WM_HOTKEY then
  begin
    if Cardinal(Message.wParam) = HOTID_HOLD_OFF then
    begin
      // toggle hold como hotkey G: prende si apagado, apaga si prendido, sin confirmar
      wasHold := FHoldMode;
      // evita doble disparo via OnHoldClick
      chkHold.OnClick := nil;
      try
        chkHold.Checked := not wasHold;
      finally
        chkHold.OnClick := @OnHoldClick;
      end;
      SetHoldMode(not wasHold);
      Exit;
    end;
    if FHoldMode then Exit; // en hold, ignora click hotkeys
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
    ini.WriteInteger('Hotkeys', HOTKEY_INI[3], hotVK[3]);
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
    for i := 0 to 3 do
    begin
      k := Word(ini.ReadInteger('Hotkeys', HOTKEY_INI[i], hotVK[i]));
      if k <> 0 then hotVK[i] := k;
    end;
  finally
    ini.Free;
  end;
end;

end.