#!/usr/bin/env bash
# 01 · 拉取内核源码并锁定到 ROM 对应的提交
# 在构建机（Linux x86_64）上运行
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/env/device.env"
mkdir -p "$WORK"
cd "$WORK"

if [ -d kernel/.git ]; then
  echo "[*] kernel/ 已存在，复用"
else
  echo "[*] 克隆 $KERNEL_REPO（分支 $KERNEL_BRANCH，无 blob 部分克隆）"
  git clone --filter=blob:none --single-branch -b "$KERNEL_BRANCH" "$KERNEL_REPO" kernel
fi

cd kernel
echo "[*] 锁定提交 $KERNEL_COMMIT"
if ! git checkout "$KERNEL_COMMIT" 2>/dev/null; then
  echo "[!] 分支历史里没有该提交，尝试按 SHA 拉取"
  git fetch origin "$KERNEL_COMMIT"
  git checkout "$KERNEL_COMMIT"
fi
git log -1 --oneline
git rev-parse HEAD

echo "[*] 校验 defconfig 关键项:"
grep -E 'CONFIG_LOCALVERSION|CONFIG_KPROBES=|CONFIG_EXT4_FS=|CONFIG_LTO_CLANG=|CONFIG_CFI_CLANG=|CONFIG_MODVERSIONS=' \
  arch/arm64/configs/vendor/lahaina-qgki_defconfig || true

echo "[+] 源码就绪: $(pwd) @ $(git rev-parse --short HEAD)"
echo "    期望内核 release 串: $KERNEL_RELEASE"
echo "    （提交必须与 release 串中的 -g<hash> 一致，否则厂商模块加载失败）"
