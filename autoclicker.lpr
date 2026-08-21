{$APPTYPE GUI}
{$R iconres.o}
program autoclicker;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, unit1;

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
