# 07 · 故障排查手册

> 先定位"哪一步挂了"：构建失败 / 打包失败 / 开机失败 / root 不生效 / 模块不加载。每类给现象→原因→处置。

## 1. 构建阶段

| 现象 | 原因 | 处置 |
|---|---|---|
| `git fetch origin 21b3312486b8` 失败 | 网络/服务器不支持按 SHA fetch | 改 `git clone --filter=blob:none -b lineage-23.2 --single-branch` 后 `git checkout 21b3312486b8` |
| `setup.sh` clone 超时（自建 Git） | `git.zako.shirkneko.top:20004` 不可达 | 手工 fallback（见 §8）或换网络/代理 |
| `make` 报 `ld.lld: not found` | 工具链缺 lld / PATH 未生效 | `export PATH=$HOME/toolchain/bin:$PATH`；`ld.lld --version` 验证 |
| 报 `CONFIG_KSU has unmet dependencies` | kprobe 依赖未满足 | 确认 `CONFIG_KPROBES=y`、`CONFIG_EXT4_FS=y`（defconfig 已有）；`make ... menuconfig` 里搜 KSU 看依赖 |
| defconfig 改完 `grep CONFIG_KSU` 为空 | `scripts/config` 用法错 | `scripts/config --file <defconfig> -e KSU`；或直接 `echo 'CONFIG_KSU=y' >> <defconfig>` |
| LTO 链接 OOM / 被 OOM killer 杀 | 内存不足（链接单线程吃 4GB+） | 加 swap；`-j` 降到 2；换 ≥16GB 机器/大 runner |
| 编译报一堆 `-Werror` | 工具链版本差异 | 用 LLVM 21.1.0（与 ROM 的 clang21 同代）；若仍报，检查是否误加了非本设备 defconfig 片段 |
| 构建成功但 `kernel.release` ≠ `5.4.302-qgki-g21b3312486b8` | 提交或 LOCALVERSION 不对 | 回 §5.6 校验提交；确认 defconfig 里 `CONFIG_LOCALVERSION="-qgki"` 未被覆盖；**别刷** |

## 2. 打包阶段

| 现象 | 原因 | 处置 |
|---|---|---|
| `magiskboot unpack` 报 "unsupported format" | 不是 boot.img（可能是 recovery/增量包/错误分区） | 用 payload-dumper-go 只提取 `boot` 分区；确认文件大小合理 |
| `repack` 失败 | 设备 magiskboot 版本旧 | Magisk Kitsune v30.7 支持 header v3；若仍失败，改用 `mkbootimg`（AOSP 参数见 docs/01：pagesize 4096 / header v3） |
| `new-boot.img` > 201326592 | 异常 | 检查是否误把 vendor_boot 当底包；正常 60~120MiB |

## 3. 开机失败（bootloop）

1. 立即回退：`fastboot flash boot_b boot_b_magisk.img`（或 dd 回刷）；
2. 若能进 bootloader，说明分区未坏，只是镜像逻辑问题；
3. 常见原因与处置：
   - kprobe 在 5.4 qGKI 上异常 → 先编**纯原版内核**（不加 KSU）验证；仍异常则工具链/提交问题；
   - 误刷了 Magisk 补丁过的 boot 当底包 → 重做 §5.2；
   - 刷到错误槽位 → 检查 `getprop ro.boot.slot_suffix`；
   - vbmeta 校验（少数情况）→ `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img`（慎用，先确认）。

## 4. 开机但 root 不生效

| 现象 | 原因 | 处置 |
|---|---|---|
| 管理器显示"内核未安装"/未识别 | 内核没带 KSU（CONFIG 未生效） | `grep CONFIG_KSU=y out/.config`；重编重刷 |
| 管理器提示版本不匹配 | 内核 tag 与管理器版本不同 | 统一：内核 `v3.0.0` ↔ 管理器 Nova v3.0.0 |
| `adb install` 报 `INSTALL_FAILED_VERSION_DOWNGRADE` | 旧 v4.1.2 versionCode 40545 > 35000 | 先 `adb uninstall com.sukisu.ultra`（data 为空无损失）再装 |
| su 弹窗但不授权 / 授权后仍无 root | ksud 未安装或 SELinux 拒 | 管理器里"安装/重装"；`dmesg | grep -i avc` 看拒绝；重启再试 |
| `su` 命令不存在 | 新 boot 干净 ramdisk、ksud 未装 | 打开管理器让它安装 ksud；之后 `su` 由内核提供 |

## 5. 开机但厂商模块不加载（Wi-Fi/基带失效）

现象：`dmesg` 有 `module verification failed`、`disagrees about version`、`Unknown symbol`，模块数极少。

处置（按顺序）：
1. 核对 `kernel.release` 是否精确等于 `5.4.302-qgki-g21b3312486b8`；
2. 核对 defconfig 是否保留了 `CONFIG_LTO_CLANG/CFI_CLANG/MODVERSIONS`（不要改）；
3. 确认只加了 `CONFIG_KSU=y`，没有顺手改别的选项；
4. 仍失败 → 同源重编厂商模块并刷 `vendor_dlkm`：
   ```bash
   # 构建机内核目录内（已 build）
   make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 modules -j$(nproc)
   # 产物：out/... 各模块；仓库若提供 vendor_dlkm 镜像生成脚本则用之；
   # 或在 fastbootd 下 fastboot flash vendor_dlkm <img>
   ```
   （该步骤较重，先完成根因排查再执行；必要时把本机当前 super 内 vendor_dlkm 备份出来。）
5. 仍无法解决 → 回退 Magisk 版本，保留日志与产物上报。

## 6. OTA 后

- 现象：OTA 完 root 消失、`uname -r` 变化。
- 处置：若 release 串未变（只是修补），直接 `scripts/06-post-ota-reflash.sh`；若 release 串变了，必须按新串重新锁提交、重编、重打包（旧镜像不可复用）。

## 7. 常见 check 命令合集

```bash
adb shell 'cat /proc/version'                       # 内核串
adb shell 'cat /proc/modules | wc -l'               # 模块数量
adb shell 'dmesg | grep -iE "vermagic|disagrees|Unknown symbol|avc" | tail -30'
adb shell 'getprop | grep -iE "kernelsu|sukisu|ksu"'
adb shell 'ls -la /data/adb/ksu'
adb shell 'su -c "cat /proc/kallsyms | grep -m5 ksu_"'
```

## 8. setup.sh 的 GitHub 镜像 fallback（手工集成）

```bash
cd kernel
git clone --depth 1 https://github.com/SukiSU-Nova/SukiSU-Nova KernelSU
git -C KernelSU checkout v3.0.0        # 或 git tag 存在时
ln -sf ../KernelSU/kernel drivers/kernelsu
printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
scripts/config --file arch/arm64/configs/vendor/lahaina-qgki_defconfig -e KSU
```

## 9. 升级/降级 SukiSU 版本

- 内核侧：重跑 `setup.sh <新tag>` 前先 `sh setup.sh --cleanup` 清理旧集成；
- 管理器侧：安装对应版本 APK；跨大版本需卸载重装（防签名/版本冲突）。

## 10. 求助时提供什么

1. 失败阶段（构建/打包/刷入/开机/root/模块）；
2. 完整命令与原始输出（不要截断报错）；
3. `kernel.release`、`out/.config` 中 KSU/LTO/CFI/MODVERSIONS 行、`Image` sha256；
4. 设备侧：`/proc/version`、`/proc/modules | wc -l`、`dmesg` 相关片段、管理器版本截图；
5. 是否已回退、回退后是否正常。
