#!/usr/bin/env bash
# 02 · 集成 SukiSU（main 分支 kprobe）并打开 CONFIG_KSU=y
# 在构建机内核源码根目录运行（依赖 01 已执行）
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/env/device.env"
cd "$WORK/kernel"

echo "[*] 下载 setup.sh 并审查"
curl -LSs "$SUKISU_SETUP_URL" -o /tmp/sukisu-setup.sh
head -40 /tmp/sukisu-setup.sh

echo "[*] 集成 SukiSU tag=$SUKISU_TAG"
sh /tmp/sukisu-setup.sh "$SUKISU_TAG"

echo "[*] 校验集成结果"
test -L drivers/kernelsu && echo "  kernelsu 软链 OK" || { echo "  [!] 软链缺失，见 docs/07 §8"; exit 1; }
grep -n kernelsu drivers/Makefile drivers/Kconfig | head -5

echo "[*] 打开 CONFIG_KSU=y"
scripts/config --file "arch/arm64/configs/$DEFCONFIG" -e KSU
grep -n 'CONFIG_KSU' "arch/arm64/configs/$DEFCONFIG" || echo '[!] 未写入，可手工追加: echo "CONFIG_KSU=y" >> defconfig'

echo "[+] 集成完成"
