#!/usr/bin/env bash
# 05 · 刷入 boot（默认 dd 免 PC；FLASH_METHOD=fastboot 走 USB）
# 用法:
#   bash 05-flash.sh new-boot.img                # dd 到当前槽位
#   FLASH_METHOD=fastboot bash 05-flash.sh new-boot.img
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/env/device.env"

IMG=${1:-new-boot.img}
[ -f "$IMG" ] || { echo "[!] 找不到镜像: $IMG"; exit 1; }
SIZE=$(stat -c %s "$IMG")
[ "$SIZE" -le "$BOOT_SIZE" ] || { echo "[!] 镜像超过分区大小"; exit 2; }

SLOT=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
PART="boot${SLOT}"
echo "[*] 当前槽位: ${SLOT}  ->  目标分区: ${PART}"

if [ "${FLASH_METHOD:-dd}" = "fastboot" ]; then
  echo "[*] fastboot 模式"
  adb reboot bootloader
  sleep 8
  fastboot devices
  CUR=$(fastboot getvar current-slot 2>/dev/null | awk -F': ' '{print $2}')
  echo "[*] fastboot current-slot: ${CUR}"
  [ "boot${CUR}" = "$PART" ] || { echo "[!] 槽位不一致，中止"; exit 3; }
  fastboot flash "$PART" "$IMG"
  fastboot reboot
  exit 0
fi

echo "[*] dd 模式：push 镜像并写入 ${PART}"
adb push "$IMG" /sdcard/new-boot.img >/dev/null
adb shell su -c "dd if=/sdcard/new-boot.img of=/dev/block/by-name/${PART} bs=1M conv=fsync"

echo "[*] 回读校验"
REMOTE=$(adb shell su -c "head -c ${SIZE} /dev/block/by-name/${PART} | sha256sum | cut -d' ' -f1" | tr -d '\r')
LOCAL=$(sha256sum "$IMG" | awk '{print $1}')
echo "  设备: ${REMOTE}"
echo "  本地: ${LOCAL}"
if [ "$REMOTE" = "$LOCAL" ]; then
  echo "[+] 写入校验通过，重启生效"
  adb reboot
else
  echo "[!] 校验不一致！立刻回刷备份（boot_b_magisk.img）"
  exit 4
fi
