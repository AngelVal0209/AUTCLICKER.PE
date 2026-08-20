unit unit2;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, LCLType;

type
  THotDlg = class(TForm)
    btnK0: TButton;
    btnK1: TButton;
    btnK2: TButton;
    btnCerrar: TButton;
    procedure btnKClick(Sender: TObject);
    procedure OnDlgKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
    procedure OnCerrarClick(Sender: TObject);
  private
    listening: Integer;
    procedure UpdateCaptions;
  end;

var
  HotDlg: THotDlg;

implementation

uses
  unit1;

{$R *.lfm}

procedure THotDlg.UpdateCaptions;
const
  names: array[0..2] of string = ('Left', 'Right', 'Middle');
var
  btns: array[0..2] of TButton;
  i: Integer;
begin
  btns[0] := btnK0;
  btns[1] := btnK1;
  btns[2] := btnK2;
  for i := 0 to 2 do
    if listening = i then
      btns[i].Caption := 'Pulsa una tecla...'
    else
      btns[i].Caption := names[i] + ': ' + KeyName(MainForm.hotVK[i]);
end;

procedure THotDlg.FormShow(Sender: TObject);
begin
  listening := -1;
  UpdateCaptions;
end;

procedure THotDlg.btnKClick(Sender: TObject);
begin
  listening := TButton(Sender).Tag;
  UpdateCaptions;
end;

procedure THotDlg.OnDlgKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if listening < 0 then Exit;
  if Key = VK_ESCAPE then
  begin
    listening := -1;
    UpdateCaptions;
  end
  else
  begin
    if MainForm.SetHotKey(listening, Key) then
    begin
      listening := -1;
      UpdateCaptions;
    end
    else
      MessageDlg('Esa tecla ya está asignada o no está disponible', mtWarning, [mbOK], 0);
  end;
  Key := 0;
end;

procedure THotDlg.OnCerrarClick(Sender: TObject);
begin
  Close;
end;

end.