# 01 · 本机画像（实测数据）

> 全部为 2026-11 对本机实测结果，命令附在文末。接手后先花 2 分钟复核关键项，若不一致（尤其内核 release、槽位、root 状态），以实测为准并回报。

## 1. 硬件

| 项目 | 实测值 |
|---|---|
| 机型 | OnePlus 9（LE2110，OnePlus/OnePlus9） |
| SoC | Qualcomm SM8350（lahaina，骁龙 888） |
| CPU | 8 核：1×X1 2.84GHz + 3×A78 2.42GHz + 4×A55 1.80GHz |
| GPU | Adreno 660（GLES 3.2 V@0530.53） |
| 屏幕 | 6.55" AMOLED，1080×2400，60/120Hz，HDR10，450dpi |
| 内存 | 8 GB（系统可用 7.2 GB） |
| 存储 | 128 GB UFS 3.1（Samsung KLUDG4UHDB-B2D1），`/data` 102G，空闲 78G |
| 电池 | 4450mAh 设计（官方 4500mAh 典型） |
| 网络 | 双卡 5G |

## 2. 软件与分区

| 项目 | 实测值 |
|---|---|
| 系统 | LineageOS 23.2 NIGHTLY（`23.2-20260525-NIGHTLY-lemonade`），Android 16（SDK 36.1），userdebug |
| 内核 | `Linux 5.4.302-qgki-g21b3312486b8`，clang 21（r563880），构建于 2026-05-25 |
| 启动 | A/B，激活槽 `_b`；`ro.boot.verifiedbootstate=orange`（已解锁） |
| 分区 | `boot_a/b` 201326592 B；`vendor_boot`、`dtbo`、`vbmeta`(system/vendor) 独立；无 `init_boot` |
| 当前 root | Magisk Kitsune v30.7（`magisk -V`=30700；`su -c id` → uid 0，`u:r:magisk:s0`） |
| Magisk 目录 | `/data/adb/magisk`（含 magiskboot/magiskinit/magiskpolicy），`/debug_ramdisk/su -> ./magisk` |
| SukiSU 管理器 | `com.sukisu.ultra` v4.1.2（2026-05-25 安装，`lastUpdateTime` 同），**无 data 目录 = 从未启动** |
| 内核 KSU | **无**：`CONFIG_KSU` 不存在，`/proc/kallsyms` 无 `ksu_*` 符号 |
| 属性 | `lineage_lemonade-userdebug`，`ro.lineage.version=23.2`，`ro.build.tags=release-keys` |

## 3. 内核配置（决定 SukiSU 可行性的关键项）

来自 `/proc/config.gz` 与 `arch/arm64/configs/vendor/lahaina-qgki_defconfig`（提交 21b3312486b8）：

```
CONFIG_KPROBES=y            # SukiSU main 分支 kprobe 集成必需
CONFIG_KRETPROBES=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_EXT4_FS=y            # main 分支 CONFIG_KSU 依赖项
CONFIG_OVERLAY_FS=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
# CONFIG_MODULE_SIG is not set      → 可加载未签名本编 .ko
CONFIG_HAVE_SYSCALL_TRACEPOINTS=y
CONFIG_LTO_CLANG=y          # 必须保留（厂商模块是 LTO/CFI 编译）
CONFIG_CFI_CLANG=y          # 必须保留
CONFIG_MODVERSIONS=y
CONFIG_LOCALVERSION="-qgki"
CONFIG_KSU / CONFIG_KPM / CONFIG_KSU_SUSFS / CONFIG_KSU_SUSFS_* ：均不存在
```

## 4. 现有 root 链路（为什么"能回退"）

- `boot_b` 当前是 Magisk Kitsune 补丁过的镜像（ramdisk 内 magiskinit 接管 init）；
- `su -c id` 走 magiskd → `u:r:magisk:s0`；
- 只要 `boot_b_magisk.img` 备份在手，`fastboot flash boot_b` 即可恢复。

## 5. 复核命令（接手第一件事）

```bash
adb shell getprop ro.product.device              # OnePlus9
adb shell getprop ro.boot.slot_suffix            # _b
adb shell getprop ro.boot.verifiedbootstate      # orange
adb shell cat /proc/version                      # 5.4.302-qgki-g21b3312486b8
adb shell su -c id                               # uid=0(root) ... magisk
adb shell su -c 'getprop ro.lineage.version'     # 23.2
adb shell dumpsys package com.sukisu.ultra | grep versionName   # v4.1.2（计划替换为 Nova v3.0.0）
adb shell su -c 'zcat /proc/config.gz | grep -c CONFIG_KSU'     # 0（无）
```

## 6. 若状态与上表不一致

- 内核版本不同 → ROM 已升级/回退，按 `docs/04-build-guide.md` 用新 release 串反推提交（`uname -r` 里 `-g<hash>`），并更新 `env/device.env` 的 `KERNEL_COMMIT/KERNEL_RELEASE`；
- 槽位变成 `_a` → 所有刷机步骤改 `boot_a`（脚本会自动判断）；
- 已无 root → 先重刷 Magisk 恢复回退能力再开始；
- 管理器版本不是 v4.1.2 → 按实际版本决定是否替换为 Nova v3.0.0。
