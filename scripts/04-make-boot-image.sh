#!/usr/bin/env bash
# 04 · 用 stock boot.img + 新 Image 重打包出 new-boot.img
# 在 PC 上运行：利用设备自带 /data/adb/magisk/magiskboot（需设备 root）
# 用法:
#   STOCK_BOOT=stock_boot.img IMAGE=out/arch/arm64/boot/Image bash 04-make-boot-image.sh
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/env/device.env"

STOCK_BOOT=${STOCK_BOOT:-stock_boot.img}
IMAGE=${IMAGE:-$ROOT/../out/arch/arm64/boot/Image}
OUT=${OUT:-new-boot.img}

[ -f "$STOCK_BOOT" ] || { echo "[!] 找不到 stock boot: $STOCK_BOOT（见 docs/05 §5.2）"; exit 1; }
[ -f "$IMAGE" ]      || { echo "[!] 找不到 Image: $IMAGE（先跑 03）"; exit 1; }

echo "[*] push 底包与内核到设备"
adb push "$STOCK_BOOT" /sdcard/stock_boot.img >/dev/null
adb push "$IMAGE" /sdcard/Image >/dev/null

echo "[*] 设备端 magiskboot unpack + repack"
adb shell su -c 'rm -rf /data/local/tmp/repack && mkdir -p /data/local/tmp/repack \
  && cd /data/local/tmp/repack \
  && /data/adb/magisk/magiskboot unpack /sdcard/stock_boot.img \
  && cp /sdcard/Image kernel \
  && /data/adb/magisk/magiskboot repack /sdcard/stock_boot.img /sdcard/new-boot.img'

adb pull /sdcard/new-boot.img "$OUT" >/dev/null
adb shell su -c 'rm -rf /data/local/tmp/repack /sdcard/stock_boot.img /sdcard/Image'

SIZE=$(stat -c %s "$OUT")
echo "[*] new-boot.img 大小: ${SIZE} 字节（上限 ${BOOT_SIZE}）"
[ "$SIZE" -le "$BOOT_SIZE" ] || { echo '[!] 超过 boot 分区大小'; exit 2; }

echo "[*] 二次解包验证"
adb push "$OUT" /sdcard/new-boot.img >/dev/null
adb shell su -c '/data/adb/magisk/magiskboot unpack /sdcard/new-boot.img' >/dev/null 2>&1 \
  && echo "  解包 OK" || echo '  [!] 二次解包失败'
sha256sum "$OUT"

echo "[+] 完成: $OUT"
