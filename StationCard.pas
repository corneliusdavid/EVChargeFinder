unit StationCard;

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.StdCtrls, FMX.Layouts, FMX.Forms,
  FMX.Controls.Presentation, FMX.Graphics;

type
  // One charging-station result, populated from the NREL API response.
  TStation = record
    Name: string;
    Address: string;
    ChargerType: string;
    Connectors: string;
    Distance: Double;
    Ports: Integer;
  end;

  // A single row in the "Nearby Stations" list. The visual layout lives in
  // StationCard.fmx (design-time); SetData fills it from a TStation.
  TStationCard = class(TFrame)
    Card: TRectangle;
    PinFill: TPath;
    PinBolt: TPath;
    lblDistance: TLabel;
    Content: TLayout;
    lblName: TLabel;
    lblAddress: TLabel;
    BadgeRow: TLayout;
    Badge: TRectangle;
    lblBadge: TLabel;
    lblPorts: TLabel;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetStation(const S: TStation);
  end;

const
  // Vector path data for the location pin + lightning-bolt cut-out. Assigned
  // in code because TPathData does not round-trip cleanly as text in .fmx.
  PIN_PATH  = 'M22,3 C12.6,3 5,10.6 5,20 C5,31 18,42 22,53 C26,42 39,31 39,20 ' +
              'C39,10.6 31.4,3 22,3 Z';
  BOLT_PATH = 'M24,9 L15,23 L21,23 L20,33 L29,18 L23,18 Z';

implementation

{$R *.fmx}

constructor TStationCard.Create(AOwner: TComponent);
begin
  inherited;
  PinFill.Data.Data := PIN_PATH;
  PinBolt.Data.Data := BOLT_PATH;
end;

procedure TStationCard.SetStation(const S: TStation);
begin
  lblName.Text := S.Name;
  lblAddress.Text := S.Address;
  lblDistance.Text := Format('%.1f mi', [S.Distance]);

  lblBadge.Text := S.ChargerType;
  Badge.Width := 32 + S.ChargerType.Length * 8;

  if S.Ports > 1 then
    lblPorts.Text := Format('%d Ports', [S.Ports])
  else if S.Ports = 1 then
    lblPorts.Text := '1 Port'
  else
    lblPorts.Text := 'Public access';
end;

end.
