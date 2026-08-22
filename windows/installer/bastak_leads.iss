; Inno Setup script for Bastak Leads (Windows x64).
;
; Do not run this directly -- use tool\build_windows_installer.ps1, which builds
; the Flutter release bundle first and passes AppVersion / BuildDir in.
;
; Requires these to be defined on the ISCC command line:
;   /DAppVersion=2.1.1        product version shown in the wizard
;   /DVersionInfo=2.1.1.2     four-part version stamped into setup.exe
;   /DBuildDir=<path>         the built Release folder to package
;   /DOutputDir=<path>        where to drop the finished installer

#ifndef AppVersion
  #error AppVersion must be defined on the command line
#endif
#ifndef BuildDir
  #error BuildDir must be defined on the command line
#endif

#define AppName        "Bastak Leads"
#define AppPublisher   "Bastak"
#define AppExeName     "bastak_leads.exe"
; Data directory used by path_provider's getApplicationSupportDirectory(),
; derived from the exe's CompanyName/ProductName in windows/runner/Runner.rc.
#define AppDataDir     "com.bastak\bastak_leads"

[Setup]
; This GUID identifies the application across versions -- never change it, or
; upgrades will install alongside the old copy instead of replacing it.
AppId={{7B3F1C42-9E5D-4A88-B2E7-5D0C6A14F3B9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#VersionInfo}
VersionInfoProductName={#AppName}

; Let the user choose "just me" (no admin) or "all users" (admin prompt).
; {autopf} then resolves to %LOCALAPPDATA%\Programs or Program Files to match.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

; The Flutter engine is x64-only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

OutputDir={#OutputDir}
OutputBaseFilename=bastak_leads-{#AppVersion}-windows-x64-setup
SetupIconFile={#SourcePath}\..\runner\resources\app_icon.ico
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Use Restart Manager to shut the app down if it is running during an upgrade,
; rather than failing with "file in use".
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Recursively package the entire Flutter release bundle: the exe, data\ (AOT
; image, ICU data, assets), the engine + plugin DLLs, and the bundled Visual
; C++ runtime that windows\CMakeLists.txt copies in.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
{ On uninstall, offer to remove the local SQLite database and settings. This is
  opt-in and defaults to No, so an uninstall/reinstall cycle keeps the user's
  leads by default.

  Use SuppressibleMsgBox rather than MsgBox: a plain MsgBox is not suppressed
  under /VERYSILENT /SUPPRESSMSGBOXES and does not honour MB_DEFBUTTON2, which
  meant an unattended uninstall silently destroyed the user's database. The
  trailing IDNO is the answer used whenever message boxes are suppressed. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{userappdata}\{#AppDataDir}');
    if DirExists(DataDir) then
    begin
      if SuppressibleMsgBox('Also delete your saved leads, database and settings?' + #13#10 + #13#10
                + DataDir + #13#10 + #13#10
                + 'Choose No to keep your data for a future reinstall.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
        DelTree(DataDir, True, True, True);
    end;
  end;
end;
