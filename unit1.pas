unit unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Spin,
  LCLType, Windows, MMSystem, IniFiles;

const
  WM_HOTKEY = $0312;
  WM_WORKER_DONE = $0401;
  HOTID_L = 1;
  HOTID_R = 2;
  HOTID_W = 3;
  HOTID_HOLD_OFF = 4;
  MOD_NOREPEAT = $4000;
  HOTKEY_INI: array[0..3] of string = ('L', 'R', 'W', 'H');

function KeyName(vk: Word): string;
procedure SendClickPair(downFlag, upFlag: DWORD); inline;

type
  TClicThread = class(TThread)
  private
    FCount: Int64;
  protected
    procedure Execute; override;
  end;

  TRawMouseThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TMainForm = class(TForm)
    lblEstado: TLabel;
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
    lblCps: TLabel;
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
    chkHoldR: TCheckBox;
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
    FHoldRight: Boolean;
    worker: TClicThread;
    FRawThread: TRawMouseThread;
    FIntMs, FRandMs, FLimite: Int64;
    FRandOn, FPick: Boolean;
    FPickX, FPickY: Integer;
    function IntervalMs: Int64;
    function ClickCount: Int64;
    procedure Snapshot;
    function WorkerAlive: Boolean;
    procedure StartWorker;
    procedure Toggle(id: Integer);
    procedure SetAll(OnOff: Boolean);
    procedure StopWorker;
    procedure UpdateUI;
    procedure UpdateCpsLabel;
    procedure SaveConfig;
    procedure LoadConfig;
    procedure SetHoldMode(AOn: Boolean);
    function StartRawMouse: Boolean;
    procedure StopRawMouse;
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
  RAW_MOUSE_CLASS = 'AutoClickerRawMouse';
  HWND_MESSAGE = HWND(PtrInt(-3));

var
  physL, physR: Boolean;
  needUpL, needUpR: Boolean;
  pressTickL, pressTickR: QWord;
  gHoldWake: THandle = 0;
  gRawReady: THandle = 0;
  gRawStop: Boolean = False;
  gRawOK: Boolean = False;
  gRawHwnd: HWND = 0;

function RawMouseWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  ri: RAWINPUT;
  sz: UINT;
  flags: USHORT;
begin
  if Msg = WM_INPUT then
  begin
    sz := SizeOf(ri);
    if GetRawInputData(HRAWINPUT(lParam), RID_INPUT, @ri, @sz, SizeOf(RAWINPUTHEADER)) = sz then
      if (ri.header.dwType = RIM_TYPEMOUSE) and (ri.header.hDevice <> 0) then
      begin
        // Ignora paquetes de solo movimiento (99.9%) sin tocar memoria compartida ni eventos
        flags := ri.data.mouse.usButtonFlags and $000F;
        if flags <> 0 then
        begin
          if (flags and RI_MOUSE_LEFT_BUTTON_DOWN) <> 0 then
            if not physL then
            begin
              pressTickL := GetTickCount64;
              needUpL := True;
              physL := True;
              if gHoldWake <> 0 then SetEvent(gHoldWake);
            end;
          if (flags and RI_MOUSE_LEFT_BUTTON_UP) <> 0 then
            if physL then
            begin
              physL := False;
              needUpL := False;
              if gHoldWake <> 0 then SetEvent(gHoldWake);
            end;
          if (flags and RI_MOUSE_RIGHT_BUTTON_DOWN) <> 0 then
            if not physR then
            begin
              pressTickR := GetTickCount64;
              needUpR := True;
              physR := True;
              if MainForm.FHoldRight and (gHoldWake <> 0) then SetEvent(gHoldWake);
            end;
          if (flags and RI_MOUSE_RIGHT_BUTTON_UP) <> 0 then
            if physR then
            begin
              physR := False;
              needUpR := False;
              if MainForm.FHoldRight and (gHoldWake <> 0) then SetEvent(gHoldWake);
            end;
        end;
      end;
    Result := DefWindowProc(hWnd, Msg, wParam, lParam);
    Exit;
  end;
  if Msg = WM_CLOSE then
  begin
    PostQuitMessage(0);
    Result := 0;
    Exit;
  end;
  Result := DefWindowProc(hWnd, Msg, wParam, lParam);
end;

procedure TRawMouseThread.Execute;
var
  wc: TWNDCLASSEX;
  msg: TMsg;
  rid: RAWINPUTDEVICE;
begin
  gRawOK := False;
  gRawHwnd := 0;
  FillChar(wc, SizeOf(wc), 0);
  wc.cbSize := SizeOf(wc);
  wc.lpfnWndProc := @RawMouseWndProc;
  wc.hInstance := HInstance;
  wc.lpszClassName := RAW_MOUSE_CLASS;
  RegisterClassEx(@wc);
  // Ventana message-only (HWND_MESSAGE): no recibe broadcasts ni participa en Z-order
  gRawHwnd := CreateWindowEx(0, RAW_MOUSE_CLASS, nil, 0, 0, 0, 0, 0, HWND_MESSAGE, 0, HInstance, nil);
  if gRawHwnd <> 0 then
  begin
    rid.usUsagePage := 1;
    rid.usUsage := 2;
    rid.dwFlags := RIDEV_INPUTSINK;
    rid.hwndTarget := gRawHwnd;
    gRawOK := RegisterRawInputDevices(@rid, 1, SizeOf(rid));
  end;
  SetEvent(gRawReady);
  if gRawOK and not gRawStop then
    while not gRawStop and GetMessage(msg, 0, 0, 0) do
    begin
      if msg.message = WM_CLOSE then Break;
      DispatchMessage(msg);
      // Drena en lote la cola WM_INPUT para evitar cambios de contexto extra a 1000-8000 Hz
      while not gRawStop and PeekMessage(msg, gRawHwnd, WM_INPUT, WM_INPUT, PM_REMOVE) do
      begin
        if msg.message = WM_QUIT then
        begin
          gRawStop := True;
          Break;
        end;
        DispatchMessage(msg);
      end;
    end;
  if gRawHwnd <> 0 then
  begin
    rid.usUsagePage := 1;
    rid.usUsage := 2;
    rid.dwFlags := RIDEV_REMOVE;
    rid.hwndTarget := 0;
    RegisterRawInputDevices(@rid, 1, SizeOf(rid));
    DestroyWindow(gRawHwnd);
  end;
  gRawHwnd := 0;
  UnregisterClass(RAW_MOUSE_CLASS, HInstance);
end;

// Envía DOWN+UP en una sola syscall atómica: ningún paquete de movimiento se cuela en medio
procedure SendClickPair(downFlag, upFlag: DWORD); inline;
var
  inps: array[0..1] of TInput;
begin
  FillChar(inps, SizeOf(inps), 0);
  inps[0]._Type := INPUT_MOUSE;
  inps[0].mi.dwFlags := downFlag;
  inps[1]._Type := INPUT_MOUSE;
  inps[1].mi.dwFlags := upFlag;
  SendInput(2, @inps[0], SizeOf(TInput));
end;

// En el 1er autoclic tras presionar físicamente, libera el DOWN físico y dispara DOWN+UP atómicamente
procedure SendReleaseAndClickPair(downFlag, upFlag: DWORD); inline;
var
  inps: array[0..2] of TInput;
begin
  FillChar(inps, SizeOf(inps), 0);
  inps[0]._Type := INPUT_MOUSE;
  inps[0].mi.dwFlags := upFlag;
  inps[1]._Type := INPUT_MOUSE;
  inps[1].mi.dwFlags := downFlag;
  inps[2]._Type := INPUT_MOUSE;
  inps[2].mi.dwFlags := upFlag;
  SendInput(3, @inps[0], SizeOf(TInput));
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
    else Result := '0x' + IntToHex(vk, 2);
  end;
end;

function CalcInterval(baseMs, randMs: Int64; randOn: Boolean; minFloor: Int64): Int64; inline;
var
  r: Int64;
begin
  Result := baseMs;
  if Result < minFloor then Result := minFloor;
  if randOn and (randMs > 0) then
  begin
    r := randMs;
    if r > Result div 2 then r := Result div 2;
    if r > 0 then
      Result := Result + Random(2 * r + 1) - r;
    if Result < minFloor then Result := minFloor;
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
  d, u: DWORD;
  limite, iv, rms, ri, wait, nowTick, rem: Int64;
  ron, pick, hold, holdR, wasL, wasR: Boolean;
  px, py: Integer;
begin
  for i := 0 to 2 do next[i] := 0;
  FCount := 0;
  wasL := False;
  wasR := False;
  while not Terminated do
  begin
    limite := MainForm.FLimite;
    if (limite >= 0) and (FCount >= limite) then Break;

    hold := MainForm.FHoldMode;
    iv := MainForm.FIntMs;
    ron := MainForm.FRandOn;
    rms := MainForm.FRandMs;
    pick := MainForm.FPick;
    px := MainForm.FPickX;
    py := MainForm.FPickY;

    if hold then
    begin
      if iv < 10 then iv := 10;
      holdR := MainForm.FHoldRight;
      nowTick := Int64(GetTickCount64);

      // Al iniciar una pulsación física espera 1 intervalo antes de inyectar (respeta clics simples)
      if physL and not wasL then
        next[0] := Int64(pressTickL) + CalcInterval(iv, rms, ron, 10);
      wasL := physL;

      if holdR and physR and not wasR then
        next[1] := Int64(pressTickR) + CalcInterval(iv, rms, ron, 10)
      else if not holdR then
        wasR := False;
      if holdR then wasR := physR;

      if physL and (nowTick >= next[0]) then
      begin
        if pick then SetCursorPos(px, py);
        if needUpL then
        begin
          needUpL := False;
          SendReleaseAndClickPair($02, $04);
        end
        else
          SendClickPair($02, $04);
        Inc(FCount);
        if (limite >= 0) and (FCount >= limite) then Break;
        ri := CalcInterval(iv, rms, ron, 10);
        next[0] := next[0] + ri;
        nowTick := Int64(GetTickCount64);
        if next[0] <= nowTick then next[0] := nowTick + ri;
      end;

      if holdR and physR and (nowTick >= next[1]) then
      begin
        if pick then SetCursorPos(px, py);
        if needUpR then
        begin
          needUpR := False;
          SendReleaseAndClickPair($08, $10);
        end
        else
          SendClickPair($08, $10);
        Inc(FCount);
        if (limite >= 0) and (FCount >= limite) then Break;
        ri := CalcInterval(iv, rms, ron, 10);
        next[1] := next[1] + ri;
        nowTick := Int64(GetTickCount64);
        if next[1] <= nowTick then next[1] := nowTick + ri;
      end;

      wait := 100;
      nowTick := Int64(GetTickCount64);
      if physL then
      begin
        rem := next[0] - nowTick;
        if rem < wait then wait := rem;
      end;
      if holdR and physR then
      begin
        rem := next[1] - nowTick;
        if rem < wait then wait := rem;
      end;
      if wait < 1 then wait := 1;
      if gHoldWake <> 0 then
        WaitForSingleObject(gHoldWake, DWORD(wait))
      else
        Sleep(DWORD(wait));
      Continue;
    end;

    wasL := False;
    wasR := False;
    if iv < 1 then iv := 1;
    nowTick := Int64(GetTickCount64);
    for i := 0 to 2 do
      if MainForm.FOn[i] and (nowTick >= next[i]) then
      begin
        case i of
          0: begin d := $02; u := $04; end;
          1: begin d := $08; u := $10; end;
        else
          begin d := $20; u := $40; end;
        end;
        if pick then SetCursorPos(px, py);
        SendClickPair(d, u);
        Inc(FCount);
        if (limite >= 0) and (FCount >= limite) then Break;
        ri := CalcInterval(iv, rms, ron, 1);
        next[i] := Int64(GetTickCount64) + ri;
      end;

    if (limite >= 0) and (FCount >= limite) then Break;

    wait := 50;
    nowTick := Int64(GetTickCount64);
    for i := 0 to 2 do
      if MainForm.FOn[i] then
      begin
        rem := next[i] - nowTick;
        if rem < wait then wait := rem;
      end;
    if wait < 1 then wait := 1;
    if gHoldWake <> 0 then
      WaitForSingleObject(gHoldWake, DWORD(wait))
    else
      Sleep(DWORD(wait));
  end;

  if not Terminated and (MainForm <> nil) and MainForm.HandleAllocated then
    PostMessage(MainForm.Handle, WM_WORKER_DONE, 0, 0);
end;

function TMainForm.ClickCount: Int64;
begin
  if rbVeces.Checked then Result := sedVeces.Value
  else Result := -1;
end;

procedure TMainForm.Snapshot;
var
  v: Int64;
begin
  v := IntervalMs;
  if FHoldMode then
  begin
    if v >= 10 then FIntMs := v;
  end
  else if v >= 1 then
    FIntMs := v;
  FRandOn := chkRand.Checked;
  FRandMs := sedRand.Value;
  FLimite := ClickCount;
  FPick := rbPick.Checked;
  FPickX := sedX.Value;
  FPickY := sedY.Value;
  FHoldRight := chkHoldR.Checked;
  if gHoldWake <> 0 then SetEvent(gHoldWake);
end;

function TMainForm.WorkerAlive: Boolean;
begin
  Result := (worker <> nil) and not worker.Finished and not worker.Terminated;
end;

procedure TMainForm.StartWorker;
begin
  StopWorker;
  Snapshot;
  worker := TClicThread.Create(False);
end;

procedure TMainForm.StopWorker;
begin
  if worker = nil then Exit;
  worker.Terminate;
  if gHoldWake <> 0 then SetEvent(gHoldWake);
  worker.WaitFor;
  FreeAndNil(worker);
end;

procedure TMainForm.RegisterAllHotKeys;
begin
  RegisterClickHotKeys;
  if not RegisterHotKey(Handle, HOTID_HOLD_OFF, MOD_NOREPEAT, hotVK[3]) then
    MessageDlg('No se pudo registrar la hotkey de Hold (' + KeyName(hotVK[3]) + ')', mtWarning, [mbOK], 0);
end;

procedure TMainForm.UnregisterAllHotKeys;
begin
  UnregisterClickHotKeys;
  UnregisterHotKey(Handle, HOTID_HOLD_OFF);
end;

procedure TMainForm.RegisterClickHotKeys;
var
  i: Integer;
begin
  for i := 0 to 2 do
    if not RegisterHotKey(Handle, i + 1, MOD_NOREPEAT, hotVK[i]) then
      MessageDlg('No se pudo registrar la hotkey ' + KeyName(hotVK[i]) +
        ', elige otra en Configurar Hotkeys', mtWarning, [mbOK], 0);
end;

procedure TMainForm.UnregisterClickHotKeys;
begin
  UnregisterHotKey(Handle, HOTID_L);
  UnregisterHotKey(Handle, HOTID_R);
  UnregisterHotKey(Handle, HOTID_W);
end;

function TMainForm.StartRawMouse: Boolean;
begin
  Result := False;
  if FRawThread <> nil then begin Result := True; Exit; end;
  ResetEvent(gRawReady);
  gRawStop := False;
  gRawOK := False;
  physL := False;
  physR := False;
  needUpL := False;
  needUpR := False;
  FRawThread := TRawMouseThread.Create(False);
  if WaitForSingleObject(gRawReady, 2000) <> WAIT_OBJECT_0 then
  begin
    StopRawMouse;
    Exit;
  end;
  Result := gRawOK;
  if not Result then StopRawMouse;
end;

procedure TMainForm.StopRawMouse;
begin
  if FRawThread = nil then Exit;
  gRawStop := True;
  if gRawHwnd <> 0 then PostMessage(gRawHwnd, WM_CLOSE, 0, 0);
  FRawThread.WaitFor;
  FreeAndNil(FRawThread);
  physL := False;
  physR := False;
  needUpL := False;
  needUpR := False;
end;

procedure TMainForm.SetHoldMode(AOn: Boolean);
begin
  if AOn then
  begin
    if IntervalMs < 10 then
    begin
      MessageDlg('El intervalo debe ser de al menos 10 ms en modo Hold', mtWarning, [mbOK], 0);
      chkHold.OnClick := nil;
      try
        chkHold.Checked := False;
      finally
        chkHold.OnClick := @OnHoldClick;
      end;
      UpdateUI;
      Exit;
    end;
    if not StartRawMouse then
    begin
      MessageDlg('No se pudo activar la detección del botón físico (Raw Input)', mtWarning, [mbOK], 0);
      chkHold.OnClick := nil;
      try
        chkHold.Checked := False;
      finally
        chkHold.OnClick := @OnHoldClick;
      end;
      UpdateUI;
      Exit;
    end;
    FHoldMode := True;
    UnregisterClickHotKeys;
    FOn[0] := False; FOn[1] := False; FOn[2] := False;
    StartWorker;
  end
  else
  begin
    FHoldMode := False;
    StopWorker;
    StopRawMouse;
    RegisterClickHotKeys;
  end;
  UpdateUI;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Randomize;
  gHoldWake := CreateEvent(nil, False, False, nil);
  gRawReady := CreateEvent(nil, True, False, nil);
  hotVK[0] := VK_F6;
  hotVK[1] := VK_F7;
  hotVK[2] := VK_F8;
  hotVK[3] := VK_F1;
  LoadConfig;
  timeBeginPeriod(1);
  RegisterAllHotKeys;
  FHoldMode := False;
  sedH.OnChange := @OnLiveChange;
  sedMin.OnChange := @OnLiveChange;
  sedS.OnChange := @OnLiveChange;
  sedMs.OnChange := @OnLiveChange;
  sedRand.OnChange := @OnLiveChange;
  chkRand.OnChange := @OnLiveChange;
  sedVeces.OnChange := @OnLiveChange;
  sedX.OnChange := @OnLiveChange;
  sedY.OnChange := @OnLiveChange;
  Snapshot;
  UpdateUI;
end;

procedure TMainForm.OnLiveChange(Sender: TObject);
begin
  Snapshot;
  UpdateCpsLabel;
  if FHoldMode then UpdateUI;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  StopWorker;
  StopRawMouse;
  UnregisterAllHotKeys;
  if gHoldWake <> 0 then CloseHandle(gHoldWake);
  if gRawReady <> 0 then CloseHandle(gRawReady);
  timeEndPeriod(1);
  SaveConfig;
end;

procedure TMainForm.Toggle(id: Integer);
begin
  if FHoldMode then Exit;
  if IntervalMs < 1 then Exit;
  FOn[id] := not FOn[id];
  Snapshot;
  if not WorkerAlive and (FOn[0] or FOn[1] or FOn[2]) then
    StartWorker
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
    StartWorker
  else if not OnOff then
    StopWorker;
  UpdateUI;
end;

procedure TMainForm.UpdateCpsLabel;
var
  iv, r, minIv, maxIv, floorMs: Int64;
  cps, minCps, maxCps: Double;
begin
  if FHoldMode then floorMs := 10 else floorMs := 1;
  iv := IntervalMs;
  if iv < floorMs then iv := floorMs;
  if chkRand.Checked and (sedRand.Value > 0) then
  begin
    r := sedRand.Value;
    if r > iv div 2 then r := iv div 2;
    minIv := iv - r;
    if minIv < floorMs then minIv := floorMs;
    maxIv := iv + r;
    minCps := 1000.0 / maxIv;
    maxCps := 1000.0 / minIv;
    lblCps.Caption := Format('Cadencia efectiva: %d–%d ms  |  %.1f – %.1f CPS',
      [minIv, maxIv, minCps, maxCps]);
  end
  else
  begin
    cps := 1000.0 / iv;
    lblCps.Caption := Format('Cadencia efectiva: %d ms  |  %.1f CPS', [iv, cps]);
  end;
end;

procedure TMainForm.UpdateUI;
var
  run: Boolean;
begin
  UpdateCpsLabel;
  run := WorkerAlive;
  if FHoldMode then
  begin
    lblEstado.Caption := 'ESTADO: MODO HOLD ACTIVO — Mantén clic para disparar (' + KeyName(hotVK[3]) + ' desactiva)';
    lblEstado.Font.Color := $00207D1E;
    btnStart.Enabled := False;
    btnStop.Enabled := True;
    btnHotSet.Enabled := False;
    chkHold.Enabled := True;
    chkHold.Caption := 'Mantener clic ACTIVO (suelta = para) — Tecla: ' + KeyName(hotVK[3]);
    lblVKL.Caption := 'Izquierdo: mantén pulsado (activo)';
    if chkHoldR.Checked then
      lblVKR.Caption := 'Derecho: mantén pulsado (activo)'
    else
      lblVKR.Caption := 'Derecho: libre (apuntar / cámara)';
    lblVKW.Caption := 'Central: ' + KeyName(hotVK[2]) + ' (en pausa)';
    Exit;
  end;

  chkHold.Caption := 'Mantener clic = autoclic (suelta para parar) — Tecla: ' + KeyName(hotVK[3]);
  chkHold.Enabled := True;
  btnHotSet.Enabled := not run;
  btnStart.Enabled := not run;
  btnStop.Enabled := run;

  if run then
  begin
    lblEstado.Caption := 'ESTADO: AUTOCLIC EN EJECUCIÓN';
    lblEstado.Font.Color := $00185ADB;
  end
  else
  begin
    lblEstado.Caption := 'ESTADO: EN ESPERA (Listo)';
    lblEstado.Font.Color := $00444444;
  end;

  if run and FOn[0] then
    lblVKL.Caption := 'Izquierdo: ' + KeyName(hotVK[0]) + ' [ACTIVO]'
  else
    lblVKL.Caption := 'Izquierdo: ' + KeyName(hotVK[0]);

  if run and FOn[1] then
    lblVKR.Caption := 'Derecho: ' + KeyName(hotVK[1]) + ' [ACTIVO]'
  else
    lblVKR.Caption := 'Derecho: ' + KeyName(hotVK[1]);

  if run and FOn[2] then
    lblVKW.Caption := 'Central: ' + KeyName(hotVK[2]) + ' [ACTIVO]'
  else
    lblVKW.Caption := 'Central: ' + KeyName(hotVK[2]);
end;

function TMainForm.SetHotKey(idx: Integer; vk: Word): Boolean;
var
  id: Cardinal;
  i: Integer;
begin
  if (idx < 0) or (idx > 3) or FHoldMode then
  begin
    Result := False;
    Exit;
  end;
  // Evita asignar la misma tecla a dos canales distintos
  for i := 0 to 3 do
    if (i <> idx) and (hotVK[i] = vk) then
    begin
      Result := False;
      Exit;
    end;

  if idx = 3 then id := HOTID_HOLD_OFF else id := idx + 1;
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
var
  vx, vy, vw, vh: Integer;
begin
  if FHoldMode then
  begin
    MessageDlg('Desactiva el modo Hold para usar Iniciar/Hotkeys normales', mtInformation, [mbOK], 0);
    Exit;
  end;
  if WorkerAlive then Exit;
  if IntervalMs < 1 then
  begin
    MessageDlg('El intervalo debe ser mayor a 0 ms', mtWarning, [mbOK], 0);
    Exit;
  end;
  if rbPick.Checked then
  begin
    vx := GetSystemMetrics(76); // SM_XVIRTUALSCREEN
    vy := GetSystemMetrics(77); // SM_YVIRTUALSCREEN
    vw := GetSystemMetrics(78); // SM_CXVIRTUALSCREEN
    vh := GetSystemMetrics(79); // SM_CYVIRTUALSCREEN
    if vw <= 0 then vw := GetSystemMetrics(0);
    if vh <= 0 then vh := GetSystemMetrics(1);
    if (sedX.Value < vx) or (sedY.Value < vy) or
       (sedX.Value >= vx + vw) or (sedY.Value >= vy + vh) then
    begin
      MessageDlg('Coordenadas fuera de la pantalla', mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  FOn[0] := True;
  StartWorker;
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
  Snapshot;
end;

procedure TMainForm.OnHoldClick(Sender: TObject);
begin
  SetHoldMode(chkHold.Checked);
end;

procedure TMainForm.OnHotSetClick(Sender: TObject);
var
  dlg: THotDlg;
begin
  if FHoldMode then
  begin
    MessageDlg('Desactiva el modo Hold para editar las hotkeys', mtInformation, [mbOK], 0);
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
  if Message.Msg = WM_WORKER_DONE then
  begin
    FOn[0] := False;
    FOn[1] := False;
    FOn[2] := False;
    if FHoldMode then
    begin
      chkHold.OnClick := nil;
      try
        chkHold.Checked := False;
      finally
        chkHold.OnClick := @OnHoldClick;
      end;
      SetHoldMode(False);
    end
    else
    begin
      StopWorker;
      UpdateUI;
    end;
    Message.Result := 0;
    Exit;
  end;

  if Message.Msg = WM_HOTKEY then
  begin
    if Cardinal(Message.wParam) = HOTID_HOLD_OFF then
    begin
      wasHold := FHoldMode;
      chkHold.OnClick := nil;
      try
        chkHold.Checked := not wasHold;
      finally
        chkHold.OnClick := @OnHoldClick;
      end;
      SetHoldMode(not wasHold);
      Exit;
    end;
    if FHoldMode then Exit;
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
    ini.WriteBool('Hold', 'RightClick', chkHoldR.Checked);
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
  i, cnt: Integer;
begin
  ini := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
  try
    sedH.Value := ini.ReadInteger('Interval', 'H', 0);
    sedMin.Value := ini.ReadInteger('Interval', 'Min', 0);
    sedS.Value := ini.ReadInteger('Interval', 'S', 0);
    sedMs.Value := ini.ReadInteger('Interval', 'Ms', 60);
    chkRand.Checked := ini.ReadBool('Interval', 'Rand', False);
    sedRand.Value := ini.ReadInteger('Interval', 'RandMs', 40);
    rbVeces.Checked := ini.ReadBool('Repeat', 'Veces', False);
    rbHasta.Checked := not rbVeces.Checked;
    cnt := ini.ReadInteger('Repeat', 'Count', 1);
    if cnt < 1 then cnt := 1;
    sedVeces.Value := cnt;
    rbPick.Checked := ini.ReadInteger('Cursor', 'Mode', 0) <> 0;
    rbCur.Checked := not rbPick.Checked;
    sedX.Value := ini.ReadInteger('Cursor', 'X', 0);
    sedY.Value := ini.ReadInteger('Cursor', 'Y', 0);
    sedX.Enabled := rbPick.Checked;
    sedY.Enabled := rbPick.Checked;
    chkHoldR.Checked := ini.ReadBool('Hold', 'RightClick', True);
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
