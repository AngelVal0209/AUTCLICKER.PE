unit unit3;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Windows;

type
  TRecEvent = record
    t: Int64;
    x, y: Integer;
    btn: Cardinal;
  end;

  TRecEventArray = array of TRecEvent;

  TRecThread = class(TThread)
  private
    FEvents: TRecEventArray;
    FCount: Integer;
    FSkipHwnd: HWND;
  protected
    procedure Execute; override;
  public
    constructor Create(ASkipHwnd: HWND);
    property Events: TRecEventArray read FEvents;
    property Count: Integer read FCount;
  end;

  TPlayThread = class(TThread)
  private
    FEvents: TRecEventArray;
  protected
    procedure Execute; override;
  public
    constructor Create(AEvents: TRecEventArray);
  end;

  TRecDlg = class(TForm)
    btnRecord: TButton;
    btnStopRec: TButton;
    btnPlay: TButton;
    btnStopPlay: TButton;
    lblStatus: TLabel;
    tmr: TTimer;
    procedure btnRecordClick(Sender: TObject);
    procedure btnStopRecClick(Sender: TObject);
    procedure btnPlayClick(Sender: TObject);
    procedure btnStopPlayClick(Sender: TObject);
    procedure OnTimer(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FRec: TRecThread;
    FPlay: TPlayThread;
    FEvents: array of TRecEvent;
    procedure StopRec;
    procedure StopPlay;
    procedure UpdateUI;
    procedure UpdateStatus;
  end;

var
  RecDlg: TRecDlg;

implementation

{$R *.lfm}

const
  GA_ROOT = 2;
  BUTTONS: array[0..2] of Cardinal = (VK_LBUTTON, VK_RBUTTON, VK_MBUTTON);
  BTN_DOWN: array[0..2] of Cardinal = ($02, $08, $20);
  BTN_UP: array[0..2] of Cardinal = ($04, $10, $40);

constructor TRecThread.Create(ASkipHwnd: HWND);
begin
  inherited Create(True);
  FSkipHwnd := ASkipHwnd;
  FCount := 0;
end;

procedure TRecThread.Execute;
var
  pt: TPoint;
  hHit: HWND;
  i, n: Integer;
  t: Int64;
  down, prev: array[0..2] of Boolean;
  lastX, lastY: Integer;
begin
  SetLength(FEvents, 0);
  n := 0;
  FCount := 0;
  lastX := -1;
  lastY := -1;
  for i := 0 to 2 do prev[i] := GetAsyncKeyState(BUTTONS[i]) < 0;
  while not Terminated do
  begin
    t := Int64(GetTickCount64);
    GetCursorPos(pt);
    if (pt.X <> lastX) or (pt.Y <> lastY) then
    begin
      if n >= Length(FEvents) then SetLength(FEvents, n + 256);
      FEvents[n].t := t;
      FEvents[n].x := pt.X;
      FEvents[n].y := pt.Y;
      FEvents[n].btn := 0;
      Inc(n);
      FCount := n;
      lastX := pt.X;
      lastY := pt.Y;
    end;
    hHit := WindowFromPoint(pt);
    // Ignora clics sobre cualquier botón/control hijo de este mismo diálogo
    if (hHit <> FSkipHwnd) and (GetAncestor(hHit, GA_ROOT) <> FSkipHwnd) then
      for i := 0 to 2 do
      begin
        down[i] := GetAsyncKeyState(BUTTONS[i]) < 0;
        if down[i] <> prev[i] then
        begin
          if n >= Length(FEvents) then SetLength(FEvents, n + 256);
          FEvents[n].t := t;
          FEvents[n].x := pt.X;
          FEvents[n].y := pt.Y;
          if down[i] then FEvents[n].btn := BTN_DOWN[i] else FEvents[n].btn := BTN_UP[i];
          Inc(n);
          FCount := n;
          prev[i] := down[i];
        end;
      end;
    Sleep(5);
  end;
  SetLength(FEvents, n);
  FCount := n;
end;

constructor TPlayThread.Create(AEvents: TRecEventArray);
begin
  inherited Create(True);
  FEvents := Copy(AEvents);
end;

procedure TPlayThread.Execute;
var
  startT, base, target, rem: Int64;
  i: Integer;
  inp: TInput;
begin
  if Length(FEvents) = 0 then Exit;
  startT := Int64(GetTickCount64);
  base := FEvents[0].t;
  i := 0;
  while not Terminated and (i < Length(FEvents)) do
  begin
    target := FEvents[i].t - base;
    while not Terminated do
    begin
      rem := target - (Int64(GetTickCount64) - startT);
      if rem <= 0 then Break;
      if rem > 15 then Sleep(10) else Sleep(1);
    end;
    if Terminated then Break;
    if FEvents[i].btn = 0 then
      SetCursorPos(FEvents[i].x, FEvents[i].y)
    else
    begin
      SetCursorPos(FEvents[i].x, FEvents[i].y);
      FillChar(inp, SizeOf(inp), 0);
      inp._Type := INPUT_MOUSE;
      inp.mi.dwFlags := FEvents[i].btn;
      SendInput(1, @inp, SizeOf(inp));
    end;
    Inc(i);
  end;
end;

procedure TRecDlg.FormShow(Sender: TObject);
begin
  UpdateUI;
end;

procedure TRecDlg.FormDestroy(Sender: TObject);
begin
  StopRec;
  StopPlay;
end;

procedure TRecDlg.UpdateUI;
begin
  btnRecord.Enabled := (FRec = nil) and (FPlay = nil);
  btnStopRec.Enabled := (FRec <> nil);
  btnPlay.Enabled := (Length(FEvents) > 0) and (FRec = nil) and (FPlay = nil);
  btnStopPlay.Enabled := (FPlay <> nil);
  UpdateStatus;
end;

procedure TRecDlg.UpdateStatus;
begin
  if FRec <> nil then
    lblStatus.Caption := Format('Estado: Grabando... (%d eventos)', [FRec.Count])
  else if FPlay <> nil then
    lblStatus.Caption := 'Estado: Reproduciendo macro...'
  else if Length(FEvents) > 0 then
    lblStatus.Caption := Format('Estado: Listo — %d eventos (%.1f s)',
      [Length(FEvents), (FEvents[High(FEvents)].t - FEvents[0].t) / 1000.0])
  else
    lblStatus.Caption := 'Estado: Listo (sin eventos grabados)';
end;

procedure TRecDlg.StopRec;
begin
  if FRec = nil then Exit;
  FRec.Terminate;
  FRec.WaitFor;
  FEvents := Copy(FRec.Events);
  FreeAndNil(FRec);
end;

procedure TRecDlg.StopPlay;
begin
  if FPlay = nil then Exit;
  FPlay.Terminate;
  FPlay.WaitFor;
  FreeAndNil(FPlay);
end;

procedure TRecDlg.btnRecordClick(Sender: TObject);
begin
  if (FRec <> nil) or (FPlay <> nil) then Exit;
  FRec := TRecThread.Create(Handle);
  FRec.Start;
  UpdateUI;
end;

procedure TRecDlg.btnStopRecClick(Sender: TObject);
begin
  StopRec;
  UpdateUI;
end;

procedure TRecDlg.btnPlayClick(Sender: TObject);
begin
  if (Length(FEvents) = 0) or (FRec <> nil) or (FPlay <> nil) then Exit;
  FPlay := TPlayThread.Create(FEvents);
  FPlay.Start;
  UpdateUI;
end;

procedure TRecDlg.btnStopPlayClick(Sender: TObject);
begin
  StopPlay;
  UpdateUI;
end;

procedure TRecDlg.OnTimer(Sender: TObject);
begin
  if (FPlay <> nil) and FPlay.Finished then
  begin
    StopPlay;
    UpdateUI;
  end
  else
    UpdateStatus;
end;

end.
