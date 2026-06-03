program EVChargerFinder;

uses
  System.StartUpCopy,
  FMX.Forms,
  MainForm in 'MainForm.pas' {MainFrm},
  StationCard in 'StationCard.pas' {StationCard: TFrame};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainFrm, MainFrm);
  Application.Run;
end.
