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
;   /DBrandingDir=<path>      wizard bitmaps from tool\make_installer_branding.ps1
;   /DAppDataDir=<rel path>   the app's data folder under %APPDATA%. Derived by
;                             the build script from CompanyName\ProductName in
;                             windows\runner\Runner.rc, because that pair is what
;                             path_provider uses for getApplicationSupportDirectory().
;                             Hardcoding it here let it silently go stale once
;                             ProductName changed, leaving the uninstaller
;                             pointed at a folder that no longer existed.

#ifndef AppVersion
  #error AppVersion must be defined on the command line
#endif
#ifndef BuildDir
  #error BuildDir must be defined on the command line
#endif
#ifndef BrandingDir
  #error BrandingDir must be defined on the command line
#endif
#ifndef AppDataDir
  #error AppDataDir must be defined on the command line
#endif

#define AppName        "Bastak Leads"
#define AppPublisher   "Bastak Instruments"
#define AppExeName     "bastak_leads.exe"

[Setup]
; This GUID identifies the application across versions -- never change it, or
; upgrades will install alongside the old copy instead of replacing it.
AppId={{7B3F1C42-9E5D-4A88-B2E7-5D0C6A14F3B9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppCopyright=Copyright (C) 2026 {#AppPublisher}
VersionInfoVersion={#VersionInfo}
VersionInfoProductName={#AppName}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup

; Default to a per-user install (no admin): {autopf} then resolves to
; %LOCALAPPDATA%\Programs. This is what makes silent auto-updates seamless — a
; per-user install upgrades without a UAC prompt. The user can still elevate to
; an all-users install via the dialog; such installs will prompt for elevation
; on update. `commandline` lets the updater pass the same scope on silent runs.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

; WizardStyle=modern defaults DisableWelcomePage to yes, which would drop the
; only page that shows the full-height brand panel. Turn it back on, and let
; the user pick the install folder rather than silently using the default.
DisableWelcomePage=no
DisableDirPage=no

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

; --- Branding ---------------------------------------------------------------
; Wizard artwork generated from assets\ by tool\make_installer_branding.ps1.
; Several sizes of each are supplied and Inno picks the one matching the user's
; DPI, so the logo stays sharp on high-DPI displays instead of being upscaled.
WizardStyle=modern
WizardImageFile={#BrandingDir}\WizardImage-*.bmp
WizardSmallImageFile={#BrandingDir}\WizardSmallImage-*.bmp
; The large image is a full-bleed brand panel, so let it fill rather than sit
; letterboxed on a grey background.
WizardImageStretch=yes
WizardSizePercent=100

; Use Restart Manager to shut the app down if it is running during an upgrade,
; rather than failing with "file in use". RestartApplications is off because the
; silent auto-update runs with /NORESTART (which disables RM's app restart) and
; relaunches explicitly via the WizardSilent [Run] entry below — keeping the
; relaunch deterministic and avoiding a double launch.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
; Say what the app actually is, rather than the stock "This will install...".
WelcomeLabel2=This will install [name/ver] on your computer.%n%nBastak Leads finds grain, flour and milling leads and tenders, scores them, and keeps them in a local database on this PC. Nothing leaves the device.%n%nIt is recommended that you close all other applications before continuing.

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
; Interactive install: offer a "Launch" checkbox on the finished page.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
; Silent install (the auto-updater path): relaunch the app so a background
; update reopens it. Only fires under /SILENT or /VERYSILENT.
Filename: "{app}\{#AppExeName}"; Flags: nowait runasoriginaluser; Check: WizardSilent

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
