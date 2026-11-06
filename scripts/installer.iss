#if !FileExists(AddBackslash(ReleaseDir) + "NOTICE.txt") || !FileExists(AddBackslash(ReleaseDir) + "NOTICE.csv")
  #error Missing host component notices. Build and install the emulator before packaging.
#endif
#if !FileExists(AddBackslash(ReleaseDir) + "legal\licenses.html") || !FileExists(AddBackslash(ReleaseDir) + "legal\sources.html") || !FileExists(AddBackslash(ReleaseDir) + "legal\TRADEMARKS.txt")
  #error Missing Kemu license, source or trademark information.
#endif
#if !FileExists(AddBackslash(ReleaseDir) + "legal\qt-sources.html") || !FileExists(AddBackslash(ReleaseDir) + "legal\Qt-6.5.3-THIRD-PARTY.txt") || !FileExists(AddBackslash(ReleaseDir) + "legal\QtWebEngine-6.5.3-Chromium-THIRD-PARTY.txt")
  #error Missing Qt notices or source information. Install the kemu-legal component before packaging.
#endif
#if !FileExists(AddBackslash(ReleaseDir) + "legal\licenses\Kemu-GPL-2.0.txt") || !FileExists(AddBackslash(ReleaseDir) + "legal\licenses\LICENSE.GPLv2") || !FileExists(AddBackslash(ReleaseDir) + "legal\licenses\LICENSE.GPLv3") || !FileExists(AddBackslash(ReleaseDir) + "legal\licenses\LICENSE.LGPLv21") || !FileExists(AddBackslash(ReleaseDir) + "legal\licenses\LICENSE.LGPLv3") || !FileExists(AddBackslash(ReleaseDir) + "legal\licenses\LICENSE.APACHE2")
  #error Missing full license texts. Install the kemu-legal component before packaging.
#endif
#if !FileExists(AddBackslash(ReleaseDir) + "legal\android\index.html")
  #error Missing Android notices. Export notices from the Android build with copy_imgs.sh.
#endif
#if DirExists(AddBackslash(ReleaseDir) + "platform-tools") && !FileExists(AddBackslash(ReleaseDir) + "platform-tools\NOTICE.txt")
  #error Missing platform-tools notices. Include NOTICE.txt from the same platform-tools package.
#endif

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
