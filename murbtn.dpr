program murbtn;

{$R 'sounds.res' 'sounds.rc'}

uses
  Forms,
  main in 'main.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'MurBtn';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
