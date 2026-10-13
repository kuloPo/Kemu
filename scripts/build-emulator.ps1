$ErrorActionPreference = 'Stop'

# --- guard: must be a VS x64 developer shell ---
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw 'Run this from "Developer PowerShell for VS 18", not plain PowerShell.'
}
if ($env:VSCMD_ARG_TGT_ARCH -ne 'x64') { throw 'Need the x64 developer shell.' }
if (-not $env:VCToolsRedistDir) { throw 'VCToolsRedistDir missing; install the C++ desktop workload.' }

# --- paths (defined here; Git Bash stage does not share variables) ---
$HostBuild  = Split-Path $PSScriptRoot -Parent
$SourceRoot = Join-Path $HostBuild 'emulator'
$Qemu       = Join-Path $SourceRoot 'external\qemu'
$BuildRoot  = Join-Path $HostBuild 'out\kemu-windows-x86_64'
$Dist       = Join-Path $BuildRoot 'distribution\emulator'
$Jobs       = [Environment]::ProcessorCount

$CMake       = Join-Path $SourceRoot 'prebuilts\cmake\windows-x86\bin\cmake.exe'
$Ninja       = Join-Path $SourceRoot 'prebuilts\ninja\windows-x86\ninja.exe'
$BuildPython = Join-Path $SourceRoot 'prebuilts\python\windows-x86\python.exe'
$Toolchain   = Join-Path $Qemu 'android\build\cmake\toolchain-windows_msvc-x86_64.cmake'
foreach ($f in @($CMake, $Ninja, $BuildPython, $Toolchain)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "missing: $f" }
}

$RevLine = Get-Content -LiteralPath (Join-Path $Qemu 'source.properties') |
           Where-Object { $_ -like 'Pkg.Revision=*' } | Select-Object -First 1
if (-not $RevLine) { throw 'Pkg.Revision is missing.' }
$EmulatorRevision = $RevLine.Split('=')[1].Trim()

# --- 3. configure ---
& $CMake -S $Qemu -B $BuildRoot -G Ninja `
    "-DCMAKE_MAKE_PROGRAM=$Ninja" `
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain" `
    "-DPython3_EXECUTABLE=$BuildPython" `
    "-DPython3_INCLUDE_DIR=$SourceRoot\prebuilts\python\windows-x86\Include" `
    -DCMAKE_BUILD_TYPE=Release -DOPTION_CRASHUPLOAD=NONE `
    "-DOPTION_SDK_TOOLS_REVISION=$EmulatorRevision" `
    -DOPTION_SDK_TOOLS_BUILD_NUMBER=standalone-0 `
    -DOPTION_FISHTANK_STRIP=TRUE -DGFXSTREAM=TRUE -DKEMU_GUI_TESTS=OFF
if ($LASTEXITCODE) { throw "CMake configure failed with exit code $LASTEXITCODE" }

# --- 4. build and install ---
& $CMake --build $BuildRoot --target install --parallel $Jobs
if ($LASTEXITCODE) { throw "install failed with exit code $LASTEXITCODE" }

# --- 4.1 overwrite the upstream MSVC runtime with this VS's runtime ---
$CrtDir = Get-ChildItem -LiteralPath (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter '*.CRT' |
          Select-Object -First 1
if (-not $CrtDir) { throw 'x64 VC runtime directory is missing.' }
foreach ($d in @($BuildRoot, $Dist, (Join-Path $Dist 'qemu\windows-x86_64'))) {
    foreach ($lib in Get-ChildItem -LiteralPath $CrtDir.FullName -Filter '*.dll') {
        Copy-Item -LiteralPath $lib.FullName -Destination $d -Force
    }
}
Write-Output "Installed: $(Join-Path $Dist 'Kemu.exe')"