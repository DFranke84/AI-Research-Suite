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
  TierIds: array[0..4] of Integer;
  TierCount: Integer;

  ModePage: TInputOptionWizardPage;
  PCPage, PiecesPage, AIPage, LibPage, SummaryPage: TWizardPage;
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
procedure AddRow(var Lines: String; var DlMB, DiskMB: Integer; Name: String; Dl, Disk: Integer);
var Pad: String;
begin
  DlMB := DlMB + Dl; DiskMB := DiskMB + Disk;
  Pad := Name;
  while Length(Pad) < 46 do Pad := Pad + ' ';
  Lines := Lines + Pad + Format('%10s %10s %14s', [SizeText(Dl), SizeText(Disk), TimeText(Dl)]) + #13#10;
end;

procedure Totals(var Lines: String; var DlMB, DiskMB: Integer);
var I, M, PacksMB, PacksN, MapsMB: Integer; E, Key, Pad: String;
begin
  Lines := ''; DlMB := 0; DiskMB := 0;
  Pad := 'Item';
  while Length(Pad) < 46 do Pad := Pad + ' ';
  Lines := Pad + Format('%10s %10s %14s', ['Download', 'On disk', 'Time']) + #13#10;
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
    if WikiChoice = 'nopic' then AddRow(Lines, DlMB, DiskMB, 'Wikipedia - full text, no pictures', CatInt('wiki', 'nopicMB'), CatInt('wiki', 'nopicMB'));
    if WikiChoice = 'maxi' then AddRow(Lines, DlMB, DiskMB, 'Wikipedia - complete, with pictures', CatInt('wiki', 'maxiMB'), CatInt('wiki', 'maxiMB'));
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
  Warn := '';
  if (Free >= 0) and (Free < Disk) then Warn := 'Not enough space: ' + ExtractFileDrive(WizardDirValue) + ' has ' + SizeText(Free) + ' free. Go back and pick another folder or fewer items.'
  else if Free >= 0 then Warn := SizeText(Free - Disk) + ' will be left free afterwards. Sizes are estimates; the downloads are checked as they go.';
  SumWarn.Caption := Warn;
  RadLater.Enabled := WikiChoice <> 'none';
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
  MakeLabel(AIPage, 'Chat model', ScaleY(74), True);
  ModelPanel := TPanel.Create(AIPage);
  ModelPanel.Parent := AIPage.Surface;
  ModelPanel.BevelOuter := bvNone; ModelPanel.ParentBackground := False; ModelPanel.Color := clWindow;
  ModelPanel.Top := ScaleY(92); ModelPanel.Width := AIPage.SurfaceWidth; ModelPanel.Height := ScaleY(4 * 30);
  for I := 0 to MaxModels - 1 do begin
    ModelRadios[I] := TNewRadioButton.Create(AIPage);
    ModelRadios[I].Parent := ModelPanel;
    ModelRadios[I].Top := ScaleY(I * 30);
    ModelRadios[I].Width := ScaleX(165);
    case I of
      0: E := 'Survival - practical how-to answers (recommended)';
      1: E := 'General - an all-rounder for everyday questions';
      2: E := 'Reasoning - step by step; slower, better on hard problems';
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
    MapsList.AddCheckBox(Field(E, 2), SizeText(StrToIntDef(Field(E, 3), 0)), 0, False, True, False, True, nil);
  end;

  { -- Library content }
  LibPage := CreateCustomPage(AIPage.ID, 'Fill your library', 'Starter packs are hand-picked pages from free archives. Setup downloads each archive and builds the pages.');
  PacksList := TNewCheckListBox.Create(LibPage);
  PacksList.Parent := LibPage.Surface;
  PacksList.Top := 0; PacksList.Width := LibPage.SurfaceWidth; PacksList.Height := ScaleY(160);
  L := Cat('packs', 'list') + ',';
  while Pos(',', L) > 0 do begin
    G := Copy(L, 1, Pos(',', L) - 1);
    L := Copy(L, Pos(',', L) + 1, Length(L));
    PacksList.AddCheckBox(Cat('pack-' + G, 'title') + ' - ' + Cat('pack-' + G, 'desc') + ' (' + Cat('pack-' + G, 'items') + ' items)',
      SizeText(CatInt('pack-' + G, 'mb')), 0, (G <> 'books') and (G <> 'se'), True, False, True, nil);
  end;
  MakeLabel(LibPage, 'Offline Wikipedia - readable in the apps and searchable by the AI', ScaleY(170), True);
  for I := 0 to 2 do begin
    WikiRadios[I] := TNewRadioButton.Create(LibPage);
    WikiRadios[I].Parent := LibPage.Surface;
    WikiRadios[I].Top := ScaleY(190 + I * 22);
    WikiRadios[I].Width := LibPage.SurfaceWidth;
  end;
  WikiRadios[0].Caption := 'None for now (you can add one later with Get Archives)';
  WikiRadios[1].Caption := 'Full text, no pictures - ' + SizeText(CatInt('wiki', 'nopicMB'));
  WikiRadios[2].Caption := 'Complete, with pictures - ' + SizeText(CatInt('wiki', 'maxiMB')) + ' (one very large file, needs NTFS)';
  WikiRadios[0].Checked := True;

  { -- Summary }
  SummaryPage := CreateCustomPage(LibPage.ID, 'Ready to install', 'Check the sizes and times, then click Install.');
  SumTotals := MakeLabel(SummaryPage, '', 0, True);
  SumMemo := TNewMemo.Create(SummaryPage);
  SumMemo.Parent := SummaryPage.Surface;
  SumMemo.Top := ScaleY(20); SumMemo.Width := SummaryPage.SurfaceWidth; SumMemo.Height := ScaleY(120);
  SumMemo.ReadOnly := True; SumMemo.ScrollBars := ssVertical;
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
