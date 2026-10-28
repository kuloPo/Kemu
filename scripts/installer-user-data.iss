; Included in the published installer script. No cleanup executable is needed.
[Code]
const
  INVALID_HANDLE_VALUE = $FFFFFFFFFFFFFFFF;

type
  TCleanupHandles = array of THandle;
  TCleanupAttributes = record
    Attributes: LongWord;
    ReparseTag: LongWord;
  end;

function CleanupOpenFile(Name: String; Access, Share: LongWord; Security: NativeUInt;
  Creation, Flags: LongWord; Template: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';
function CleanupCloseHandle(Handle: THandle): Bool;
  external 'CloseHandle@kernel32.dll stdcall';
function CleanupGetAttributes(Name: String): LongWord;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function CleanupHandleAttributes(Handle: THandle; InfoClass: Integer;
  var Info: TCleanupAttributes; Size: LongWord): Bool;
  external 'GetFileInformationByHandleEx@kernel32.dll stdcall';
function CleanupMarkDeleted(Handle: THandle; InfoClass: Integer;
  var DeleteFile: Byte; Size: LongWord): Bool;
  external 'SetFileInformationByHandle@kernel32.dll stdcall';

procedure CleanupRequire(Condition: Boolean; const MessageText: String);
begin
  if not Condition then RaiseException(MessageText);
end;

procedure CleanupCloseAll(var Handles: TCleanupHandles);
var I: Integer;
begin
  for I := GetArrayLength(Handles) - 1 downto 0 do
    CleanupCloseHandle(Handles[I]);
  SetArrayLength(Handles, 0);
end;

function CleanupAttributesOf(const Path: String): LongWord;
var Error: LongWord;
begin
  Result := CleanupGetAttributes(Path);
  if Result = $FFFFFFFF then begin
    Error := DLLGetLastError;
    CleanupRequire((Error = 2) or (Error = 3), 'Cannot inspect: ' + Path);
  end;
end;

function CleanupAbsolutePath(const Path: String): Boolean;
var Drive: String;
begin
  Drive := ExtractFileDrive(Path);
  Result := (Drive <> '') and (Length(Path) > Length(Drive)) and
    (Copy(Path, Length(Drive) + 1, 1) = '\') and
    (Copy(Path, 1, 4) <> '\\?\') and (Copy(Path, 1, 4) <> '\\.\') and
    (Pos('*', Path) = 0) and (Pos('?', Path) = 0) and
    (Pos(#0, Path) = 0) and (Pos(#13, Path) = 0) and (Pos(#10, Path) = 0) and
    (Pos(':', Copy(Path, Length(Drive) + 1, Length(Path))) = 0) and
    (CompareText(ExpandFileName(Path), Path) = 0);
end;

// Keep every existing ancestor open without FILE_SHARE_DELETE to prevent
// renaming it or substituting a junction while cleanup is in progress.
procedure CleanupPinDirectory(const Directory: String; var Handles: TCleanupHandles);
var Parent: String; Handle: THandle; Info: TCleanupAttributes; Count: Integer;
begin
  Parent := ExtractFileDir(Directory);
  if (Parent <> '') and (CompareText(Parent, Directory) <> 0) then
    CleanupPinDirectory(Parent, Handles);
  Handle := CleanupOpenFile(Directory, $80, 3, 0, 3, $02200000, 0);
  CleanupRequire(Handle <> INVALID_HANDLE_VALUE, 'Cannot access directory: ' + Directory);
  Count := GetArrayLength(Handles);
  SetArrayLength(Handles, Count + 1);
  Handles[Count] := Handle;
  CleanupRequire(CleanupHandleAttributes(Handle, 9, Info, SizeOf(Info)),
    'Cannot inspect directory: ' + Directory);
  CleanupRequire(((Info.Attributes and $10) <> 0) and
    ((Info.Attributes and $400) = 0), 'Linked directories cannot be cleaned: ' + Directory);
end;

function CleanupDiskPath(const DataRoot: String): String;
var
  RecordPath: String;
  Lines: TArrayOfString;
  Attributes: LongWord;
  Directories: TCleanupHandles;
begin
  Result := DataRoot + '\avd\kemu.avd\userdata-qemu.img';
  RecordPath := DataRoot + '\avd\storage-location.txt';
  Attributes := CleanupAttributesOf(RecordPath);
  if Attributes = $FFFFFFFF then exit;
  CleanupRequire((Attributes and ($10 or $400)) = 0,
    'The disk location record must be a regular file.');
  try
    CleanupPinDirectory(ExtractFileDir(RecordPath), Directories);
    CleanupRequire(LoadStringsFromFile(RecordPath, Lines), 'Cannot read the disk location record.');
  finally
    CleanupCloseAll(Directories);
  end;
  CleanupRequire(GetArrayLength(Lines) = 2, 'Invalid disk location record.');
  CleanupRequire(Lines[0] = '1', 'Unsupported disk location record.');
  Result := Lines[1];
  CleanupRequire(CleanupAbsolutePath(Result) and
    (CompareText(ExtractFileName(Result), 'userdata-qemu.img') = 0),
    'Invalid virtual disk path.');
end;

function CleanupLockDisk(const Path: String; Required: Boolean;
  var Directories: TCleanupHandles): THandle;
var Attributes: LongWord; Info: TCleanupAttributes; Valid: Boolean;
begin
  Result := INVALID_HANDLE_VALUE;
  Attributes := CleanupAttributesOf(Path);
  if Attributes = $FFFFFFFF then begin
    CleanupRequire(not Required, 'The virtual disk is unavailable. Reconnect its drive: ' + Path);
    exit;
  end;
  CleanupPinDirectory(ExtractFileDir(Path), Directories);
  Result := CleanupOpenFile(Path, $80010000, 0, 0, 3, $00200000, 0);
  CleanupRequire(Result <> INVALID_HANDLE_VALUE,
    'Cannot open the virtual disk exclusively. Close Kemu and try again: ' + Path);
  Valid := CleanupHandleAttributes(Result, 9, Info, SizeOf(Info));
  if not Valid or
    ((Info.Attributes and ($10 or $400)) <> 0) then begin
    CleanupCloseHandle(Result);
    Result := INVALID_HANDLE_VALUE;
    RaiseException('The virtual disk must be a regular file: ' + Path);
  end;
end;

procedure CleanupDeleteDisk(var Handle: THandle);
var DeleteFlag: Byte;
begin
  if Handle = INVALID_HANDLE_VALUE then exit;
  DeleteFlag := 1;
  CleanupRequire(CleanupMarkDeleted(Handle, 4, DeleteFlag, 1),
    'Cannot delete the virtual disk. Check its permissions and try again.');
  CleanupCloseHandle(Handle);
  Handle := INVALID_HANDLE_VALUE;
end;

procedure CleanupUserData(const LocalData, ExpectedDisk, SettingsKey: String);
var
  DataRoot, Disk, DefaultDisk: String;
  Ancestors, DiskDirectories: TCleanupHandles;
  Image, DefaultImage, RecordHandle: THandle;
begin
  DataRoot := LocalData + '\Kemu\Kemu';
  CleanupRequire(CleanupAbsolutePath(DataRoot), 'Invalid user data directory.');
  Image := INVALID_HANDLE_VALUE;
  DefaultImage := INVALID_HANDLE_VALUE;
  RecordHandle := INVALID_HANDLE_VALUE;
  try
    CleanupPinDirectory(LocalData, Ancestors);
    if CleanupAttributesOf(DataRoot) <> $FFFFFFFF then begin
      CleanupPinDirectory(DataRoot, Ancestors);
      if CleanupAttributesOf(DataRoot + '\avd\storage-location.txt') <> $FFFFFFFF then begin
        CleanupPinDirectory(DataRoot + '\avd', DiskDirectories);
        RecordHandle := CleanupOpenFile(DataRoot + '\avd\storage-location.txt',
          $80000000, 1, 0, 3, $00200000, 0);
        CleanupRequire(RecordHandle <> INVALID_HANDLE_VALUE, 'Cannot lock the disk location record.');
      end;
      Disk := CleanupDiskPath(DataRoot);
      CleanupRequire(CompareText(Disk, ExpectedDisk) = 0,
        'The virtual disk location changed. Restart the uninstaller.');
      DefaultDisk := DataRoot + '\avd\kemu.avd\userdata-qemu.img';
      Image := CleanupLockDisk(Disk, CompareText(Disk, DefaultDisk) <> 0, DiskDirectories);
      if CompareText(Disk, DefaultDisk) <> 0 then
        DefaultImage := CleanupLockDisk(DefaultDisk, False, DiskDirectories);
      CleanupDeleteDisk(Image);
      CleanupDeleteDisk(DefaultImage);
      if RecordHandle <> INVALID_HANDLE_VALUE then begin
        CleanupCloseHandle(RecordHandle);
        RecordHandle := INVALID_HANDLE_VALUE;
      end;
      CleanupCloseAll(DiskDirectories);
      // DelTree does not traverse directory reparse points. Keep the root
      // pinned until its contents are removed, including the encryption key.
      CleanupRequire(DelTree(DataRoot + '\*', False, True, True),
        'Some user data could not be removed. Close Kemu and try again: ' + DataRoot);
    end;
    if RegKeyExists(HKCU, SettingsKey) then
      CleanupRequire(RegDeleteKeyIncludingSubkeys(HKCU, SettingsKey),
        'Cannot remove the current account settings.');
  finally
    if Image <> INVALID_HANDLE_VALUE then CleanupCloseHandle(Image);
    if DefaultImage <> INVALID_HANDLE_VALUE then CleanupCloseHandle(DefaultImage);
    if RecordHandle <> INVALID_HANDLE_VALUE then CleanupCloseHandle(RecordHandle);
    CleanupCloseAll(DiskDirectories);
    CleanupCloseAll(Ancestors);
  end;
  RemoveDir(DataRoot);
  RemoveDir(LocalData + '\Kemu');
end;

// Selection is collected before uninstallation. Deletion only begins after
// Inno Setup's own confirmation and mutex checks have completed.
var
  RemoveKemuUserData: Boolean;
  KemuCleanupDisk: String;

function InitializeUninstall: Boolean;
var
  Form: TSetupForm;
  Description: TNewStaticText;
  Paths: TNewMemo;
  RemoveData: TNewCheckBox;
  ContinueButton, CancelButton: TNewButton;
  DataRoot, Problem: String;
begin
  Result := True;
  RemoveKemuUserData := False;
  if UninstallSilent then exit;
  DataRoot := ExpandConstant('{localappdata}\Kemu\Kemu');
  Problem := '';
  try
    KemuCleanupDisk := CleanupDiskPath(DataRoot);
  except
    Problem := GetExceptionMessage;
  end;
  Form := CreateCustomForm(520, 325, True, True);
  try
    Form.Caption := 'Uninstall Kemu';
    Description := TNewStaticText.Create(Form);
    Description.Parent := Form;
    Description.SetBounds(ScaleX(20), ScaleY(16), ScaleX(480), ScaleY(58));
    Description.AutoSize := False;
    Description.WordWrap := True;
    Description.Caption := 'Your Android apps, files and Kemu settings are kept by default.'#13#10 +
      'Optional cleanup applies to the Windows account running this uninstaller: ' + GetUserNameString;
    Paths := TNewMemo.Create(Form);
    Paths.Parent := Form;
    Paths.SetBounds(ScaleX(20), ScaleY(82), ScaleX(480), ScaleY(112));
    Paths.ReadOnly := True;
    Paths.ScrollBars := ssBoth;
    Paths.WordWrap := False;
    Paths.Text := 'User data: ' + DataRoot + #13#10 + 'Virtual disk: ' + KemuCleanupDisk;
    if Problem <> '' then Paths.Text := Paths.Text + #13#10 + Problem;
    RemoveData := TNewCheckBox.Create(Form);
    RemoveData.Parent := Form;
    RemoveData.SetBounds(ScaleX(20), ScaleY(206), ScaleX(480), ScaleY(22));
    RemoveData.Caption := 'Delete user data, including Android apps, files and settings';
    RemoveData.Checked := False;
    RemoveData.Enabled := Problem = '';
    Description := TNewStaticText.Create(Form);
    Description.Parent := Form;
    Description.SetBounds(ScaleX(20), ScaleY(234), ScaleX(480), ScaleY(36));
    Description.AutoSize := False;
    Description.WordWrap := True;
    Description.Caption := 'This cannot be undone. Other files beside a moved virtual disk are kept.';
    ContinueButton := TNewButton.Create(Form);
    ContinueButton.Parent := Form;
    ContinueButton.SetBounds(ScaleX(310), ScaleY(282), ScaleX(90), ScaleY(26));
    ContinueButton.Caption := 'Continue';
    ContinueButton.ModalResult := mrOK;
    ContinueButton.Default := True;
    CancelButton := TNewButton.Create(Form);
    CancelButton.Parent := Form;
    CancelButton.SetBounds(ScaleX(410), ScaleY(282), ScaleX(90), ScaleY(26));
    CancelButton.Caption := 'Cancel';
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    Result := Form.ShowModal = mrOK;
    RemoveKemuUserData := Result and RemoveData.Checked;
  finally
    Form.Free;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and RemoveKemuUserData then begin
    try
      CleanupUserData(ExpandConstant('{localappdata}'), KemuCleanupDisk, 'Software\Kemu\Kemu');
    except
      SuppressibleMsgBox('User data cleanup could not finish. Uninstallation has stopped.'#13#10#13#10 +
        GetExceptionMessage + #13#10#13#10 +
        'Some files may already have been removed. Resolve the problem and retry, or leave ' +
        'the delete-data option unchecked.', mbError, MB_OK, IDOK);
      Abort;
    end;
  end;
end;
