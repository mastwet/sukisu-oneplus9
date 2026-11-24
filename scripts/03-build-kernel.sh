#!/usr/bin/env bash
# 03 · 编译内核 Image 并做构建后自检
# 在构建机运行（依赖 01/02）
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/env/device.env"

cd "$WORK/kernel"
export PATH="$HOME/toolchain/bin:$PATH"

command -v clang >/dev/null || { echo '[!] clang 不在 PATH，先执行 docs/04 §2'; exit 1; }
command -v ld.lld >/dev/null || { echo '[!] ld.lld 不在 PATH（LTO/CFI 必需）'; exit 1; }
clang --version | head -1

echo "[*] 配置 $DEFCONFIG"
make "O=$WORK/out" ARCH=arm64 LLVM=1 LLVM_IAS=1 "$DEFCONFIG"
grep -q '^CONFIG_KSU=y' "$WORK/out/.config" && echo "  CONFIG_KSU=y OK"

echo "[*] 编译 Image（LTO，耗时较长）"
make "O=$WORK/out" ARCH=arm64 LLVM=1 LLVM_IAS=1 Image -j"${JOBS:-$(nproc)}"

echo "[*] 构建后自检"
REL=$(cat "$WORK/out/include/config/kernel.release")
echo "  kernel.release = $REL"
[ "$REL" = "$KERNEL_RELEASE" ] || { echo "[!] release 串不匹配，禁止刷机！见 docs/04 §6"; exit 2; }
grep -E '^CONFIG_(LTO_CLANG|CFI_CLANG|MODVERSIONS)=y' "$WORK/out/.config"
ls -l "$WORK/out/arch/arm64/boot/Image"
sha256sum "$WORK/out/arch/arm64/boot/Image"

echo "[+] 完成: $WORK/out/arch/arm64/boot/Image"
