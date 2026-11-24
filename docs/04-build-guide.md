# 04 · 构建详细步骤（VM / GitHub Actions 两套）

> 目标产物：`out/arch/arm64/boot/Image`，且 `out/include/config/kernel.release == 5.4.302-qgki-g21b3312486b8`。

## 0. 前置

- 构建机：x86_64 Linux（Ubuntu 22.04+），≥16 GB RAM（LTO 链接吃内存），≥30 GB 磁盘；或 GitHub Actions。
- 网络：能访问 GitHub、`git.zako.shirkneko.top`（SukiSU 自建 Git）。
- **不要**在手机上编（见 docs/03 备选 5）。

## 1. 安装依赖（Debian/Ubuntu）

```bash
sudo apt-get update
sudo apt-get install -y bc bison flex libssl-dev libelf-dev lz4 cpio python3 rsync \
    git curl xz-utils build-essential
```

## 2. 工具链（LLVM 21.1.0）

```bash
mkdir -p ~/toolchain && cd ~/toolchain
curl -L -o llvm.tar.xz \
  https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.0/LLVM-21.1.0-Linux-X64.tar.xz
tar -xf llvm.tar.xz --strip-components=1
export PATH="$HOME/toolchain/bin:$PATH"
clang --version     # 应显示 clang version 21.1.0
ld.lld --version    # 必须存在（LTO/CFI 必需）
```

> 备选：AOSP prebuilt clang r563880（LineageOS 构建同款）。可 `git clone --depth 1 https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86`（体积大），clang 在 `clang-r563880/`。官方 tarball 通道不稳定，以能跑通 `clang --version` 为准。

## 3. 取内核源码并锁定提交

```bash
WORK=$PWD/work && mkdir -p "$WORK" && cd "$WORK"

git clone --filter=blob:none --single-branch -b lineage-23.2 "$KERNEL_REPO" kernel
cd kernel
git checkout 21b3312486b8       # 若报错：git fetch origin 21b3312486b8 && git checkout 21b3312486b8
git log -1 --oneline            # 应看到 "arm64: configs: Regenerate Q/GKI lahaina defconfigs"

# 校验 defconfig 关键项（此时还没有 CONFIG_KSU）
grep -E 'CONFIG_LOCALVERSION|CONFIG_KPROBES=|CONFIG_EXT4_FS=|CONFIG_LTO_CLANG=|CONFIG_CFI_CLANG=' \
     arch/arm64/configs/vendor/lahaina-qgki_defconfig
```

> 说明：clone 用 `--filter=blob:none`（无文件内容的完整历史），checkout 时按需取 blob，比整仓浅克隆更稳；不要改成"只浅克隆分支 tip"，否则 checkout 不到旧提交。

## 4. 集成 SukiSU（main 分支 kprobe）

```bash
cd "$WORK/kernel"

# 4.1 下载 setup.sh 并先审查（不要盲跑）
curl -LSs "$SUKISU_SETUP_URL" -o /tmp/sukisu-setup.sh
head -60 /tmp/sukisu-setup.sh     # 确认逻辑：clone 仓库→软链 drivers/kernelsu→改 Makefile/Kconfig

# 4.2 执行，锁定 v3.0.0
sh /tmp/sukisu-setup.sh v3.0.0
test -L drivers/kernelsu && echo "kernelsu 软链 OK"
grep -n "kernelsu" drivers/Makefile drivers/Kconfig | head

# 4.3 打开 CONFIG_KSU=y（写进 defconfig，构建时生效）
scripts/config --file arch/arm64/configs/vendor/lahaina-qgki_defconfig -e KSU
grep -n "CONFIG_KSU" arch/arm64/configs/vendor/lahaina-qgki_defconfig   # 应出现 CONFIG_KSU=y
```

说明：
- `setup.sh` 无参数时默认 checkout 最新 tag；我们显式传 `v3.0.0` 与管理器配套。
- 若自建 Git 不可达，fallback：`git clone --depth 1 https://github.com/SukiSU-Nova/SukiSU-Nova KernelSU`，再手工做软链与 Makefile/Kconfig 三处修改（见 07 排查 #8）。
- 5.4 上 kprobe 分支**不需要**手动改 `fs/exec.c` 等源码。

## 5. 编译

```bash
cd "$WORK/kernel"
export PATH="$HOME/toolchain/bin:$PATH"

make O="$WORK/out" ARCH=arm64 LLVM=1 LLVM_IAS=1 vendor/lahaina-qgki_defconfig
grep -q '^CONFIG_KSU=y' "$WORK/out/.config" && echo "CONFIG_KSU=y OK"

make O="$WORK/out" ARCH=arm64 LLVM=1 LLVM_IAS=1 Image -j"${JOBS:-$(nproc)}"
```

预期：
- 首次配置后编译时间视机器 20 分钟 ~ 2 小时（LTO）；
- 产物 `$WORK/out/arch/arm64/boot/Image`（约 30~60 MiB 未压缩）；
- 链接阶段单线程，`ld.lld` 内存峰值高（≥4 GB），CI 小机器可能 OOM。

## 6. 构建后自检（必须全过）

```bash
cat "$WORK/out/include/config/kernel.release"
# 期望：5.4.302-qgki-g21b3312486b8   ← 不一致 = 模块不匹配，不要往下走

grep '^CONFIG_KSU=y' "$WORK/out/.config"
grep -E '^CONFIG_(LTO_CLANG|CFI_CLANG|MODVERSIONS)=y' "$WORK/out/.config"
file "$WORK/out/arch/arm64/boot/Image"
ls -l "$WORK/out/arch/arm64/boot/Image"

# 可选：确认 KSU 符号已编入（未压缩 Image 里能搜到）
strings "$WORK/out/arch/arm64/boot/Image" | grep -m5 -E 'ksu|KernelSU' || true
```

**任一不符 → 停止，先按 07 排查，不要刷机。**

## 7. GitHub Actions 方式

`ci/build-kernel.yml` 即完整流水线（workflow_dispatch 手动触发）：

1. 把该文件放到任意仓库 `.github/workflows/`（私有仓库亦可）；
2. Actions 页面 → Run workflow；
3. 结束后下载 artifact `kernel-image`（含 `Image`、`System.map`、`.config`、`kernel.release`）；
4. 本地跑 `docs/05` 的重打包流程。

注意：
- 免费 runner 内存可能不够 LTO 链接 → 如果失败，把 `-j` 降到 2，或换大 runner/自托管；
- workflow 已内置 `setup.sh` 不可达时的 GitHub 镜像 fallback。

## 8. 交付物清单（构建机侧）

```
out/arch/arm64/boot/Image      ← 核心产物
out/include/config/kernel.release
out/.config
out/System.map                 ← 排查用
sha256sum Image                ← 记录到交接记录
```
