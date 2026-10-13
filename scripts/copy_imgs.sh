#!/bin/bash

if [ "$#" -ne 2 ] || [ ! -d "$1" ] || [ ! -d "$2" ]; then
	echo "Usage: $0 <src> <dst>"
	exit 1
fi

if [ ! -e "$1/system-qemu.img" ]; then
	echo "Error: $1 does not have system imgs"
	exit 1
fi

if [ ! -e "$2/Kemu.exe" ]; then
	echo "Error: $2 does not have Kemu.exe"
	exit 1
fi

mkdir -p $2/system-img

cp $1/system-qemu.img $2/system-img/system.img
cp $1/vendor-qemu.img $2/system-img/vendor.img
cp $1/ramdisk-qemu.img $2/system-img/ramdisk.img
cp $1/userdata.img $2/system-img/
cp $1/encryptionkey.img $2/system-img/
cp $1/advancedFeatures.ini $2/system-img/
cp $1/system/build.prop $2/system-img/
cp $1/kernel_cmdline.txt $2/system-img/
cp $1/kernel-ranchu $2/system-img/
cp $1/VerifiedBootParams.textproto $2/system-img/
