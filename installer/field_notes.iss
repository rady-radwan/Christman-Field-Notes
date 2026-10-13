; Inno Setup script for Christman Field Notes (Windows).
; Built by GitHub Actions: ISCC.exe /DAppVersion=x.y.z installer/field_notes.iss

#define AppName "Christman Field Notes"
#define AppExe "christman_field_notes.exe"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{8F3C2A51-6B7E-4D2A-9C41-1F5E7B2D9A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=The Christman Company
DefaultDirName={autopf}\Christman Field Notes
DefaultGroupName=Christman Field Notes
DisableProgramGroupPage=yes
; Installs for the current user without needing admin rights.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\dist
OutputBaseFilename=ChristmanFieldNotes-Setup-{#AppVersion}
SetupIconFile=..\assets\icon\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
