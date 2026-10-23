param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$ProjectRoot = 'D:\Kemu'
$SourceRoot  = Join-Path $ProjectRoot 'emulator'

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

# Repo-relative paths of index symlinks that exist on disk but are not symlinks.
function Get-BrokenLinks([string]$repo) {
    git -C $repo -c core.quotePath=false ls-files -s | Where-Object { $_ -like '120000 *' } | ForEach-Object {
        $path = ($_ -split '\s+', 4)[3]
        $full = Join-Path $repo ($path -replace '/', '\')
        if (Test-Path -LiteralPath $full) {
            if ((Get-Item -LiteralPath $full -Force).LinkType -ne 'SymbolicLink') { $path }
        }
    }
}

# ---- 3. find interrupted checkouts ----
# git writes the index only when a checkout completes. Without it ls-files lists
# nothing, so neither broken links nor files the checkout never wrote are visible.
$noIndex = @(foreach ($r in $repos) {
    if (-not (Test-Path -LiteralPath (Join-Path (git -C $r rev-parse --absolute-git-dir) 'index'))) { $r }
})
"repos without an index: $($noIndex.Count)"
if ($DryRun) {
    $noIndex | ForEach-Object { "  $_" }
} else {
    foreach ($r in $noIndex) {
        git -C $r reset -q    # rebuild the index from HEAD; the worktree stays as it is
        if ($LASTEXITCODE) { throw "git reset failed in $r" }
    }
}

# ---- 4. collect the paths to restore ----
# Missing files are restored only where the checkout was interrupted; elsewhere a
# deleted file may be an intended worktree change.
$work = foreach ($r in $repos) {
    $links = @(Get-BrokenLinks $r)
    $missing = @()
    if (-not $DryRun -and $noIndex -contains $r) {
        $missing = @(git -C $r -c core.quotePath=false ls-files --deleted)
    }
    if ($links.Count -or $missing.Count) {
        [pscustomobject]@{ Repo = $r; Links = $links; Missing = $missing }
    }
}
"repos to repair: $(@($work).Count)"
"broken links: $(($work | ForEach-Object { $_.Links.Count } | Measure-Object -Sum).Sum)"
"missing files: $(($work | ForEach-Object { $_.Missing.Count } | Measure-Object -Sum).Sum)"
if ($DryRun) {
    $work | ForEach-Object { $w = $_; $w.Links | ForEach-Object { Join-Path $w.Repo $_ } } | Select-Object -First 30
    Write-Output 'DryRun: nothing changed.'
    return
}

# ---- 5. rewrite only those paths from the index (offline) ----
# local core.symlinks=true (system gitconfig stays untouched)
$pathFile = [IO.Path]::GetTempFileName()
try {
    foreach ($w in $work) {
        if ($w.Links.Count) { git -C $w.Repo config core.symlinks true }
        foreach ($p in $w.Links) { Remove-Item -LiteralPath (Join-Path $w.Repo ($p -replace '/', '\')) -Force }
        # NUL-separated paths in a file: piping to git would append CR to every path.
        [IO.File]::WriteAllText($pathFile, ((@($w.Links) + @($w.Missing)) -join "`0"),
                                (New-Object System.Text.UTF8Encoding $false))
        git --literal-pathspecs -C $w.Repo restore --pathspec-from-file=$pathFile --pathspec-file-nul
        if ($LASTEXITCODE) { throw "git restore failed in $($w.Repo)" }
    }
} finally {
    Remove-Item -LiteralPath $pathFile -Force
}

# ---- 6. verify ----
$remaining = foreach ($w in $work) { Get-BrokenLinks $w.Repo | ForEach-Object { Join-Path $w.Repo $_ } }
if ($remaining.Count -gt 0) { $remaining | Select-Object -First 20; throw "$($remaining.Count) entries still not symlinks." }
$stillMissing = foreach ($r in $noIndex) { git -C $r -c core.quotePath=false ls-files --deleted | ForEach-Object { Join-Path $r $_ } }
if ($stillMissing.Count -gt 0) { $stillMissing | Select-Object -First 20; throw "$($stillMissing.Count) files still missing." }

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
Write-Output 'Repair done. run: build-emulator.ps1'