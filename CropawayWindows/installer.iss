; Cropaway Windows Installer
; Built with Inno Setup 6 - https://jrsoftware.org/isinfo.php

#define MyAppName "Cropaway"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Cropaway"
#define MyAppURL "https://github.com/mhadifilms/cropaway"
#define MyAppExeName "Cropaway.exe"

[Setup]
AppId={{B4F2A1C3-D5E6-4F78-9A0B-1C2D3E4F5A6B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=CropawaySetup-{#MyAppVersion}
SetupIconFile=CropawayWindows\Resources\cropaway.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "fileassoc"; Description: "Associate video files with Cropaway"; GroupDescription: "File associations:"; Flags: unchecked

[Files]
; Main application and all .NET runtime files
Source: "publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; File associations (optional)
Root: HKA; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: string; ValueName: "Cropaway.Video"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: string; ValueName: "Cropaway.Video"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: string; ValueName: "Cropaway.Video"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: string; ValueName: "Cropaway.Video"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\Cropaway.Video"; ValueType: string; ValueName: ""; ValueData: "Cropaway Video"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\Cropaway.Video\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\Cropaway.Video\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandirs; Name: "{localappdata}\Cropaway"
