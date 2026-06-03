unit MainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.JSON,
  System.Math, System.Generics.Collections, System.Net.HttpClient,
  System.Net.URLClient, System.NetEncoding, System.Threading,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts,
  FMX.Objects, FMX.StdCtrls, FMX.Edit, FMX.Controls.Presentation,
  StationCard;

type
  TMainFrm = class(TForm)
    LeftPanel: TRectangle;
    Divider: TRectangle;
    CarIcon: TPath;
    TitleLabel: TLabel;
    SubtitleLabel: TLabel;
    ZipLabel: TLabel;
    InputBox: TRectangle;
    ZipEdit: TEdit;
    SearchBtn: TRectangle;
    SearchIcon: TPath;
    SearchLabel: TLabel;
    Illustration: TPath;
    StatusLabel: TLabel;
    RightPanel: TLayout;
    HeaderLabel: TLabel;
    StationsBox: TVertScrollBox;
    procedure FormCreate(Sender: TObject);
    procedure ZipEditApplyStyleLookup(Sender: TObject);
    procedure ZipEditKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
    procedure SearchClick(Sender: TObject);
    procedure SearchMouseEnter(Sender: TObject);
    procedure SearchMouseLeave(Sender: TObject);
  private
    FBusy: Boolean;
    procedure DoSearch;
    procedure SearchZip(const Zip: string);
    procedure ClearStations;
    procedure ShowInfo(const AText: string);
    procedure PopulateStations(const Stations: TArray<TStation>);
  end;

var
  MainFrm: TMainFrm;

implementation

{$R *.fmx}

const
  // --- Free APIs ---------------------------------------------------------
  // ZIP -> coordinates : Zippopotam.us  (no key, https://api.zippopotam.us)
  // Charging stations  : Open Charge Map (https://api.openchargemap.io)
  //
  // The Open Charge Map key (OCM_KEY) is kept out of source control. On a
  // fresh checkout, copy ApiKeys.inc.template to ApiKeys.inc and paste your
  // free key there (see that file for instructions). ApiKeys.inc is listed in
  // .gitignore. OCM also works without a key for light use (leave it as '').
  {$I ApiKeys.inc}

  // Optional proxy. THTTPClient uses WinHTTP, which ignores the browser/IE
  // proxy. If you are on a network where the browser works but this app gets
  // "(12007) server name could not be resolved", put your proxy here (find it
  // in Windows Settings > Network > Proxy, or your IT team). Leave blank
  // otherwise. Example: PROXY_HOST = 'proxy.company.com'; PROXY_PORT = 8080;
  PROXY_HOST = '';
  PROXY_PORT = 8080;

  CLR_GREEN_SOFT = TAlphaColor($1A8BE04B);
  CLR_GREEN_NONE = TAlphaColor($008BE04B);
  CLR_GRAY       = TAlphaColor($FF9AA0A6);

  // Decorative vector icons drawn with TPath (assigned in code; TPathData
  // does not round-trip cleanly through .fmx text).
  MAG_PATH = 'M15,15 L21,21 M9,2.5 C5.4,2.5 2.5,5.4 2.5,9 C2.5,12.6 5.4,15.5 ' +
             '9,15.5 C12.6,15.5 15.5,12.6 15.5,9 C15.5,5.4 12.6,2.5 9,2.5 Z';
  CAR_PATH = 'M12,49 L24,49 C27,33 34,27 47,27 L74,27 C87,27 96,34 103,49 ' +
             'L113,49 M33,53 a8,8 0 1,0 16,0 a8,8 0 1,0 -16,0 ' +
             'M82,53 a8,8 0 1,0 16,0 a8,8 0 1,0 -16,0 ' +
             'M113,40 L122,40 M113,58 L122,58 M122,36 L122,62';
  STN_PATH = 'M30,42 L88,42 L88,150 L30,150 Z ' +
             'M44,57 L74,57 L74,86 L44,86 Z ' +
             'M62,61 L54,75 L60,75 L58,83 L68,69 L62,69 Z ' +
             'M18,150 L100,150 ' +
             'M88,98 C104,98 104,118 92,120 ' +
             'M150,150 L160,150 C163,121 176,113 200,113 ' +
             'L250,113 C268,113 280,121 288,150 L298,150 ' +
             'M175,154 a11,11 0 1,0 22,0 a11,11 0 1,0 -22,0 ' +
             'M250,154 a11,11 0 1,0 22,0 a11,11 0 1,0 -22,0 ' +
             'M132,168 L300,168';

// ---------------------------------------------------------------------------
//  JSON helpers (APIs return null / mixed types for many fields)
// ---------------------------------------------------------------------------
function JStr(Obj: TJSONObject; const Name: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  V := Obj.GetValue(Name);
  if (V <> nil) and not (V is TJSONNull) then
    Result := V.Value;
end;

function JInt(Obj: TJSONObject; const Name: string): Integer;
var
  V: TJSONValue;
begin
  Result := 0;
  V := Obj.GetValue(Name);
  if (V <> nil) and not (V is TJSONNull) then
    Result := StrToIntDef(V.Value, 0);
end;

function JFloat(Obj: TJSONObject; const Name: string): Double;
var
  V: TJSONValue;
  F: Double;
begin
  Result := 0;
  V := Obj.GetValue(Name);
  if (V <> nil) and not (V is TJSONNull) then
    if TryStrToFloat(V.Value, F, TFormatSettings.Invariant) then
      Result := F;
end;

// Parse an Open Charge Map POI array (the response is a top-level JSON array).
function ParseOCM(Arr: TJSONArray): TArray<TStation>;
var
  V, C: TJSONValue;
  Poi, Addr, Conn, CType: TJSONObject;
  ConnArr: TJSONArray;
  S: TStation;
  List: TList<TStation>;
  Parts: TArray<string>;
  P, CTitle: string;
  MaxKW: Double;
  Qty, Pts: Integer;

  procedure AddConnector(const ATitle: string);
  begin
    if ATitle = '' then Exit;
    if Pos(ATitle, S.Connectors) > 0 then Exit; // de-dupe
    if S.Connectors <> '' then S.Connectors := S.Connectors + ', ';
    S.Connectors := S.Connectors + ATitle;
  end;

begin
  List := TList<TStation>.Create;
  try
    for V in Arr do
    begin
      if not (V is TJSONObject) then Continue;
      Poi := TJSONObject(V);

      if not Poi.TryGetValue<TJSONObject>('AddressInfo', Addr) then Continue;

      S.Name := JStr(Addr, 'Title');

      Parts := [];
      P := JStr(Addr, 'AddressLine1');
      if P <> '' then Parts := Parts + [P];
      P := JStr(Addr, 'Town');
      if P <> '' then Parts := Parts + [P];
      P := Trim(JStr(Addr, 'StateOrProvince') + ' ' + JStr(Addr, 'Postcode'));
      if P <> '' then Parts := Parts + [P];
      S.Address := string.Join(', ', Parts);

      S.Distance := JFloat(Addr, 'Distance');

      // Classify charger type and tally ports / connectors from Connections.
      MaxKW := 0;
      Qty := 0;
      S.Connectors := '';
      if Poi.TryGetValue<TJSONArray>('Connections', ConnArr) then
        for C in ConnArr do
        begin
          if not (C is TJSONObject) then Continue;
          Conn := TJSONObject(C);
          if JFloat(Conn, 'PowerKW') > MaxKW then
            MaxKW := JFloat(Conn, 'PowerKW');
          Qty := Qty + Max(1, JInt(Conn, 'Quantity'));
          if Conn.TryGetValue<TJSONObject>('ConnectionType', CType) then
          begin
            CTitle := JStr(CType, 'Title');
            AddConnector(CTitle);
          end;
        end;

      if MaxKW >= 50 then
        S.ChargerType := 'DC Fast'
      else if MaxKW >= 7 then
        S.ChargerType := 'Level 2'
      else if MaxKW > 0 then
        S.ChargerType := 'Level 1'
      else
        S.ChargerType := 'EV';

      Pts := JInt(Poi, 'NumberOfPoints');
      if Pts > 0 then
        S.Ports := Pts
      else
        S.Ports := Qty;

      if S.Name <> '' then
        List.Add(S);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Form lifecycle / events
// ---------------------------------------------------------------------------
procedure TMainFrm.FormCreate(Sender: TObject);
begin
  // Vector icon geometry (see note above).
  CarIcon.Data.Data := CAR_PATH;
  SearchIcon.Data.Data := MAG_PATH;
  Illustration.Data.Data := STN_PATH;
  ShowInfo('Enter a ZIP code and press Search to find nearby charging stations.');
end;

procedure TMainFrm.ZipEditApplyStyleLookup(Sender: TObject);
var
  O: TFmxObject;
begin
  // Hide the platform edit's opaque background so the dark box shows through.
  O := ZipEdit.FindStyleResource('background');
  if O is TControl then
    TControl(O).Opacity := 0;
end;

procedure TMainFrm.ZipEditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: Char; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
    DoSearch;
  end;
end;

procedure TMainFrm.SearchClick(Sender: TObject);
begin
  DoSearch;
end;

procedure TMainFrm.SearchMouseEnter(Sender: TObject);
begin
  SearchBtn.Fill.Color := CLR_GREEN_SOFT;
end;

procedure TMainFrm.SearchMouseLeave(Sender: TObject);
begin
  SearchBtn.Fill.Color := CLR_GREEN_NONE;
end;

// ---------------------------------------------------------------------------
//  Station list management
// ---------------------------------------------------------------------------
procedure TMainFrm.ClearStations;
var
  I: Integer;
begin
  for I := StationsBox.Content.ControlsCount - 1 downto 0 do
    StationsBox.Content.Controls[I].Free;
end;

procedure TMainFrm.ShowInfo(const AText: string);
var
  L: TLabel;
begin
  ClearStations;
  L := TLabel.Create(Self);
  L.Parent := StationsBox;
  L.Align := TAlignLayout.Top;
  L.Height := 60;
  L.Margins.Rect := RectF(4, 12, 4, 0);
  L.StyledSettings := [];
  L.TextSettings.Font.Family := 'Segoe UI';
  L.TextSettings.Font.Size := 14;
  L.TextSettings.FontColor := CLR_GRAY;
  L.WordWrap := True;
  L.Text := AText;
end;

procedure TMainFrm.PopulateStations(const Stations: TArray<TStation>);
var
  S: TStation;
  Frame: TStationCard;
begin
  ClearStations;
  if Length(Stations) = 0 then
  begin
    ShowInfo('No charging stations found for that ZIP code.');
    Exit;
  end;
  for S in Stations do
  begin
    Frame := TStationCard.Create(Self);
    Frame.Name := '';  // clear inherited design name so instances don't collide
    Frame.Parent := StationsBox;
    Frame.Align := TAlignLayout.Top;
    Frame.SetStation(S);
  end;
end;

// ---------------------------------------------------------------------------
//  Search (network call on a background thread)
// ---------------------------------------------------------------------------
procedure TMainFrm.DoSearch;
var
  Zip: string;
begin
  if FBusy then Exit;
  Zip := Trim(ZipEdit.Text);
  if Zip = '' then
  begin
    StatusLabel.Text := 'Please enter a ZIP code.';
    Exit;
  end;
  SearchZip(Zip);
end;

procedure TMainFrm.SearchZip(const Zip: string);
begin
  FBusy := True;
  SearchLabel.Text := 'Searching...';
  StatusLabel.Text := 'Searching near ' + Zip + '...';
  ShowInfo('Loading nearby stations...');

  TTask.Run(
    procedure
    var
      Http: THTTPClient;
      Resp: IHTTPResponse;
      Url, Err, KeyParam: string;
      Lat, Lon: Double;
      Root: TJSONValue;
      Place: TJSONObject;
      Places: TJSONArray;
      Stations: TArray<TStation>;
    begin
      Err := '';
      Stations := nil;
      Lat := 0;
      Lon := 0;
      try
        Http := THTTPClient.Create;
        try
          Http.ConnectionTimeout := 15000;
          Http.ResponseTimeout := 20000;
          if PROXY_HOST <> '' then
          begin
            // Assign proxy via record fields (version-agnostic across the RTL).
            var PS := Http.ProxySettings;
            PS.Host := PROXY_HOST;
            PS.Port := PROXY_PORT;
            Http.ProxySettings := PS;
          end;

          // --- Step 1: ZIP -> latitude/longitude (Zippopotam.us) ---------
          Url := 'https://api.zippopotam.us/us/' + TNetEncoding.URL.Encode(Zip);
          Resp := Http.Get(Url);
          if Resp.StatusCode = 404 then
            Err := 'ZIP code not found. Please check it and try again.'
          else if Resp.StatusCode <> 200 then
            Err := Format('Lookup failed (HTTP %d).', [Resp.StatusCode])
          else
          begin
            Root := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
            try
              if (Root is TJSONObject) and
                 TJSONObject(Root).TryGetValue<TJSONArray>('places', Places) and
                 (Places.Count > 0) and (Places.Items[0] is TJSONObject) then
              begin
                Place := TJSONObject(Places.Items[0]);
                Lat := JFloat(Place, 'latitude');
                Lon := JFloat(Place, 'longitude');
              end
              else
                Err := 'Could not read location for that ZIP code.';
            finally
              Root.Free;
            end;
          end;

          // --- Step 2: stations near the coordinates (Open Charge Map) ----
          if Err = '' then
          begin
            KeyParam := '';
            if OCM_KEY <> '' then
              KeyParam := '&key=' + TNetEncoding.URL.Encode(OCM_KEY);
            Url := Format('https://api.openchargemap.io/v3/poi?output=json' +
              '&countrycode=US&latitude=%s&longitude=%s&distance=30' +
              '&distanceunit=Miles&maxresults=20&compact=false&verbose=false%s',
              [FloatToStr(Lat, TFormatSettings.Invariant),
               FloatToStr(Lon, TFormatSettings.Invariant), KeyParam]);
            Resp := Http.Get(Url);
            if Resp.StatusCode = 200 then
            begin
              Root := TJSONObject.ParseJSONValue(
                Resp.ContentAsString(TEncoding.UTF8));
              try
                if Root is TJSONArray then
                  Stations := ParseOCM(TJSONArray(Root))
                else
                  Err := 'Unexpected response from the stations service.';
              finally
                Root.Free;
              end;
            end
            else if (Resp.StatusCode = 401) or (Resp.StatusCode = 403) then
              Err := 'Stations service needs an API key. Add a free Open ' +
                     'Charge Map key (see README / OCM_KEY).'
            else
              Err := Format('Stations service returned HTTP %d.',
                [Resp.StatusCode]);
          end;
        finally
          Http.Free;
        end;
      except
        on E: Exception do
          Err := E.Message;
      end;

      TThread.Queue(nil,
        procedure
        begin
          FBusy := False;
          SearchLabel.Text := 'Search';
          if Err <> '' then
          begin
            StatusLabel.Text := 'Error: ' + Err;
            ShowInfo('Unable to load stations.' + sLineBreak + Err);
          end
          else
          begin
            PopulateStations(Stations);
            StatusLabel.Text := 'Last updated: ' +
              FormatDateTime('m/d/yyyy h:nn AM/PM', Now);
          end;
        end);
    end);
end;

end.
