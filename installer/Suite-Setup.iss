; Suite-Setup.iss - the AI Research Suite installer (Inno Setup 6).
; Build with tools\build-installer.ps1 (it writes catalog.ini first, then runs ISCC).
;
; The wizard only collects choices and shows sizes/times. Setup copies the small suite folder
; (updater + install.ps1) into <folder>\AI-Research-Suite, writes plan.ini there and runs
; install.ps1, which downloads and sets up everything with the apps' own setup scripts.
; Command line (testing / unattended): /SOURCE=<folder of release zips>  /PLANFILE=<plan.ini to use>

#ifndef SuiteVersion
  #define SuiteVersion "0.0"
#endif

[Setup]
AppId={{A93E3B4B-12E7-4726-A871-4EE22901FDE0}
AppName=AI Research Suite
AppVersion={#SuiteVersion}
AppPublisher=DFranke84
AppPublisherURL=https://github.com/DFranke84/AI-Research-Suite
AppSupportURL=https://github.com/DFranke84/AI-Research-Suite
AppUpdatesURL=https://github.com/DFranke84/AI-Research-Suite/releases
DefaultDirName={code:DefaultRoot}
AppendDefaultDirName=no
DirExistsWarning=no
UsePreviousAppDir=yes
DisableWelcomePage=no
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
WizardStyle=modern
WizardSizePercent=110
LicenseFile=licences.txt
OutputBaseFilename=Suite-Setup-{#SuiteVersion}
UninstallFilesDir={app}\AI-Research-Suite\uninstall
UninstallDisplayName=AI Research Suite
Compression=lzma2
SolidCompression=yes

[Messages]
WelcomeLabel2=A private, offline AI assistant and a survival and how-to library that keep working without internet.%n%nSetup asks what you want, shows how much space and download time it needs, then downloads and sets up everything for you.%n%n  - AIPortable (full) or AIPortable-JustAI (slim) - the AI app%n  - Research library - your own offline library and the Library Manager%n  - Library Viewer - read the library on a tablet%n%nTour video: youtu.be/AcBpQHDESII

[Files]
Source: "..\update.ps1"; DestDir: "{app}\AI-Research-Suite"; Flags: ignoreversion
Source: "..\install.ps1"; DestDir: "{app}\AI-Research-Suite"; Flags: ignoreversion
Source: "..\suite.json"; DestDir: "{app}\AI-Research-Suite"; Flags: ignoreversion
Source: "..\Check for updates.bat"; DestDir: "{app}\AI-Research-Suite"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}\AI-Research-Suite"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}\AI-Research-Suite"; Flags: ignoreversion
Source: "..\VERSION"; DestDir: "{app}\AI-Research-Suite"; Flags: ignoreversion
Source: "catalog.ini"; DestDir: "{app}\AI-Research-Suite\installer"; Flags: ignoreversion
Source: "probe.ps1"; DestDir: "{app}\AI-Research-Suite\installer"; Flags: ignoreversion
Source: "licences.txt"; DestDir: "{app}\AI-Research-Suite\installer"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\AI Research Suite\AIPortable"; Filename: "{app}\AIPortable\AIPortable.vbs"; WorkingDir: "{app}\AIPortable"; Check: IsApp('full')
Name: "{autoprograms}\AI Research Suite\AIPortable-JustAI"; Filename: "{app}\AIPortable-JustAI\AIPortable-JustAI.vbs"; WorkingDir: "{app}\AIPortable-JustAI"; Check: IsApp('slim')
Name: "{autoprograms}\AI Research Suite\Library Manager"; Filename: "{app}\Research\Library Manager.vbs"; WorkingDir: "{app}\Research"; IconFilename: "{app}\Research\_scripts\library_manager.ico"; Check: HasResearch
Name: "{autoprograms}\AI Research Suite\Check for updates"; Filename: "{app}\AI-Research-Suite\Check for updates.bat"; WorkingDir: "{app}\AI-Research-Suite"
Name: "{autoprograms}\AI Research Suite\Uninstall AI Research Suite"; Filename: "{uninstallexe}"
Name: "{autodesktop}\AIPortable"; Filename: "{app}\AIPortable\AIPortable.vbs"; WorkingDir: "{app}\AIPortable"; Check: IsApp('full') and WantDesktop
Name: "{autodesktop}\AIPortable-JustAI"; Filename: "{app}\AIPortable-JustAI\AIPortable-JustAI.vbs"; WorkingDir: "{app}\AIPortable-JustAI"; Check: IsApp('slim') and WantDesktop
Name: "{autodesktop}\Library Manager"; Filename: "{app}\Research\Library Manager.vbs"; WorkingDir: "{app}\Research"; IconFilename: "{app}\Research\_scripts\library_manager.ico"; Check: HasResearch and WantDesktop

[Run]
Filename: "{app}\AIPortable\AIPortable.vbs"; Description: "Open AIPortable now"; Flags: postinstall shellexec nowait skipifsilent; Check: IsApp('full') and InstallOk
Filename: "{app}\AIPortable-JustAI\AIPortable-JustAI.vbs"; Description: "Open AIPortable-JustAI now"; Flags: postinstall shellexec nowait skipifsilent; Check: IsApp('slim') and InstallOk
Filename: "{app}\Research\Library Manager.vbs"; Description: "Open the Library Manager now"; Flags: postinstall shellexec nowait skipifsilent unchecked; Check: HasResearch and InstallOk

[UninstallDelete]
Type: filesandordirs; Name: "{app}\AI-Research-Suite\logs"
Type: filesandordirs; Name: "{app}\AI-Research-Suite\backups"
Type: files; Name: "{app}\AI-Research-Suite\plan.ini"
Type: files; Name: "{app}\AI-Research-Suite\install-state.ini"
Type: files; Name: "{app}\AI-Research-Suite\settings.json"
Type: dirifempty; Name: "{app}\AI-Research-Suite\installer"
Type: dirifempty; Name: "{app}\AI-Research-Suite"

[Code]
const
  MaxTiers = 5;
  MaxModels = 4;

var
  PlanTier: Integer;
  PlanModel: String;
  ClosingForUninstall: Boolean;
  CatIni, ProbeIni: String;
  VramGB, RamGB, SpeedMbps: Integer;
  GpuName, WinName: String;
  OllamaRunning, Probed, Existing, InstallSucceeded: Boolean;
  AmdGpu, HaveBrowser, HaveAntiword: Boolean;
  ChkGit, ChkChrome: TNewCheckBox;
  TierIds: array[0..4] of Integer;
  TierCount: Integer;

  ModePage: TInputOptionWizardPage;
  PCPage, PiecesPage, AIPage, LibPage, ArchPage, SummaryPage: TWizardPage;
  ArchList: TNewCheckListBox;
  ArchRow: array of Integer;   { ArchList line -> catalog archive number (0 = a category heading) }
  WikiNote, ArchWhere: TNewStaticText;
  PCValues: array[0..5] of TNewStaticText;
  SpeedCombo: TNewComboBox;
  RadFull, RadSlim, RadNone: TNewRadioButton;
  ChkResearch, ChkViewer: TNewCheckBox;
  TierPanel, ModelPanel: TPanel;
  TierRadios: array[0..4] of TNewRadioButton;
  ModelRadios: array[0..3] of TNewRadioButton;
  ModelInfo: array[0..3] of TNewStaticText;
  ChkVoice: TNewCheckBox;
  MapsLabel: TNewStaticText;
  MapsList: TNewCheckListBox;
  PacksList: TNewCheckListBox;
  WikiRadios: array[0..2] of TNewRadioButton;
  SumMemo: TNewMemo;
  SumTotals, SumWarn: TNewStaticText;
  RadNow, RadLater: TNewRadioButton;
  ChkDesktop, ChkWeekly: TNewCheckBox;
  LocalPage: TWizardPage;
  ChkLocal, ChkLocalMap: TNewCheckBox;
  PlaceEdit: TNewEdit;
  FindBtn: TNewButton;
  PlaceCombo, KmCombo, PerCombo, TopoCombo: TNewComboBox;
  PlaceNote, LocalEst, TopoLabel: TNewStaticText;
  PlaceLat, PlaceLon, PlaceCC: array[0..4] of String;
  PlaceCount: Integer;

function GetDriveType(lpRootPathName: String): Cardinal; external 'GetDriveTypeW@kernel32.dll stdcall';

{ ---------------------------------------------------------------- small helpers }
function Field(S: String; N: Integer): String;
var I: Integer;
begin
  for I := 1 to N - 1 do begin
    if Pos('|', S) = 0 then begin Result := ''; exit; end;
    S := Copy(S, Pos('|', S) + 1, Length(S));
  end;
  if Pos('|', S) > 0 then S := Copy(S, 1, Pos('|', S) - 1);
  Result := S;
end;

function Cat(Section, Key: String): String;
begin
  Result := GetIniString(Section, Key, '', CatIni);
end;

function CatInt(Section, Key: String): Integer;
begin
  Result := StrToIntDef(Cat(Section, Key), 0);
end;

function SizeText(MB: Integer): String;
begin
  if MB < 1000 then Result := IntToStr(MB) + ' MB'
  else if MB < 10000 then Result := Format('%d.%d GB', [MB div 1000, (MB mod 1000) div 100])
  else Result := IntToStr((MB + 500) div 1000) + ' GB';
end;

function TimeText(MB: Integer): String;
var Secs, H, M: Integer;
begin
  if SpeedMbps <= 0 then begin Result := '?'; exit; end;
  Secs := (MB * 8) div SpeedMbps;
  if Secs < 60 then Result := 'under 1 min'
  else if Secs < 3600 then Result := IntToStr((Secs + 30) div 60) + ' min'
  else begin
    H := Secs div 3600; M := ((Secs mod 3600) + 30) div 60;
    Result := IntToStr(H) + ' h';
    if M > 0 then Result := Result + ' ' + IntToStr(M) + ' min';
  end;
end;

function MakeLabel(Page: TWizardPage; Caption: String; Top: Integer; Bold: Boolean): TNewStaticText;
begin
  Result := TNewStaticText.Create(Page);
  Result.Parent := Page.Surface;
  Result.Caption := Caption;
  Result.Top := Top;
  Result.Left := 0;
  Result.AutoSize := True;
  if Bold then Result.Font.Style := [fsBold];
end;

{ ---------------------------------------------------------------- choices, as the [Icons]/[Run] checks see them }
function AppChoice: String;
begin
  if RadFull.Checked then Result := 'full'
  else if RadSlim.Checked then Result := 'slim'
  else Result := 'none';
end;

function IsApp(Which: String): Boolean;
begin
  Result := AppChoice = Which;
end;

function HasResearch: Boolean;
begin
  Result := ChkResearch.Checked or ChkViewer.Checked;
end;

function WantDesktop: Boolean;
begin
  Result := ChkDesktop.Checked;
end;

function InstallOk: Boolean;
begin
  Result := InstallSucceeded;
end;

function SelectedTier: Integer;
var I: Integer;
begin
  Result := TierIds[0];
  for I := 0 to TierCount - 1 do
    if TierRadios[I].Checked then Result := TierIds[I];
end;

function SelectedModel: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to MaxModels - 1 do
    if ModelRadios[I].Checked then Result := I;
end;

function ModelEntry(Tier, Idx: Integer): String;
begin
  Result := Cat('tier' + IntToStr(Tier), 'm' + IntToStr(Idx + 1));
end;

function PackGroupChecked(G: String): Boolean;
var I: Integer; L: String;
begin
  Result := False;
  L := Cat('packs', 'list') + ',';
  for I := 0 to PacksList.Items.Count - 1 do begin
    if Copy(L, 1, Pos(',', L) - 1) = G then begin Result := HasResearch and PacksList.Checked[I]; exit; end;
    L := Copy(L, Pos(',', L) + 1, Length(L));
  end;
end;

{ the starter-pack group that downloads this archive anyway ('' = none ticked) }
function ArchiveComesWith(ArchiveKey: String): String;
var L, G: String;
begin
  Result := '';
  if ArchiveKey = '' then exit;
  L := Cat('packs', 'list') + ',';
  while Pos(',', L) > 0 do begin
    G := Copy(L, 1, Pos(',', L) - 1);
    L := Copy(L, Pos(',', L) + 1, Length(L));
    if (Pos(',' + ArchiveKey + ',', ',' + Cat('pack-' + G, 'archives') + ',') > 0) and PackGroupChecked(G) then begin
      Result := Cat('pack-' + G, 'title'); exit;
    end;
  end;
end;

function WikiChoice: String;
begin
  if WikiRadios[1].Checked then Result := 'nopic'
  else if WikiRadios[2].Checked then Result := 'maxi'
  else Result := 'none';
end;

{ ---------------------------------------------------------------- the default folder: the fixed drive with the most room }
function DefaultRoot(Param: String): String;
var D: Integer; Free, Total, Best: Int64; Root, BestRoot: String;
begin
  BestRoot := ExpandConstant('{sd}');
  Best := 0;
  for D := Ord('C') to Ord('Z') do begin
    Root := Chr(D) + ':\';
    if (GetDriveType(Root) = 3) and GetSpaceOnDisk64(Root, Free, Total) then
      if Free > Best then begin Best := Free; BestRoot := Chr(D) + ':'; end;
  end;
  Result := BestRoot + '\AI-Research';
end;

{ ---------------------------------------------------------------- PC probe }
procedure RunProbe;
var RC: Integer;
begin
  ExtractTemporaryFile('probe.ps1');
  ProbeIni := ExpandConstant('{tmp}\probe.ini');
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\probe.ps1') + '" -Out "' + ProbeIni + '"',
       '', SW_HIDE, ewWaitUntilTerminated, RC);
  WinName := GetIniString('pc', 'windows', 'Windows', ProbeIni);
  RamGB := GetIniInt('pc', 'ramGB', 0, 0, 0, ProbeIni);
  GpuName := GetIniString('pc', 'gpu', 'unknown', ProbeIni);
  VramGB := GetIniInt('pc', 'vramGB', 0, 0, 0, ProbeIni);
  OllamaRunning := GetIniInt('pc', 'ollamaRunning', 0, 0, 0, ProbeIni) = 1;
  AmdGpu := GetIniInt('pc', 'amd', 0, 0, 0, ProbeIni) = 1;
  HaveBrowser := GetIniInt('pc', 'browser', 1, 0, 0, ProbeIni) = 1;
  HaveAntiword := GetIniInt('pc', 'antiword', 1, 0, 0, ProbeIni) = 1;
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\probe.ps1') + '" -Speed -Out "' + ExpandConstant('{tmp}\speed.ini') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, RC);
  SpeedMbps := GetIniInt('net', 'mbps', 0, 0, 0, ExpandConstant('{tmp}\speed.ini'));
  if SpeedMbps <= 0 then SpeedMbps := 25;
  Probed := True;
end;

function DriveInfo(Letter: String; N: Integer): String;
var I, Count: Integer; Row: String;
begin
  Result := '';
  Count := GetIniInt('drives', 'count', 0, 0, 0, ProbeIni);
  for I := 1 to Count do begin
    Row := GetIniString('drives', 'd' + IntToStr(I), '', ProbeIni);
    if CompareText(Field(Row, 1), Letter) = 0 then begin Result := Field(Row, N); exit; end;
  end;
end;

function DrivesText: String;
var I, Count: Integer; Row: String;
begin
  Result := '';
  Count := GetIniInt('drives', 'count', 0, 0, 0, ProbeIni);
  for I := 1 to Count do begin
    Row := GetIniString('drives', 'd' + IntToStr(I), '', ProbeIni);
    if Result <> '' then Result := Result + '   ';
    Result := Result + Field(Row, 1) + ' ' + SizeText(StrToIntDef(Field(Row, 2), 0) * 1000) + ' free (' + Field(Row, 4) + ')';
  end;
end;

procedure ShowProbe;
var I: Integer; Measured: String;
begin
  PCValues[0].Caption := WinName;
  PCValues[1].Caption := IntToStr(RamGB) + ' GB';
  if VramGB > 0 then
    PCValues[2].Caption := GpuName + ' - ' + IntToStr(VramGB) + ' GB  (you can pick any AI model size up to ' + IntToStr(VramGB) + ' GB)'
  else
    PCValues[2].Caption := GpuName + ' - memory not detected (small models are the safe choice)';
  if AmdGpu then PCValues[2].Caption := PCValues[2].Caption + ' - AMD card: Ollama''s AMD add-on is installed too';
  PCValues[3].Caption := DrivesText;
  PCValues[4].Caption := IntToStr(SpeedMbps) + ' Mbps (quick test) - used for the time estimates';
  if OllamaRunning then
    PCValues[5].Caption := 'Another copy of Ollama is running - close it before the install starts (the suite uses its own copy)'
  else
    PCValues[5].Caption := 'Port 11434 is free';
  Measured := IntToStr(SpeedMbps) + ' Mbps (measured)';
  SpeedCombo.Items.Clear;
  SpeedCombo.Items.Add(Measured);
  SpeedCombo.Items.Add('10 Mbps (slow DSL)');
  SpeedCombo.Items.Add('25 Mbps');
  SpeedCombo.Items.Add('100 Mbps');
  SpeedCombo.Items.Add('300 Mbps');
  SpeedCombo.Items.Add('1000 Mbps (fibre)');
  SpeedCombo.ItemIndex := 0;
  { tiers: any size up to the card's memory }
  for I := 0 to TierCount - 1 do begin
    TierRadios[I].Enabled := (VramGB = 0) and (TierIds[I] <= 8) or (VramGB > 0) and (TierIds[I] <= VramGB);
  end;
  for I := TierCount - 1 downto 0 do
    if TierRadios[I].Enabled then begin TierRadios[I].Checked := True; break; end;
  for I := 0 to TierCount - 1 do
    if (TierIds[I] = PlanTier) and TierRadios[I].Enabled then TierRadios[I].Checked := True;
end;

procedure SpeedChanged(Sender: TObject);
var S: String;
begin
  S := SpeedCombo.Text;
  if Pos(' ', S) > 0 then S := Copy(S, 1, Pos(' ', S) - 1);
  SpeedMbps := StrToIntDef(S, SpeedMbps);
end;

{ ---------------------------------------------------------------- AI options page }
procedure FillModels;
var I, T: Integer; E: String;
begin
  T := SelectedTier;
  for I := 0 to MaxModels - 1 do begin
    E := ModelEntry(T, I);
    ModelRadios[I].Visible := E <> '';
    ModelInfo[I].Visible := E <> '';
    if E <> '' then ModelRadios[I].Caption := Field(E, 2) + '   (' + SizeText(StrToIntDef(Field(E, 4), 0)) + ')';
    if (PlanModel <> '') and (Field(E, 3) = PlanModel) then ModelRadios[I].Checked := True;
  end;
end;

procedure TierClick(Sender: TObject);
begin
  PlanModel := '';
  FillModels;
end;

procedure AppChanged(Sender: TObject);
begin
  if ChkViewer.Checked then ChkResearch.Checked := True;
end;

procedure ResearchClick(Sender: TObject);
begin
  if not ChkResearch.Checked then ChkViewer.Checked := False;
end;

{ ---------------------------------------------------------------- sizes }
{ ---------------------------------------------------------------- Offline archives }
procedure UpdateArchives(Sender: TObject);
var I: Integer; E, Pack: String;
begin
  if HasResearch then begin
    WikiNote.Caption := 'It also speeds up the Wikipedia articles pack and Local Area: they read their articles from it instead of ' +
      'wikipedia.org (so it is downloaded first).';
    ArchWhere.Caption := 'Saved in Research\_sources\zim - the AI apps read them there. Skip any now? Add them later with Get Archives.bat';
    if IsApp('full') then ArchWhere.Caption := ArchWhere.Caption + ' or AIPortable''s Wikipedia tab.' else ArchWhere.Caption := ArchWhere.Caption + '.';
  end else begin
    WikiNote.Caption := 'Read it in AIPortable''s Wikipedia tab; the AI can search it while it answers.';
    ArchWhere.Caption := 'Saved in AIPortable\data\wikipedia. Skip any now? Add them later in AIPortable''s Wikipedia tab.';
  end;
  { archives a ticked starter pack downloads anyway: shown ticked and greyed }
  for I := 0 to ArchList.Items.Count - 1 do
    if ArchRow[I] > 0 then begin
      E := Cat('archives', 'a' + IntToStr(ArchRow[I]));
      Pack := ArchiveComesWith(Field(E, 6));
      ArchList.ItemEnabled[I] := Pack = '';
      if Pack <> '' then begin
        ArchList.Checked[I] := True;
        ArchList.ItemSubItem[I] := 'with ' + Pack;
      end else
        ArchList.ItemSubItem[I] := SizeText(StrToIntDef(Field(E, 3), 0));
    end;
end;

{ ---------------------------------------------------------------- Your local area (Build Local Area) }
function ComboNumText(S: String): String;
begin
  if Pos(' ', S) > 0 then S := Copy(S, 1, Pos(' ', S) - 1);
  if S = 'none' then S := '0';
  Result := S;
end;

function ComboNum(C: TNewComboBox): Integer;
begin
  Result := StrToIntDef(ComboNumText(C.Text), 0);
end;

function LocalOn: Boolean;
begin
  Result := HasResearch and ChkLocal.Checked and (PlaceCount > 0) and (PlaceCombo.ItemIndex >= 0);
end;

function PlaceIsUS: Boolean;
begin
  Result := (PlaceCount > 0) and (PlaceCombo.ItemIndex >= 0) and (PlaceCC[PlaceCombo.ItemIndex] = 'us');
end;

{ USGS 7.5-minute maps are about 13 x 14 km and about 55 MB each (measured, Asheville 2026-10) }
function TopoCount: Integer;
var K: Integer;
begin
  K := ComboNum(TopoCombo);
  if (K <= 0) or not PlaceIsUS then Result := 0
  else Result := ((2 * K + 12) div 13) * ((2 * K + 13) div 14);
end;

{ 11 groups (flowering plants, conifers, grasses, ferns, birds, mammals, fish, reptiles, insects, spiders,
  fungi). Measured on a test build (Asheville, 2026-10): a page with its photos is about 1.7 MB and takes about
  12 s to build - iNaturalist is asked one species at a time. Quiet areas have fewer species than asked for. }
function SpeciesMB: Integer;
begin
  Result := 11 * ComboNum(PerCombo) * 17 div 10;
end;

function SpeciesMinutes: Integer;
begin
  Result := 11 * ComboNum(PerCombo) * 12 div 60;
end;

function MinutesText(M: Integer): String;
begin
  if M < 60 then Result := IntToStr(M) + ' min'
  else if M mod 60 = 0 then Result := IntToStr(M div 60) + ' h'
  else Result := IntToStr(M div 60) + ' h ' + IntToStr(M mod 60) + ' min';
end;

{ street detail for the square around the place: about 7 MB per 1,000 square km (17 MB for 25 km around Asheville) }
function AreaMapMB: Integer;
var R: Integer;
begin
  R := ComboNum(KmCombo);
  Result := (2 * R) * (2 * R) * 7 div 1000;
  if Result < 5 then Result := 5;
end;

procedure UpdateLocal(Sender: TObject);
var On, Found: Boolean; Mins: Integer; T: String;
begin
  On := ChkLocal.Checked;
  Found := (PlaceCount > 0) and (PlaceCombo.ItemIndex >= 0);
  PlaceEdit.Enabled := On; FindBtn.Enabled := On; PlaceCombo.Enabled := On and Found;
  KmCombo.Enabled := On; PerCombo.Enabled := On;
  TopoCombo.Enabled := On and PlaceIsUS; TopoLabel.Enabled := TopoCombo.Enabled;
  ChkLocalMap.Visible := IsApp('full'); ChkLocalMap.Enabled := On;
  if not On then begin LocalEst.Caption := ''; exit; end;
  if not Found then begin LocalEst.Caption := 'Type where you live and click Find.'; exit; end;
  Mins := SpeciesMinutes;
  T := 'About ' + SizeText(SpeciesMB) + ' of species pages, about ' + MinutesText(Mins) + ' to build (iNaturalist is asked one species at a time)';
  if TopoCount > 0 then T := T + ', ' + IntToStr(TopoCount) + ' topo maps (about ' + SizeText(TopoCount * 55) + ')';
  if IsApp('full') and ChkLocalMap.Checked then T := T + ', a ' + SizeText(AreaMapMB) + ' street map';
  LocalEst.Caption := T + '.';
end;

procedure FindClick(Sender: TObject);
var RC, I: Integer; F, Row, Q: String;
begin
  Q := Trim(PlaceEdit.Text);
  StringChangeEx(Q, '"', '', True);
  if Q = '' then exit;
  FindBtn.Enabled := False;
  PlaceNote.Caption := 'Looking it up...';
  WizardForm.Repaint;
  if not FileExists(ExpandConstant('{tmp}\probe.ps1')) then ExtractTemporaryFile('probe.ps1');
  F := ExpandConstant('{tmp}\place.ini');
  DeleteFile(F);
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\probe.ps1') + '" -Out "' + F + '" -Place "' + Q + '"',
       '', SW_HIDE, ewWaitUntilTerminated, RC);
  PlaceCount := GetIniInt('places', 'count', 0, 0, 5, F);
  PlaceCombo.Items.Clear;
  for I := 1 to PlaceCount do begin
    Row := GetIniString('places', 'p' + IntToStr(I), '', F);
    PlaceCombo.Items.Add(Field(Row, 1));
    PlaceLat[I - 1] := Field(Row, 2); PlaceLon[I - 1] := Field(Row, 3); PlaceCC[I - 1] := Field(Row, 4);
  end;
  if PlaceCount > 0 then begin
    PlaceCombo.ItemIndex := 0;
    if PlaceCount > 1 then PlaceNote.Caption := IntToStr(PlaceCount) + ' places found - pick yours in the list.' + ' Only the place search (OpenStreetMap), iNaturalist and USGS see it; it is kept in your library, nowhere else.'
    else PlaceNote.Caption := 'Found it.' + ' Only the place search (OpenStreetMap), iNaturalist and USGS see it; it is kept in your library, nowhere else.';
  end else
    PlaceNote.Caption := 'Not found (or no internet) - try a town with its state or country, or a position like 35.59, -82.55.';
  UpdateLocal(nil);
end;

procedure AddRow(var Lines: String; var DlMB, DiskMB: Integer; Name: String; Dl, Disk: Integer);
var Pad: String;
begin
  DlMB := DlMB + Dl; DiskMB := DiskMB + Disk;
  Pad := Name;
  while Length(Pad) < 35 do Pad := Pad + ' ';
  Lines := Lines + Pad + Format('%8s %8s %12s', [SizeText(Dl), SizeText(Disk), TimeText(Dl)]) + #13#10;
end;

procedure AddRowTime(var Lines: String; var DlMB, DiskMB: Integer; Name: String; Dl, Disk: Integer; Time: String);
var Pad: String;
begin
  DlMB := DlMB + Dl; DiskMB := DiskMB + Disk;
  Pad := Name;
  while Length(Pad) < 35 do Pad := Pad + ' ';
  Lines := Lines + Pad + Format('%8s %8s %12s', [SizeText(Dl), SizeText(Disk), Time]) + #13#10;
end;

procedure Totals(var Lines: String; var DlMB, DiskMB: Integer);
var I, M, PacksMB, PacksN, MapsMB: Integer; E, Key, Pad: String;
begin
  Lines := ''; DlMB := 0; DiskMB := 0;
  Pad := 'Item';
  while Length(Pad) < 35 do Pad := Pad + ' ';
  Lines := Pad + Format('%8s %8s %12s', ['Download', 'On disk', 'Time']) + #13#10;
  if not IsApp('none') then begin
    if IsApp('full') then Key := 'AIPortable' else Key := 'AIPortable-JustAI';
    AddRow(Lines, DlMB, DiskMB, Key + ' + its runtimes', CatInt('base', 'appDlMB'), CatInt('base', 'appDiskMB'));
    E := ModelEntry(SelectedTier, SelectedModel);
    M := StrToIntDef(Field(E, 4), 0);
    AddRow(Lines, DlMB, DiskMB, 'Chat model: ' + Field(E, 2), M, M);
    M := CatInt('tier' + IntToStr(SelectedTier), 'embedMB');
    AddRow(Lines, DlMB, DiskMB, 'Search index model', M, M);
    if ChkVoice.Checked then AddRow(Lines, DlMB, DiskMB, 'Voice input', CatInt('base', 'voiceDlMB'), CatInt('base', 'voiceDiskMB'));
    if IsApp('full') then begin
      MapsMB := CatInt('maps', 'worldMB');
      for I := 0 to MapsList.Items.Count - 1 do
        if MapsList.Checked[I] then MapsMB := MapsMB + StrToIntDef(Field(Cat('maps', 'm' + IntToStr(I + 1)), 3), 0);
      AddRow(Lines, DlMB, DiskMB, 'Offline maps', MapsMB, MapsMB);
    end;
  end;
  if HasResearch then begin
    AddRow(Lines, DlMB, DiskMB, 'Research library + Library Manager', CatInt('base', 'researchDlMB'), CatInt('base', 'researchDiskMB'));
    PacksMB := 0; PacksN := 0; Key := Cat('packs', 'list') + ',';
    for I := 0 to PacksList.Items.Count - 1 do begin
      if PacksList.Checked[I] then begin
        PacksMB := PacksMB + CatInt('pack-' + Copy(Key, 1, Pos(',', Key) - 1), 'mb');
        PacksN := PacksN + 1;
      end;
      Key := Copy(Key, Pos(',', Key) + 1, Length(Key));
    end;
    if PacksN > 0 then begin
      AddRow(Lines, DlMB, DiskMB, 'Starter packs (' + IntToStr(PacksN) + ')', PacksMB, PacksMB + PacksMB * CatInt('base', 'pagesPercent') div 100);
    end;
  end;
  if HasResearch or IsApp('full') then begin
    if WikiChoice = 'nopic' then AddRow(Lines, DlMB, DiskMB, 'Wikipedia (text, no pictures)', CatInt('wiki', 'nopicMB'), CatInt('wiki', 'nopicMB'));
    if WikiChoice = 'maxi' then AddRow(Lines, DlMB, DiskMB, 'Wikipedia (with pictures)', CatInt('wiki', 'maxiMB'), CatInt('wiki', 'maxiMB'));
    M := 0; PacksN := 0;
    for I := 0 to ArchList.Items.Count - 1 do
      if (ArchRow[I] > 0) and ArchList.Checked[I] and ArchList.ItemEnabled[I] then begin
        M := M + StrToIntDef(Field(Cat('archives', 'a' + IntToStr(ArchRow[I])), 3), 0);
        PacksN := PacksN + 1;
      end;
    if PacksN > 0 then AddRow(Lines, DlMB, DiskMB, 'More archives (' + IntToStr(PacksN) + ')', M, M);
  end;
  if LocalOn then begin
    AddRowTime(Lines, DlMB, DiskMB, 'Local Area: species pages', SpeciesMB, SpeciesMB, MinutesText(SpeciesMinutes));
    if TopoCount > 0 then AddRow(Lines, DlMB, DiskMB, 'Local Area: ' + IntToStr(TopoCount) + ' topo maps', TopoCount * 55, TopoCount * 55);
    if IsApp('full') and ChkLocalMap.Checked then AddRow(Lines, DlMB, DiskMB, 'Street map of your area', AreaMapMB, AreaMapMB);
  end;
  if ChkViewer.Checked then AddRow(Lines, DlMB, DiskMB, 'Library Viewer + tablet data', CatInt('base', 'viewerDlMB'), CatInt('base', 'viewerDiskMB'));
end;

function FreeMB(Dir: String): Integer;
var Free, Total: Int64;
begin
  Result := -1;
  if GetSpaceOnDisk64(ExtractFileDrive(Dir) + '\', Free, Total) then Result := Free div 1000000;
end;

procedure ShowSummary;
var Lines, Warn: String; Dl, Disk, Free: Integer;
begin
  Totals(Lines, Dl, Disk);
  SumMemo.Text := Lines;
  Free := FreeMB(WizardDirValue);
  SumTotals.Caption := 'Download ' + SizeText(Dl) + '  -  space needed on ' + ExtractFileDrive(WizardDirValue) + ' ' + SizeText(Disk) +
    '  -  about ' + TimeText(Dl) + ' at ' + IntToStr(SpeedMbps) + ' Mbps';
  if LocalOn then SumTotals.Caption := SumTotals.Caption + ' + Local Area ' + MinutesText(SpeciesMinutes);
  Warn := '';
  if (Free >= 0) and (Free < Disk) then Warn := 'Not enough space: ' + ExtractFileDrive(WizardDirValue) + ' has ' + SizeText(Free) + ' free. Go back and pick another folder or fewer items.'
  else if Free >= 0 then Warn := SizeText(Free - Disk) + ' will be left free afterwards (sizes are estimates).';
  SumWarn.Caption := Warn;
  RadLater.Enabled := (WikiChoice <> 'none') and HasResearch and not PackGroupChecked('wiki') and not LocalOn;
  if not RadLater.Enabled then RadNow.Checked := True;
end;

{ ---------------------------------------------------------------- restoring an earlier install's choices }
procedure LoadPlan(F: String);
var S, L: String; I: Integer;
begin
  S := GetIniString('plan', 'app', 'slim', F);
  RadFull.Checked := S = 'full'; RadSlim.Checked := S = 'slim'; RadNone.Checked := S = 'none';
  ChkResearch.Checked := GetIniString('plan', 'research', '1', F) = '1';
  ChkViewer.Checked := GetIniString('plan', 'viewer', '0', F) = '1';
  ChkVoice.Checked := GetIniString('plan', 'voice', '1', F) = '1';
  S := GetIniString('plan', 'wiki', 'none', F);
  WikiRadios[1].Checked := S = 'nopic'; WikiRadios[2].Checked := S = 'maxi'; WikiRadios[0].Checked := (S <> 'nopic') and (S <> 'maxi');
  ChkDesktop.Checked := GetIniString('plan', 'desktop', '1', F) = '1';
  ChkWeekly.Checked := GetIniString('plan', 'weekly', '1', F) = '1';
  S := ',' + GetIniString('plan', 'maps', '', F) + ',';
  for I := 0 to MapsList.Items.Count - 1 do
    MapsList.Checked[I] := Pos(',' + Field(Cat('maps', 'm' + IntToStr(I + 1)), 1) + ',', S) > 0;
  S := ',' + GetIniString('plan', 'packs', '', F) + ',';
  L := Cat('packs', 'list') + ',';
  for I := 0 to PacksList.Items.Count - 1 do begin
    PacksList.Checked[I] := Pos(',' + Copy(L, 1, Pos(',', L) - 1) + ',', S) > 0;
    L := Copy(L, Pos(',', L) + 1, Length(L));
  end;
  PlanTier := StrToIntDef(GetIniString('plan', 'tier', '0', F), 0);
  PlanModel := GetIniString('plan', 'model', '', F);
  RadLater.Checked := GetIniString('plan', 'background', '0', F) = '1';
  RadNow.Checked := not RadLater.Checked;
  S := ',' + GetIniString('plan', 'archives', '', F) + ',';
  for I := 0 to ArchList.Items.Count - 1 do
    if ArchRow[I] > 0 then ArchList.Checked[I] := Pos(',' + Field(Cat('archives', 'a' + IntToStr(ArchRow[I])), 1) + ',', S) > 0;
  ChkGit.Checked := Pos('git', GetIniString('plan', 'tools', '', F)) > 0;
  ChkChrome.Checked := Pos('chrome', GetIniString('plan', 'tools', '', F)) > 0;
  if GetIniString('plan', 'local', '0', F) = '1' then begin
    ChkLocal.Checked := True;
    PlaceCount := 1;
    PlaceCombo.Items.Clear; PlaceCombo.Items.Add(GetIniString('plan', 'localName', '', F)); PlaceCombo.ItemIndex := 0;
    PlaceLat[0] := GetIniString('plan', 'localLat', '', F); PlaceLon[0] := GetIniString('plan', 'localLon', '', F);
    PlaceCC[0] := GetIniString('plan', 'localCountry', '', F);
    PlaceEdit.Text := PlaceCombo.Text;
    for I := 0 to KmCombo.Items.Count - 1 do if ComboNumText(KmCombo.Items[I]) = GetIniString('plan', 'localKm', '', F) then KmCombo.ItemIndex := I;
    for I := 0 to PerCombo.Items.Count - 1 do if ComboNumText(PerCombo.Items[I]) = GetIniString('plan', 'localPerGroup', '', F) then PerCombo.ItemIndex := I;
    for I := 0 to TopoCombo.Items.Count - 1 do if ComboNumText(TopoCombo.Items[I]) = GetIniString('plan', 'localTopoKm', '', F) then TopoCombo.ItemIndex := I;
    ChkLocalMap.Checked := GetIniString('plan', 'localMap', '0', F) = '1';
  end;
end;

{ ---------------------------------------------------------------- building the pages }
procedure InitializeWizard;
var I, Top, N: Integer; E, L, G: String; Lbl: TNewStaticText;
begin
  ExtractTemporaryFile('catalog.ini');
  CatIni := ExpandConstant('{tmp}\catalog.ini');
  L := Cat('tiers', 'list') + ',';
  TierCount := 0;
  while (Pos(',', L) > 0) and (TierCount < MaxTiers) do begin
    TierIds[TierCount] := StrToIntDef(Copy(L, 1, Pos(',', L) - 1), 0);
    L := Copy(L, Pos(',', L) + 1, Length(L));
    TierCount := TierCount + 1;
  end;

  ModePage := CreateInputOptionPage(wpWelcome, 'AI Research Suite is already installed',
    'Found an existing install in the folder below. What would you like to do?', '', True, False);
  ModePage.Add('Update and repair - keep my choices (your chats, models and library are kept)');
  ModePage.Add('Change my choices - add or remove pieces, models, maps or library packs');
  ModePage.Add('Uninstall');
  ModePage.SelectedValueIndex := 0;

  { -- Check this PC }
  PCPage := CreateCustomPage(wpLicense, 'Checking this PC', 'Setup looked at your computer to recommend the right AI model and where to put things.');
  Top := 0;
  for I := 0 to 5 do begin
    case I of
      0: L := 'Windows';
      1: L := 'Memory';
      2: L := 'Graphics card';
      3: L := 'Free space';
      4: L := 'Internet';
      5: L := 'Ollama';
    end;
    MakeLabel(PCPage, L, Top, True);
    PCValues[I] := MakeLabel(PCPage, 'checking...', Top, False);
    PCValues[I].Left := ScaleX(110);
    PCValues[I].AutoSize := False;
    PCValues[I].WordWrap := True;
    PCValues[I].Width := PCPage.SurfaceWidth - ScaleX(110);
    PCValues[I].Height := ScaleY(30);
    Top := Top + ScaleY(32);
  end;
  MakeLabel(PCPage, 'Internet speed used for the time estimates:', Top + ScaleY(8), False);
  SpeedCombo := TNewComboBox.Create(PCPage);
  SpeedCombo.Parent := PCPage.Surface;
  SpeedCombo.Style := csDropDownList;
  SpeedCombo.Top := Top + ScaleY(4);
  SpeedCombo.Left := ScaleX(250);
  SpeedCombo.Width := ScaleX(170);
  SpeedCombo.OnChange := @SpeedChanged;

  { -- Choose pieces }
  PiecesPage := CreateCustomPage(PCPage.ID, 'What would you like to install?', 'Pick one AI app (or none), then the library add-ons.');
  MakeLabel(PiecesPage, 'AI app (pick one)', 0, True);
  RadFull := TNewRadioButton.Create(PiecesPage); RadFull.Parent := PiecesPage.Surface;
  RadFull.Caption := 'AIPortable (full) - chat, library search, offline maps and the Wikipedia reader';
  RadFull.Top := ScaleY(22); RadFull.Width := PiecesPage.SurfaceWidth;
  RadSlim := TNewRadioButton.Create(PiecesPage); RadSlim.Parent := PiecesPage.Surface;
  RadSlim.Caption := 'AIPortable-JustAI (slim) - chat and library search, no maps';
  RadSlim.Top := ScaleY(46); RadSlim.Width := PiecesPage.SurfaceWidth; RadSlim.Checked := True;
  RadNone := TNewRadioButton.Create(PiecesPage); RadNone.Parent := PiecesPage.Surface;
  RadNone.Caption := 'No AI app - only the library tools';
  RadNone.Top := ScaleY(70); RadNone.Width := PiecesPage.SurfaceWidth;
  MakeLabel(PiecesPage, 'Library add-ons', ScaleY(106), True);
  ChkResearch := TNewCheckBox.Create(PiecesPage); ChkResearch.Parent := PiecesPage.Surface;
  ChkResearch.Caption := 'Research library - your offline library, the Library Manager, starter packs and archives';
  ChkResearch.Top := ScaleY(128); ChkResearch.Width := PiecesPage.SurfaceWidth; ChkResearch.Checked := True;
  ChkResearch.OnClick := @ResearchClick;
  ChkViewer := TNewCheckBox.Create(PiecesPage); ChkViewer.Parent := PiecesPage.Surface;
  ChkViewer.Caption := 'Library Viewer - read the library on an Android tablet (needs the Research library)';
  ChkViewer.Top := ScaleY(152); ChkViewer.Width := PiecesPage.SurfaceWidth;
  ChkViewer.OnClick := @AppChanged;
  MakeLabel(PiecesPage, 'People use AIPortable or JustAI, not both. Everything goes side by side in one folder (next page).', ScaleY(188), False);

  { -- AI options (after the folder page) }
  AIPage := CreateCustomPage(wpSelectDir, 'AI options', 'Pick a model size up to your graphics card''s memory, then a model. More can be added later in the app.');
  MakeLabel(AIPage, 'Model size', 0, True);
  { sizes and models sit on panels of their own, so they are two separate radio groups }
  TierPanel := TPanel.Create(AIPage);
  TierPanel.Parent := AIPage.Surface;
  TierPanel.BevelOuter := bvNone; TierPanel.ParentBackground := False; TierPanel.Color := clWindow;
  TierPanel.Top := ScaleY(18); TierPanel.Width := AIPage.SurfaceWidth; TierPanel.Height := ScaleY(22);
  for I := 0 to TierCount - 1 do begin
    TierRadios[I] := TNewRadioButton.Create(AIPage);
    TierRadios[I].Parent := TierPanel;
    TierRadios[I].Caption := IntToStr(TierIds[I]) + ' GB';
    TierRadios[I].Top := ScaleY(2);
    TierRadios[I].Left := I * ScaleX(84);
    TierRadios[I].Width := ScaleX(82);
    TierRadios[I].OnClick := @TierClick;
  end;
  L := 'Sizes above your graphics card''s memory are greyed out. Smaller models answer faster; bigger ones answer better.';
  Lbl := MakeLabel(AIPage, L, ScaleY(44), False);
  Lbl.AutoSize := False; Lbl.WordWrap := True; Lbl.Width := AIPage.SurfaceWidth; Lbl.Height := ScaleY(28);
  MakeLabel(AIPage, 'Chat model', ScaleY(80), True);
  ModelPanel := TPanel.Create(AIPage);
  ModelPanel.Parent := AIPage.Surface;
  ModelPanel.BevelOuter := bvNone; ModelPanel.ParentBackground := False; ModelPanel.Color := clWindow;
  ModelPanel.Top := ScaleY(98); ModelPanel.Width := AIPage.SurfaceWidth; ModelPanel.Height := ScaleY(4 * 30);
  for I := 0 to MaxModels - 1 do begin
    ModelRadios[I] := TNewRadioButton.Create(AIPage);
    ModelRadios[I].Parent := ModelPanel;
    ModelRadios[I].Top := ScaleY(I * 30);
    ModelRadios[I].Width := ScaleX(165);
    case I of
      0: E := 'Survival - practical how-to answers (recommended)';
      1: E := 'General - an all-rounder for everyday questions';
      2: E := 'Reasoning - thinks step by step (slower)';
      3: E := 'Vision - can look at photos you attach';
    end;
    ModelInfo[I] := TNewStaticText.Create(AIPage);
    ModelInfo[I].Parent := ModelPanel;
    ModelInfo[I].Caption := E;
    ModelInfo[I].Top := ScaleY(I * 30 + 2);
    ModelInfo[I].Left := ScaleX(170);
    ModelInfo[I].AutoSize := False; ModelInfo[I].WordWrap := True;
    ModelInfo[I].Width := AIPage.SurfaceWidth - ScaleX(170); ModelInfo[I].Height := ScaleY(28);
  end;
  ModelRadios[0].Checked := True;
  ChkVoice := TNewCheckBox.Create(AIPage); ChkVoice.Parent := AIPage.Surface;
  ChkVoice.Caption := 'Voice input - talk to the AI instead of typing';
  ChkVoice.Top := ScaleY(236); ChkVoice.Width := AIPage.SurfaceWidth; ChkVoice.Checked := True;
  MapsLabel := MakeLabel(AIPage, 'Offline maps (AIPortable only - a world overview is always included)', ScaleY(262), True);
  MapsList := TNewCheckListBox.Create(AIPage);
  MapsList.Parent := AIPage.Surface;
  MapsList.Top := ScaleY(280); MapsList.Width := AIPage.SurfaceWidth; MapsList.Height := AIPage.SurfaceHeight - ScaleY(280);
  N := CatInt('maps', 'count');
  for I := 1 to N do begin
    E := Cat('maps', 'm' + IntToStr(I));
    if StrToIntDef(Field(E, 3), 0) > 10000 then
      MapsList.AddCheckBox(Field(E, 2) + ' - takes hours; restarts if interrupted', SizeText(StrToIntDef(Field(E, 3), 0)), 0, False, True, False, True, nil)
    else
      MapsList.AddCheckBox(Field(E, 2), SizeText(StrToIntDef(Field(E, 3), 0)), 0, False, True, False, True, nil);
  end;

  { -- Library content }
  LibPage := CreateCustomPage(AIPage.ID, 'Fill your library', 'Starter packs are hand-picked pages from free archives. Setup downloads each archive and builds the pages.');
  PacksList := TNewCheckListBox.Create(LibPage);
  PacksList.Parent := LibPage.Surface;
  PacksList.Top := 0; PacksList.Width := LibPage.SurfaceWidth; PacksList.Height := ScaleY(172);
  L := Cat('packs', 'list') + ',';
  while Pos(',', L) > 0 do begin
    G := Copy(L, 1, Pos(',', L) - 1);
    L := Copy(L, Pos(',', L) + 1, Length(L));
    PacksList.AddCheckBox(Cat('pack-' + G, 'title') + ' - ' + Cat('pack-' + G, 'desc') + ' (' + Cat('pack-' + G, 'items') + ' items)',
      SizeText(CatInt('pack-' + G, 'mb')), 0, (G <> 'books') and (G <> 'se'), True, False, True, nil);
  end;
  Lbl := MakeLabel(LibPage, 'Every page is a full article. Each pack downloads its source archive and keeps it, so the AI can search it too. ' +
    'None are required - add packs later with Build Starter Library.bat in the Research folder.', ScaleY(178), False);
  Lbl.AutoSize := False; Lbl.WordWrap := True; Lbl.Width := LibPage.SurfaceWidth; Lbl.Height := ScaleY(30);
  { optional library tools - only offered when this PC doesn't have them (see probe.ps1) }
  ChkGit := TNewCheckBox.Create(LibPage); ChkGit.Parent := LibPage.Surface;
  ChkGit.Caption := 'Also read old Word .doc files - installs Git for Windows, which includes antiword (about 300 MB)';
  ChkGit.Top := ScaleY(214); ChkGit.Width := LibPage.SurfaceWidth; ChkGit.Visible := False;
  ChkChrome := TNewCheckBox.Create(LibPage); ChkChrome.Parent := LibPage.Surface;
  ChkChrome.Caption := 'Install Google Chrome - makes the clean one-page recipe PDFs (this PC has no Chrome or Edge)';
  ChkChrome.Top := ScaleY(236); ChkChrome.Width := LibPage.SurfaceWidth; ChkChrome.Visible := False;

  { -- Offline archives }
  ArchPage := CreateCustomPage(LibPage.ID, 'Offline archives',
    'Whole websites saved as one file each - readable in the apps and searchable by the AI. Download as much or as little as you like.');
  MakeLabel(ArchPage, 'English Wikipedia - complete articles', 0, True);
  for I := 0 to 2 do begin
    WikiRadios[I] := TNewRadioButton.Create(ArchPage);
    WikiRadios[I].Parent := ArchPage.Surface;
    WikiRadios[I].Top := ScaleY(17 + I * 18);
    WikiRadios[I].Width := ArchPage.SurfaceWidth;
  end;
  WikiRadios[0].Caption := 'Not now';
  WikiRadios[1].Caption := 'Full text, no pictures - ' + SizeText(CatInt('wiki', 'nopicMB'));
  WikiRadios[2].Caption := 'Full text with pictures - ' + SizeText(CatInt('wiki', 'maxiMB')) + ' (one very large file, needs NTFS)';
  WikiRadios[0].Checked := True;
  WikiNote := MakeLabel(ArchPage, '', ScaleY(72), False);
  WikiNote.AutoSize := False; WikiNote.WordWrap := True; WikiNote.Width := ArchPage.SurfaceWidth; WikiNote.Height := ScaleY(30);
  MakeLabel(ArchPage, 'More archives', ScaleY(108), True);
  ArchList := TNewCheckListBox.Create(ArchPage);
  ArchList.Parent := ArchPage.Surface;
  ArchList.Top := ScaleY(126); ArchList.Width := ArchPage.SurfaceWidth; ArchList.Height := ScaleY(112);
  ArchList.OnClickCheck := @UpdateArchives;
  N := CatInt('archives', 'count');
  G := '';
  for I := 1 to N do begin
    E := Cat('archives', 'a' + IntToStr(I));
    if Field(E, 4) <> G then begin
      G := Field(E, 4);
      ArchList.AddGroup(G, '', 0, nil);
      SetArrayLength(ArchRow, ArchList.Items.Count); ArchRow[ArchList.Items.Count - 1] := 0;
    end;
    ArchList.AddCheckBox(Field(E, 2), SizeText(StrToIntDef(Field(E, 3), 0)), 1, False, True, False, True, nil);
    SetArrayLength(ArchRow, ArchList.Items.Count); ArchRow[ArchList.Items.Count - 1] := I;
  end;
  ArchWhere := MakeLabel(ArchPage, '', ScaleY(242), False);
  ArchWhere.AutoSize := False; ArchWhere.WordWrap := True; ArchWhere.Width := ArchPage.SurfaceWidth; ArchWhere.Height := ScaleY(34);
  ArchWhere.Font.Color := clGrayText;
  for I := 0 to 2 do WikiRadios[I].OnClick := @UpdateArchives;   { only now: ticking a radio runs it }

  { -- Summary }
  { -- Your local area }
  LocalPage := CreateCustomPage(ArchPage.ID, 'Your local area',
    'Pages about the plants, wildlife and fungi seen near you, your weather, and maps - built from iNaturalist and USGS.');
  ChkLocal := TNewCheckBox.Create(LocalPage); ChkLocal.Parent := LocalPage.Surface;
  ChkLocal.Caption := 'Build a Local Area for where I live';
  ChkLocal.Top := 0; ChkLocal.Width := LocalPage.SurfaceWidth; ChkLocal.OnClick := @UpdateLocal;
  Lbl := MakeLabel(LocalPage, 'Where do you live? A town, an address, or a position like 35.59, -82.55', ScaleY(26), False);
  PlaceEdit := TNewEdit.Create(LocalPage); PlaceEdit.Parent := LocalPage.Surface;
  PlaceEdit.Top := ScaleY(44); PlaceEdit.Width := LocalPage.SurfaceWidth - ScaleX(90);
  FindBtn := TNewButton.Create(LocalPage); FindBtn.Parent := LocalPage.Surface;
  FindBtn.Caption := 'Find'; FindBtn.Top := ScaleY(43); FindBtn.Left := LocalPage.SurfaceWidth - ScaleX(80);
  FindBtn.Width := ScaleX(80); FindBtn.Height := ScaleY(23); FindBtn.OnClick := @FindClick;
  PlaceCombo := TNewComboBox.Create(LocalPage); PlaceCombo.Parent := LocalPage.Surface;
  PlaceCombo.Style := csDropDownList; PlaceCombo.Top := ScaleY(72); PlaceCombo.Width := LocalPage.SurfaceWidth;
  PlaceCombo.OnChange := @UpdateLocal;
  PlaceNote := MakeLabel(LocalPage, 'Only the place search (OpenStreetMap), iNaturalist and USGS see it; it is kept in your library, nowhere else.', ScaleY(98), False);
  PlaceNote.AutoSize := False; PlaceNote.WordWrap := True; PlaceNote.Width := LocalPage.SurfaceWidth; PlaceNote.Height := ScaleY(28);
  PlaceNote.Font.Color := clGrayText;
  MakeLabel(LocalPage, 'How far around it', ScaleY(134), False);
  KmCombo := TNewComboBox.Create(LocalPage); KmCombo.Parent := LocalPage.Surface; KmCombo.Style := csDropDownList;
  KmCombo.Top := ScaleY(131); KmCombo.Left := ScaleX(200); KmCombo.Width := ScaleX(200);
  KmCombo.Items.Add('25 km (16 miles)'); KmCombo.Items.Add('50 km (31 miles)'); KmCombo.Items.Add('100 km (62 miles)'); KmCombo.Items.Add('200 km (124 miles)');
  KmCombo.ItemIndex := 1; KmCombo.OnChange := @UpdateLocal;
  MakeLabel(LocalPage, 'Species per group (11 groups)', ScaleY(162), False);
  PerCombo := TNewComboBox.Create(LocalPage); PerCombo.Parent := LocalPage.Surface; PerCombo.Style := csDropDownList;
  PerCombo.Top := ScaleY(159); PerCombo.Left := ScaleX(200); PerCombo.Width := ScaleX(200);
  PerCombo.Items.Add('25 - the most often seen'); PerCombo.Items.Add('50'); PerCombo.Items.Add('100'); PerCombo.Items.Add('200 - very thorough');
  PerCombo.ItemIndex := 2; PerCombo.OnChange := @UpdateLocal;
  TopoLabel := MakeLabel(LocalPage, 'USGS topo maps (US only)', ScaleY(190), False);
  TopoCombo := TNewComboBox.Create(LocalPage); TopoCombo.Parent := LocalPage.Surface; TopoCombo.Style := csDropDownList;
  TopoCombo.Top := ScaleY(187); TopoCombo.Left := ScaleX(200); TopoCombo.Width := ScaleX(200);
  TopoCombo.Items.Add('none'); TopoCombo.Items.Add('5 km around you'); TopoCombo.Items.Add('15 km around you'); TopoCombo.Items.Add('30 km around you');
  TopoCombo.ItemIndex := 2; TopoCombo.OnChange := @UpdateLocal;
  ChkLocalMap := TNewCheckBox.Create(LocalPage); ChkLocalMap.Parent := LocalPage.Surface;
  ChkLocalMap.Caption := 'Add a street map of this area to AIPortable''s offline maps';
  ChkLocalMap.Top := ScaleY(216); ChkLocalMap.Width := LocalPage.SurfaceWidth; ChkLocalMap.Checked := True; ChkLocalMap.OnClick := @UpdateLocal;
  LocalEst := MakeLabel(LocalPage, '', ScaleY(242), False);
  LocalEst.AutoSize := False; LocalEst.WordWrap := True; LocalEst.Width := LocalPage.SurfaceWidth; LocalEst.Height := ScaleY(44);
  UpdateLocal(nil);

  SummaryPage := CreateCustomPage(LocalPage.ID, 'Ready to install', 'Check the sizes and times, then click Install.');
  SumTotals := MakeLabel(SummaryPage, '', 0, True);
  SumMemo := TNewMemo.Create(SummaryPage);
  SumMemo.Parent := SummaryPage.Surface;
  SumMemo.Top := ScaleY(20); SumMemo.Width := SummaryPage.SurfaceWidth; SumMemo.Height := ScaleY(120);
  SumMemo.ReadOnly := True; SumMemo.ScrollBars := ssBoth; SumMemo.WordWrap := False;
  SumMemo.Font.Name := 'Consolas'; SumMemo.Font.Size := 8;
  SumWarn := MakeLabel(SummaryPage, '', ScaleY(146), False);
  SumWarn.AutoSize := False; SumWarn.WordWrap := True; SumWarn.Width := SummaryPage.SurfaceWidth; SumWarn.Height := ScaleY(28);
  RadNow := TNewRadioButton.Create(SummaryPage); RadNow.Parent := SummaryPage.Surface;
  RadNow.Caption := 'Download everything now and wait';
  RadNow.Top := ScaleY(178); RadNow.Width := SummaryPage.SurfaceWidth; RadNow.Checked := True;
  RadLater := TNewRadioButton.Create(SummaryPage); RadLater.Parent := SummaryPage.Surface;
  RadLater.Caption := 'Set up the apps first; fetch Wikipedia in its own window while I use them';
  RadLater.Top := ScaleY(200); RadLater.Width := SummaryPage.SurfaceWidth;
  ChkDesktop := TNewCheckBox.Create(SummaryPage); ChkDesktop.Parent := SummaryPage.Surface;
  ChkDesktop.Caption := 'Put shortcuts on the desktop (the Start menu always gets them)';
  ChkDesktop.Top := ScaleY(230); ChkDesktop.Width := SummaryPage.SurfaceWidth; ChkDesktop.Checked := True;
  ChkWeekly := TNewCheckBox.Create(SummaryPage); ChkWeekly.Parent := SummaryPage.Surface;
  ChkWeekly.Caption := 'Check for new versions once a week when online (only github.com is contacted)';
  ChkWeekly.Top := ScaleY(252); ChkWeekly.Width := SummaryPage.SurfaceWidth; ChkWeekly.Checked := True;

  { /PLANFILE= (unattended installs, tests): the pages and the shortcut choices follow that plan }
  if ExpandConstant('{param:PLANFILE|}') <> '' then LoadPlan(ExpandConstant('{param:PLANFILE|}'));
end;


{ ---------------------------------------------------------------- page flow }
function ShouldSkipPage(PageID: Integer): Boolean;
var KeepChoices: Boolean;
begin
  Result := False;
  KeepChoices := Existing and (ModePage.SelectedValueIndex = 0);
  if PageID = ModePage.ID then begin
    { the folder field already holds the earlier install's folder (UsePreviousAppDir) }
    Existing := FileExists(AddBackslash(WizardDirValue) + 'AI-Research-Suite\plan.ini');
    Result := not Existing;
  end;
  if KeepChoices and ((PageID = wpLicense) or (PageID = PiecesPage.ID) or (PageID = wpSelectDir) or
     (PageID = AIPage.ID) or (PageID = LibPage.ID)) then Result := True;
  if PageID = AIPage.ID then Result := Result or IsApp('none');
  if PageID = LibPage.ID then Result := Result or not HasResearch;
  if PageID = ArchPage.ID then Result := Result or not (HasResearch or IsApp('full')) or KeepChoices;
  if PageID = LocalPage.ID then Result := Result or not HasResearch or KeepChoices;
end;

procedure CurPageChanged(CurPageID: Integer);
var Full: Boolean;
begin
  if (CurPageID = PCPage.ID) and not Probed then begin
    WizardForm.NextButton.Enabled := False;
    PCValues[0].Caption := 'checking (a few seconds)...';
    WizardForm.Repaint;
    RunProbe;
    ShowProbe;
    WizardForm.NextButton.Enabled := True;
  end;
  if CurPageID = AIPage.ID then begin
    FillModels;
    Full := IsApp('full');
    MapsLabel.Visible := Full; MapsList.Visible := Full;
  end;
  if CurPageID = LocalPage.ID then UpdateLocal(nil);
  if CurPageID = ArchPage.ID then UpdateArchives(nil);
  if CurPageID = LibPage.ID then begin
    ChkGit.Visible := Probed and not HaveAntiword;
    ChkChrome.Visible := Probed and not HaveBrowser;
  end;
  if (CurPageID = wpFinished) and IsApp('slim') and not HasResearch then
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 +
      'Offline archives (Wikipedia and more): JustAI searches them while it answers. Download .zim files from library.kiwix.org, ' +
      'then add their folder in Tools/Settings - Library - ZIM archive folders. Or run Setup again and add the Research library.';
  if CurPageID = SummaryPage.ID then begin
    ShowSummary;
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
  end;
end;

function GitCheckoutIn(Dir: String): String;
var Names: array[0..3] of String; I: Integer;
begin
  Result := '';
  Names[0] := 'AIPortable'; Names[1] := 'AIPortable-JustAI'; Names[2] := 'Research'; Names[3] := 'LibraryViewer';
  for I := 0 to 3 do
    if DirExists(AddBackslash(Dir) + Names[I] + '\.git') then Result := Names[I];
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var Dl, Disk: Integer; Lines, FS, G: String;
begin
  Result := True;
  if (CurPageID = ModePage.ID) and Existing then begin
    LoadPlan(AddBackslash(WizardDirValue) + 'AI-Research-Suite\plan.ini');
    if ModePage.SelectedValueIndex = 2 then begin
      if MsgBox('Uninstall the AI Research Suite? You will be asked whether to keep the apps'' program files.', mbConfirmation, MB_YESNO) = IDYES then
        ShellExec('', AddBackslash(WizardDirValue) + 'AI-Research-Suite\uninstall\unins000.exe', '', '', SW_SHOWNORMAL, ewNoWait, Dl);
      ClosingForUninstall := True;
      WizardForm.Close;
      Result := False;
    end;
  end;
  if CurPageID = PiecesPage.ID then
    if IsApp('none') and not HasResearch then begin
      MsgBox('Pick at least one piece to install.', mbError, MB_OK); Result := False;
    end;
  if CurPageID = wpSelectDir then begin
    G := GitCheckoutIn(WizardDirValue);
    if G <> '' then begin
      MsgBox(WizardDirValue + '\' + G + ' is a developer copy (a git checkout). Pick another folder - Setup never installs over one.', mbError, MB_OK);
      Result := False; exit;
    end;
    if Pos(' ', WizardDirValue) > 0 then
      if MsgBox('The folder name has spaces in it. That works, but some tools prefer folders without spaces. Use it anyway?', mbConfirmation, MB_YESNO) = IDNO then Result := False;
    FS := DriveInfo(ExtractFileDrive(WizardDirValue), 4);
    if (FS = 'FAT32') then begin
      MsgBox('This drive uses FAT32, which can''t hold files over 4 GB - AI models and Wikipedia won''t fit. Pick an NTFS drive (or reformat this one as NTFS or exFAT first).', mbError, MB_OK);
      Result := False;
    end;
  end;
  if (CurPageID = LocalPage.ID) and ChkLocal.Checked and not LocalOn then begin
    MsgBox('Type where you live and click Find - or untick "Build a Local Area".', mbError, MB_OK);
    Result := False;
  end;
  if CurPageID = SummaryPage.ID then begin
    Totals(Lines, Dl, Disk);
    if (FreeMB(WizardDirValue) >= 0) and (FreeMB(WizardDirValue) < Disk) then begin
      MsgBox('There isn''t enough free space on ' + ExtractFileDrive(WizardDirValue) + '. Go back and pick another folder or fewer items.', mbError, MB_OK);
      Result := False;
    end else if OllamaRunning then
      MsgBox('Another copy of Ollama is still running. Close it (tray icon - Quit) before the AI app''s setup downloads models, so they go into the suite folder.', mbInformation, MB_OK);
  end;
end;

{ ---------------------------------------------------------------- doing the install }
procedure WritePlan(F: String);
var I: Integer; Maps, Packs, Key: String;
begin
  SetIniString('plan', 'app', AppChoice, F);
  if ChkResearch.Checked or ChkViewer.Checked then SetIniString('plan', 'research', '1', F) else SetIniString('plan', 'research', '0', F);
  if ChkViewer.Checked then SetIniString('plan', 'viewer', '1', F) else SetIniString('plan', 'viewer', '0', F);
  SetIniString('plan', 'tier', IntToStr(SelectedTier), F);
  SetIniString('plan', 'model', Field(ModelEntry(SelectedTier, SelectedModel), 3), F);
  if ChkVoice.Checked then SetIniString('plan', 'voice', '1', F) else SetIniString('plan', 'voice', '0', F);
  Maps := '';
  for I := 0 to MapsList.Items.Count - 1 do
    if MapsList.Checked[I] then begin
      if Maps <> '' then Maps := Maps + ',';
      Maps := Maps + Field(Cat('maps', 'm' + IntToStr(I + 1)), 1);
    end;
  SetIniString('plan', 'maps', Maps, F);
  Packs := ''; Key := Cat('packs', 'list') + ',';
  for I := 0 to PacksList.Items.Count - 1 do begin
    if PacksList.Checked[I] then begin
      if Packs <> '' then Packs := Packs + ',';
      Packs := Packs + Copy(Key, 1, Pos(',', Key) - 1);
    end;
    Key := Copy(Key, Pos(',', Key) + 1, Length(Key));
  end;
  SetIniString('plan', 'packs', Packs, F);
  SetIniString('plan', 'wiki', WikiChoice, F);
  if RadLater.Checked then SetIniString('plan', 'background', '1', F) else SetIniString('plan', 'background', '0', F);
  if ChkWeekly.Checked then SetIniString('plan', 'weekly', '1', F) else SetIniString('plan', 'weekly', '0', F);
  if ChkDesktop.Checked then SetIniString('plan', 'desktop', '1', F) else SetIniString('plan', 'desktop', '0', F);
  SetIniString('plan', 'source', ExpandConstant('{param:SOURCE|}'), F);
  if AmdGpu then SetIniString('plan', 'rocm', '1', F) else SetIniString('plan', 'rocm', '0', F);
  Key := '';
  if ChkGit.Visible and ChkGit.Checked then Key := 'git';
  if ChkChrome.Visible and ChkChrome.Checked then begin if Key <> '' then Key := Key + ','; Key := Key + 'chrome'; end;
  if Key = '' then Key := 'none';
  SetIniString('plan', 'tools', Key, F);
  Key := '';
  if HasResearch or IsApp('full') then
    for I := 0 to ArchList.Items.Count - 1 do
      if (ArchRow[I] > 0) and ArchList.Checked[I] and ArchList.ItemEnabled[I] then begin
        if Key <> '' then Key := Key + ',';
        Key := Key + Field(Cat('archives', 'a' + IntToStr(ArchRow[I])), 1);
      end;
  SetIniString('plan', 'archives', Key, F);
  if LocalOn then begin
    SetIniString('plan', 'local', '1', F);
    SetIniString('plan', 'localName', PlaceCombo.Text, F);
    SetIniString('plan', 'localLat', PlaceLat[PlaceCombo.ItemIndex], F);
    SetIniString('plan', 'localLon', PlaceLon[PlaceCombo.ItemIndex], F);
    SetIniString('plan', 'localCountry', PlaceCC[PlaceCombo.ItemIndex], F);
    SetIniString('plan', 'localKm', IntToStr(ComboNum(KmCombo)), F);
    SetIniString('plan', 'localPerGroup', IntToStr(ComboNum(PerCombo)), F);
    if TopoCount > 0 then SetIniString('plan', 'localTopoKm', IntToStr(ComboNum(TopoCombo)), F) else SetIniString('plan', 'localTopoKm', '0', F);
    if IsApp('full') and ChkLocalMap.Checked then SetIniString('plan', 'localMap', '1', F) else SetIniString('plan', 'localMap', '0', F);
  end else SetIniString('plan', 'local', '0', F);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Suite, Plan, Given, Err, Extra: String; RC, Show: Integer;
begin
  if CurStep = ssPostInstall then begin
    Suite := ExpandConstant('{app}') + '\AI-Research-Suite';
    Plan := Suite + '\plan.ini';
    Given := ExpandConstant('{param:PLANFILE|}');
    if Given <> '' then begin
      CopyFile(Given, Plan, False);
      if ExpandConstant('{param:SOURCE|}') <> '' then SetIniString('plan', 'source', ExpandConstant('{param:SOURCE|}'), Plan);
    end else begin DeleteFile(Plan); WritePlan(Plan); end;
    WizardForm.StatusLabel.Caption := 'Downloading and setting everything up - follow the progress in the AI Research Suite window. This can take a while.';
    if WizardSilent then begin Show := SW_HIDE; Extra := ' -NoPause'; end else begin Show := SW_SHOWNORMAL; Extra := ''; end;
    Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + Suite + '\install.ps1"' + Extra, Suite, Show, ewWaitUntilTerminated, RC);
    InstallSucceeded := GetIniString('state', 'result', '', Suite + '\install-state.ini') = 'ok';
    if not InstallSucceeded then begin
      Err := GetIniString('state', 'error', 'the setup window was closed before it finished', Suite + '\install-state.ini');
      if Err = '' then Err := 'the setup window was closed before it finished';
      SuppressibleMsgBox('Setup did not finish: ' + Err + #13#10#13#10 + 'Run Setup again (or "Check for updates") - it carries on where it stopped. Log: ' +
        GetIniString('state', 'log', Suite + '\logs', Suite + '\install-state.ini'), mbError, MB_OK, IDOK);
    end;
  end;
end;

{ ---------------------------------------------------------------- uninstall }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var RC: Integer; Suite: String;
begin
  if CurUninstallStep = usUninstall then begin
    Suite := ExpandConstant('{app}') + '\AI-Research-Suite';
    if FileExists(Suite + '\update.ps1') then
      if SuppressibleMsgBox('Also remove the apps'' program files (AIPortable / JustAI, the library tools, the viewer)?' + #13#10#13#10 +
         'Your chats, AI models, maps, library and notes are kept in their folders either way - delete those yourself if you don''t need them.',
         mbConfirmation, MB_YESNO, IDNO) = IDYES then
        Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + Suite + '\update.ps1" -Remove -Yes', Suite, SW_HIDE, ewWaitUntilTerminated, RC);
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if ClosingForUninstall then Confirm := False;
end;
