#!/usr/bin/env bash
# 06 · OTA 之后重刷 SukiSU boot（A/B 槽位可能已切换）
# 用法: bash 06-post-ota-reflash.sh new-boot.img
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/env/device.env"

IMG=${1:-new-boot.img}
[ -f "$IMG" ] || { echo "[!] 找不到镜像: $IMG"; exit 1; }

NEWREL=$(adb shell uname -r | tr -d '\r')
echo "[*] 当前内核: ${NEWREL}"
case "$NEWREL" in
  *"$KERNEL_RELEASE"*) echo "[+] release 串一致，可直接重刷" ;;
  *) echo "[!] release 串已变化（OTA 升级了内核），旧镜像不可用："
     echo "    需按新串 -g<hash> 更新 env/device.env 的 KERNEL_COMMIT/KERNEL_RELEASE 并重新构建"
     exit 2 ;;
esac

bash "$ROOT/scripts/05-flash.sh" "$IMG"
