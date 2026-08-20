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
    FSkipHwnd: HWND;
  protected
    procedure Execute; override;
  public
    constructor Create(ASkipHwnd: HWND);
    property Events: TRecEventArray read FEvents;
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
  BUTTONS: array[0..2] of Cardinal = (VK_LBUTTON, VK_RBUTTON, VK_MBUTTON);
  BTN_DOWN: array[0..2] of Cardinal = ($02, $08, $20);
  BTN_UP: array[0..2] of Cardinal = ($04, $10, $40);

constructor TRecThread.Create(ASkipHwnd: HWND);
begin
  inherited Create(True);
  FSkipHwnd := ASkipHwnd;
end;

procedure TRecThread.Execute;
var
  pt: TPoint;
  i, n: Integer;
  t: Int64;
  down, prev: array[0..2] of Boolean;
  lastX, lastY: Integer;
begin
  SetLength(FEvents, 0);
  n := 0;
  lastX := -1;
  lastY := -1;
  for i := 0 to 2 do prev[i] := False;
  while not Terminated do
  begin
    t := GetTickCount64;
    GetCursorPos(pt);
    if (pt.X <> lastX) or (pt.Y <> lastY) then
    begin
      if n >= Length(FEvents) then SetLength(FEvents, n + 256);
      FEvents[n].t := t;
      FEvents[n].x := pt.X;
      FEvents[n].y := pt.Y;
      FEvents[n].btn := 0;
      Inc(n);
      lastX := pt.X;
      lastY := pt.Y;
    end;
    if WindowFromPoint(pt) <> FSkipHwnd then
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
          prev[i] := down[i];
        end;
      end;
    Sleep(5);
  end;
  SetLength(FEvents, n);
end;

constructor TPlayThread.Create(AEvents: TRecEventArray);
begin
  inherited Create(True);
  FEvents := AEvents;
end;

procedure TPlayThread.Execute;
var
  startT, base, target: Int64;
  i: Integer;
begin
  startT := GetTickCount64;
  base := FEvents[0].t;
  i := 0;
  while not Terminated and (i < Length(FEvents)) do
  begin
    target := FEvents[i].t - base;
    if target > GetTickCount64 - startT then
      Sleep(target - (GetTickCount64 - startT));
    if FEvents[i].btn = 0 then
      SetCursorPos(FEvents[i].x, FEvents[i].y)
    else
      Mouse_Event(FEvents[i].btn, 0, 0, 0, 0);
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
    lblStatus.Caption := 'Grabando...'
  else if FPlay <> nil then
    lblStatus.Caption := 'Reproduciendo...'
  else if Length(FEvents) > 0 then
    lblStatus.Caption := IntToStr(Length(FEvents)) + ' eventos - ' +
      IntToStr((FEvents[High(FEvents)].t - FEvents[0].t) div 1000) + ' s'
  else
    lblStatus.Caption := 'Listo';
end;

procedure TRecDlg.StopRec;
var
  i: Integer;
begin
  if FRec = nil then Exit;
  FRec.Terminate;
  FRec.WaitFor;
  SetLength(FEvents, Length(FRec.Events));
  for i := 0 to High(FEvents) do FEvents[i] := FRec.Events[i];
  FRec.Free;
  FRec := nil;
end;

procedure TRecDlg.StopPlay;
begin
  if FPlay = nil then Exit;
  FPlay.Terminate;
  FPlay.WaitFor;
  FPlay.Free;
  FPlay := nil;
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
  UpdateStatus;
end;

end.