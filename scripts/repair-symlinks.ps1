param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$ProjectRoot = 'D:\Kemu'
$SourceRoot  = Join-Path $ProjectRoot 'emulator'
$BuildRoot   = Join-Path $ProjectRoot 'out\kemu-windows-x86_64'

# ---- 1. enable the privilege that is already in this token ----
if (-not ('Kemu.TokenPriv' -as [type])) {
    Add-Type -Namespace Kemu -Name TokenPriv -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
struct LUID { public uint LowPart; public int HighPart; }

[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }

[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
struct TOKEN_PRIVILEGES { public uint Count; public LUID_AND_ATTRIBUTES Privileges; }

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
static extern bool LookupPrivilegeValue(string systemName, string name, out LUID luid);

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
static extern bool OpenProcessToken(IntPtr processHandle, uint access, out IntPtr token);

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
static extern bool AdjustTokenPrivileges(IntPtr tokenHandle, bool disableAll,
    ref TOKEN_PRIVILEGES newState, uint bufferLength, IntPtr previousState, out uint returnLength);

[System.Runtime.InteropServices.DllImport("kernel32.dll")]
static extern IntPtr GetCurrentProcess();

public static bool Enable(string privilegeName) {
    const uint TOKEN_ADJUST_PRIVILEGES = 0x0020, TOKEN_QUERY = 0x0008, SE_PRIVILEGE_ENABLED = 0x00000002;
    LUID luid;
    if (!LookupPrivilegeValue(null, privilegeName, out luid))
        throw new Exception("LookupPrivilegeValue failed, Win32=" + System.Runtime.InteropServices.Marshal.GetLastWin32Error());
    IntPtr token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
        throw new Exception("OpenProcessToken failed, Win32=" + System.Runtime.InteropServices.Marshal.GetLastWin32Error());
    TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
    tp.Count = 1;
    tp.Privileges.Luid = luid;
    tp.Privileges.Attributes = SE_PRIVILEGE_ENABLED;
    uint ret;
    AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, out ret);
    int err = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
    if (err == 1300) return false;   // ERROR_NOT_ALL_ASSIGNED: privilege not in this token
    if (err != 0) throw new Exception("AdjustTokenPrivileges failed, Win32=" + err);
    return true;
}
'@
}

if (-not [Kemu.TokenPriv]::Enable('SeCreateSymbolicLinkPrivilege')) {
    throw 'SeCreateSymbolicLinkPrivilege is NOT in this token. Run from an elevated window, or enable Developer Mode / grant the user right first.'
}
$check = (whoami /priv) | Where-Object { $_ -match 'SeCreateSymbolicLinkPrivilege' }
if ($check -notmatch 'Enabled') { throw "privilege still not enabled in child processes: $check" }
Write-Output 'privilege enabled'

# ---- 2. enumerate repos ----
$projects = Get-Content -LiteralPath (Join-Path $SourceRoot '.repo\project.list') | Where-Object { $_ }
$repos = foreach ($p in $projects) {
    $full = Join-Path $SourceRoot ($p -replace '/', '\')
    if (Test-Path -LiteralPath $full -PathType Container) { $full }
}

function Get-BrokenLinks([string]$repo) {
    git -C $repo ls-files -s | Where-Object { $_ -like '120000 *' } | ForEach-Object {
        $path = ($_ -split '\s+', 4)[3]
        $full = Join-Path $repo ($path -replace '/', '\')
        if (Test-Path -LiteralPath $full) {
            if ((Get-Item -LiteralPath $full -Force).LinkType -ne 'SymbolicLink') { $full }
        }
    }
}

# ---- 3. local core.symlinks=true (system gitconfig stays untouched) ----
$targets = foreach ($r in $repos) {
    if ((Get-BrokenLinks $r).Count -gt 0) {
        git -C $r config core.symlinks true
        $r
    }
}
"repos to repair: $($targets.Count)"

# ---- 4. delete the mis-materialized files ----
$broken = foreach ($r in $targets) { Get-BrokenLinks $r }
"broken files: $($broken.Count)"
if ($DryRun) { $broken | Select-Object -First 30; Write-Output 'DryRun: nothing changed.'; return }
foreach ($f in $broken) { Remove-Item -LiteralPath $f -Force }

# ---- 5. re-checkout from the local object stores (offline) ----
foreach ($r in $targets) {
    git -C $r checkout -- .
    if ($LASTEXITCODE) { throw "git checkout failed in $r" }
}

# ---- 6. verify ----
$remaining = foreach ($r in $targets) { Get-BrokenLinks $r }
if ($remaining.Count -gt 0) { $remaining | Select-Object -First 20; throw "$($remaining.Count) entries still not symlinks." }

foreach ($probe in 'prebuilts\clang\host\windows-x86\clang-r596125\bin\clang-cl.exe',
                   'prebuilts\android-emulator-build\qt\windows-x86_64\include',
                   'external\qemu\android\emu\adb\interface\src\android\emulation\AdbHostListener.h') {
    $f = Join-Path $SourceRoot $probe
    $i = Get-Item -LiteralPath $f -Force
    if ($i.LinkType -ne 'SymbolicLink') { throw "not a symlink: $probe" }
    Write-Output "OK  $probe -> $($i.Target -join '')"
}

$dirty = 0
foreach ($r in $repos) { if (git -C $r status --porcelain) { $dirty++; Write-Output "dirty: $r" } }
"repos with dirty worktree: $dirty"

# ---- 7. drop the poisoned CMake cache ----
if (Test-Path -LiteralPath $BuildRoot) { Remove-Item -LiteralPath $BuildRoot -Recurse -Force }
Write-Output 'Repair done. run: build-emulator.ps1'