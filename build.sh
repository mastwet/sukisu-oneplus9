#!/usr/bin/env bash
# 便捷入口：在构建机上一次跑完 01 -> 03
# 用法: bash build.sh
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "== 01 拉取源码并锁定提交 =="
bash "$ROOT/scripts/01-fetch-sources.sh"

echo "== 02 集成 SukiSU =="
bash "$ROOT/scripts/02-integrate-sukisu.sh"

echo "== 03 编译内核 =="
bash "$ROOT/scripts/03-build-kernel.sh"

echo
echo "下一步（见 docs/05）:"
echo "  1) 从同版本 OTA 提取 stock boot.img"
echo "  2) STOCK_BOOT=stock_boot.img IMAGE=\$WORK/out/arch/arm64/boot/Image bash scripts/04-make-boot-image.sh"
echo "  3) bash scripts/05-flash.sh new-boot.img"
