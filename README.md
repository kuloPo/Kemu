[简体中文](README_zh.md) | [English](README.md)

## Overview

Kemu is a high-performance, open-source Android emulator for Windows. Built on AOSP Android 16 and Android Emulator / QEMU, it uses WHPX hardware acceleration, the ANGLE / gfxstream graphics stack, and Digitalis ARM64 Native Bridge translation. Application compatibility and performance are still being improved.

## Downloads

[GitHub Releases](https://github.com/kuloPo/Kemu/releases)

## Build and Run from Source

The build has two parts: build the emulator on Windows, then build the Android system images in WSL and copy them into the emulator directory.

### Prerequisites

- Windows x64 with CPU virtualization and **Windows Hypervisor Platform** enabled.
- Git for Windows (including Git Bash) and Python 3.
- Visual Studio 18 (2026) with the **Desktop development with C++** workload, ATL/MFC, and the Windows SDK installed. Use the x64 development environment.
- A WSL Linux environment with Git, Git LFS, Repo, and the AOSP build dependencies installed, plus sufficient free disk space.

The commands below assume that the project is located at `D:\Kemu` and that its `scripts` directory is already present. The project path in `repair-symlinks.ps1` is currently hardcoded to `D:\Kemu`. If you use a different location, update `$ProjectRoot` in that script first.

### 1. Download the Emulator Source

Run the following in **Git Bash on Windows**:

```bash
git clone https://github.com/kuloPo/Kemu.git
cd Kemu
curl -fL -o repo https://storage.googleapis.com/git-repo-downloads/repo
mkdir -p emulator && cd emulator
../repo init -u https://github.com/kuloPo/Kemu-emulator_manifests.git -g default --platform=windows
../repo sync -c -j8
```

### 2. Build the Windows Emulator

Open **Developer PowerShell for VS 18** as administrator, make sure you are using the x64 development environment, and run:

```powershell
.\scripts\repair-symlinks.ps1
.\scripts\build-emulator.ps1
```

### 3. Build the Android System Images

Run the following on **Linux**. **WSL** is recommended.

```bash
git clone https://github.com/kuloPo/Kemu.git
cd Kemu
mkdir -p AOSP && cd AOSP
repo init -u https://github.com/kuloPo/Kemu-AOSP_manifests.git -b main --git-lfs
repo sync -c -j8

source build/envsetup.sh
lunch sdk_phone64_x86_64_digitalis-trunk_staging-userdebug
make -j"$(nproc)"
```

`make` uses all available CPU cores for the build. If memory is limited, reduce the number of parallel jobs, for example with `make -j8`.

The image output directory in this example is `Kemu/AOSP/out/target/product/emu64xa/`.

### 4. Copy the System Images

Close Kemu if it is running, then run the following in **WSL**:

```bash
cd Kemu
scripts/copy_imgs.sh \
  "AOSP/out/target/product/emu64xa" \
  /mnt/<drive>/path/to/Kemu/out/kemu-windows-x86_64/distribution/emulator
```

The script creates a `system-img` folder alongside `Kemu.exe` and copies the required files into it. To copy the files manually, use the mapping below. Source paths are relative to the `emu64xa` output directory from the previous step; destination paths are relative to the directory containing `Kemu.exe`.

| Build Output File | Destination File |
| --- | --- |
| `system-qemu.img` | `system-img/system.img` |
| `ramdisk-qemu.img` | `system-img/ramdisk.img` |
| `userdata.img` | `system-img/userdata.img` |
| `encryptionkey.img` | `system-img/encryptionkey.img` |
| `advancedFeatures.ini` | `system-img/advancedFeatures.ini` |
| `system/build.prop` | `system-img/build.prop` |
| `kernel_cmdline.txt` | `system-img/kernel_cmdline.txt` |
| `kernel-ranchu` | `system-img/kernel-ranchu` |
| `VerifiedBootParams.textproto` | `system-img/VerifiedBootParams.textproto` |

Use the complete set of files from the same build. For the first two entries, copy the images with the `-qemu` suffix and rename them as shown in the table.

### 5. Launch Kemu

On Windows, double-click `Kemu.exe` in `out/kemu-windows-x86_64/distribution/emulator`.

New instances use a 128 GiB data disk. Settings > Performance > Storage shows its allocated host space and total capacity. Expand disk preserves existing data and asks for confirmation before restarting to apply a larger capacity. Existing disks keep their current capacity.
