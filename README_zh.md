[简体中文](README_zh.md) | [English](README.md)

## 项目介绍

Kemu 是面向 Windows 的高性能开源 Android 模拟器，基于 AOSP Android 16 和 Android Emulator / QEMU，使用 WHPX 硬件加速、ANGLE / gfxstream 图形栈及 Digitalis ARM64 Native Bridge 转译。应用兼容性与性能仍在完善。



## 下载链接

[GitHub Releases](https://github.com/kuloPo/Kemu/releases)



## 从源码编译并运行

编译分为两部分：在 Windows 上构建模拟器，在 WSL 中构建 Android 系统镜像，最后将镜像复制到模拟器目录。

### 准备环境

- Windows x64，已开启 CPU 虚拟化及 **Windows Hypervisor Platform**。
- Git for Windows（含 Git Bash）、Python 3。
- Visual Studio 18（2026），安装“使用 C++ 的桌面开发”、ATL/MFC 和 Windows SDK，使用 x64 开发环境。
- WSL Linux 环境，已安装 Git、Git LFS、Repo 及 AOSP 编译依赖，并预留充足的磁盘空间。

以下命令以本项目位于 `D:\Kemu` 为例，且该目录下已有 `scripts` 文件夹。当前 `repair-symlinks.ps1` 中的项目路径固定为 `D:\Kemu`；若使用其他目录，请先修改该脚本的 `$ProjectRoot`。

### 1. 下载模拟器源码

在 **Windows** 端 **Git Bash** 中执行：

```bash
git clone https://github.com/kuloPo/Kemu.git
cd Kemu
curl -fL -o repo https://storage.googleapis.com/git-repo-downloads/repo
mkdir -p emulator && cd emulator
../repo init -u https://github.com/kuloPo/Kemu-emulator_manifests.git -g default --platform=windows
../repo sync -c -j8
```

### 2. 编译 Windows 模拟器

以管理员身份打开 **Developer PowerShell for VS 18**，确认使用 x64 开发环境，然后执行：

```powershell
.\scripts\repair-symlinks.ps1
.\scripts\build-emulator.ps1
```

### 3. 编译 Android 系统镜像

以下命令在 **Linux** 中执行，推荐使用 **WSL**。

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

`make` 使用所有可用 CPU 核心并行构建。如果内存不足，可降低并行数，例如改为 `make -j8`。

本例的镜像输出目录为 `Kemu/AOSP/out/target/product/emu64xa/`。

### 4. 复制系统镜像

关闭正在运行的 Kemu，然后在 **WSL** 中执行：

```bash
cd Kemu
scripts/copy_imgs.sh \
  "AOSP/out/target/product/emu64xa" \
  /mnt/<drive>/path/to/Kemu/out/kemu-windows-x86_64/distribution/emulator
```

脚本会在 `Kemu.exe` 旁创建 `system-img` 文件夹并复制所需文件。如需手动复制，请按照以下对应关系操作；源路径均相对于上一步的 `emu64xa` 输出目录，目标路径均相对于 `Kemu.exe` 所在目录。

| 编译输出文件 | 目标文件 |
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

请使用同一次构建生成的整套文件。注意前两项需要复制带 `-qemu` 后缀的镜像，并按表格重命名。

### 5. 启动 Kemu

在 Windows 中双击位于`out/kemu-windows-x86_64/distribution/emulator`目录下的 `Kemu.exe`



