#!/usr/bin/env bash
# 00 · 备份当前 boot 分区（当前槽位，通常是 boot_b 的 Magisk 版）
# 在 PC 上运行，需要 adb + 设备 root
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/env/device.env"
OUT=${OUT:-$PWD}
TMP="/data/local/tmp/${BOOT_PART}.img"

SLOT=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
echo "[*] 当前槽位: ${SLOT}"
echo "[*] 备份 /dev/block/by-name/${BOOT_PART} -> ${OUT}/${BOOT_PART}.img"

adb shell su -c "rm -f ${TMP}; dd if=/dev/block/by-name/${BOOT_PART} of=${TMP} bs=1M conv=fsync"
REMOTE=$(adb shell su -c "sha256sum ${TMP} | cut -d' ' -f1" | tr -d '\r')
adb pull "$TMP" "$OUT/${BOOT_PART}.img"
adb shell su -c "rm -f ${TMP}"

LOCAL=$(sha256sum "$OUT/${BOOT_PART}.img" | awk '{print $1}')
echo "[*] 设备 sha256: ${REMOTE}"
echo "[*] 本地 sha256: ${LOCAL}"
[ "$LOCAL" = "$REMOTE" ] || { echo '[!] 校验失败，重新备份'; exit 1; }

echo "[+] 已保存: $OUT/${BOOT_PART}.img"
echo "[!] 请复制到安全位置（电脑/云盘），这是唯一的回退保险"
