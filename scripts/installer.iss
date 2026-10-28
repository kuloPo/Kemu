[Setup]
AppId=Kemu
AppName=Kemu
AppVersion={#AppVersion}
AppPublisher=Kemu
DefaultDirName={commonpf64}\Kemu
DefaultGroupName=Kemu
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
SetupArchitecture=x64
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/ultra64
SolidCompression=yes
LZMADictionarySize=262144
LZMANumFastBytes=273
DiskSpanning=no
Uninstallable=yes
CreateUninstallRegKey=yes
UninstallDisplayIcon={uninstallexe}
CloseApplications=yes
RestartApplications=no
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Kemu"; Filename: "{app}\Kemu.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\Kemu"; Filename: "{app}\Kemu.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Kemu.exe"; WorkingDir: "{app}"; Description: "Launch Kemu"; Flags: nowait postinstall skipifsilent unchecked
