# SukiSU × OnePlus 9（LineageOS 23.2）内核构建交接包

> 交接版本：2026-11-24
> 目标：由接手人按本目录步骤，产出一个**可直接刷入 boot_b 的 boot.img**（5.4 内核内置 SukiSU Nova v3.0.0，kprobe 集成），替换当前 Magisk Kitsune root，并完成验收。
> 范围：只动 `boot` 分区（内核 + ramdisk 重打包）。**不动** system/vendor/super/vendor_boot/dtbo/vbmeta。

---

## 0. 30 秒理解这台机器

- 机型：OnePlus 9（`lemonade` / LE2110），骁龙 888（SM8350）
- 系统：**LineageOS 23.2 NIGHTLY**（Android 16，userdebug），构建 `23.2-20260525-NIGHTLY-lemonade`
- 内核：**5.4.302-qgki-g21b3312486b8**（5.4 qGKI，**不是** GKI 2.0）
- 分区：A/B，当前激活 `_b`；`boot_a/b` 各 192 MiB；bootloader 已解锁（orange）
- 当前 root：**Magisk Kitsune v30.7**（ramdisk 注入，`u:r:magisk:s0`）
- SukiSU 管理器：`com.sukisu.ultra` v4.1.2 已安装但**从未启动**；内核无 `CONFIG_KSU`、无 ksu 符号
- 结论：5.4 非 GKI，SukiSU 官方无预编译（LKM 只覆盖 5.10+），**只能源码集成内核**；SukiSU 管理器需换成 Nova v3.0.0 配套

## 1. 目录结构

```
sukisu-op9-handover/
├── README.md                     ← 本文件（总入口 / 快速开始 / 硬性约束）
├── env/device.env                ← 设备与构建参数（脚本统一从这里取）
├── docs/
│   ├── 00-insight-report.md      ← 最初的洞察报告（背景）
│   ├── 01-device-profile.md      ← 本机画像（实测数据）
│   ├── 02-sukisu-internals.md    ← SukiSU 原理与两种集成形态
│   ├── 03-decisions-and-risks.md ← 决策日志、风险表、备选方案
│   ├── 04-build-guide.md         ← 【核心】构建详细步骤（VM/CI 两套）
│   ├── 05-flash-guide.md         ← 重打包 boot、刷机、回退
│   ├── 06-verification.md        ← 验收清单（含厂商模块检查）
│   └── 07-troubleshooting.md     ← 故障排查手册
├── scripts/
│   ├── 00-backup-boot.sh         ← 备份当前 boot_b（PC + adb）
│   ├── 01-fetch-sources.sh       ← 拉内核源码并锁定提交
│   ├── 02-integrate-sukisu.sh    ← 集成 SukiSU + 打开 CONFIG_KSU
│   ├── 03-build-kernel.sh        ← 编译 Image
│   ├── 04-make-boot-image.sh     ← 用设备上的 magiskboot 重打包 boot.img
│   ├── 05-flash.sh               ← dd（免 PC）或 fastboot 刷入
│   └── 06-post-ota-reflash.sh    ← OTA 后重刷
└── ci/build-kernel.yml           ← GitHub Actions 一键构建（推荐）
```

## 2. 快速开始（六步）

```bash
# 0) 备份（强烈建议第一步做，PC 上跑）
bash scripts/00-backup-boot.sh            # 产出 boot_b_magisk.img（Magisk 回退用）

# 1) 取 stock boot.img（用于重打包；从同版本 OTA zip 提取）
#    lineage-23.2-20260525-NIGHTLY-lemonade.zip → payload.bin → payload-dumper-go → boot.img
#    详见 docs/05-flash-guide.md §5.1

# 2) 构建 Image（二选一）
#    A. GitHub Actions：把 ci/build-kernel.yml 放进任意仓库跑 workflow_dispatch，下载 artifact
#    B. Linux VM：bash build.sh        ← 串行执行 01→02→03（也可单独跑 scripts/01~03）

# 3) 重打包（手机 root + 设备自带 magiskboot，PC 上执行）
STOCK_BOOT=stock_boot.img IMAGE=out/arch/arm64/boot/Image bash scripts/04-make-boot-image.sh
#    产出 new-boot.img

# 4) 刷入（默认 dd 免 PC；也可 fastboot）
bash scripts/05-flash.sh new-boot.img

# 5) 验收（docs/06-verification.md）
#    - 开机正常、厂商模块加载正常
#    - 安装 SukiSU Nova v3.0.0 管理器 → 识别内核 → su 可用

# 6) 失败回退
bash scripts/05-flash.sh boot_b_magisk.img   # 刷回 Magisk 版 boot
```

## 3. 硬性约束（违反会 bootloop 或 root 不生效）

1. **必须锁定内核提交 `21b3312486b8`**（lineage-23.2 分支）。内核 release 串必须产出 `5.4.302-qgki-g21b3312486b8`——只有一致，`vendor_dlkm` 里的厂商模块（vermagic/CRC）才能加载。
2. **保留 LTO/CFI 配置**（`CONFIG_LTO_CLANG=y`、`CONFIG_CFI_CLANG=y`）。厂商模块是 CFI 编译的，关掉 CFI 会导致模块拒绝加载。
3. **`CONFIG_KSU=y` 用内置（y），不要用 `m`**（`CONFIG_MODVERSIONS=y` 下模块方式易出 CRC 问题）。
4. 刷机只动 `boot_b`（当前槽 `_b`）；**未备份前禁止刷机**；刷前用 `ro.boot.slot_suffix` 复核槽位。
5. 管理器必须与内核侧 SukiSU 版本配套：内核 tag `v3.0.0` ↔ 管理器 **Nova v3.0.0**（当前机器上的 v4.1.2 是旧 Ultra 版本，需卸载重装）。
6. 产物 `new-boot.img` 必须 ≤ 201326592 字节（boot 分区大小），正常约 60~120 MiB。

## 4. 交接人检查清单

- [ ] 已读 `docs/01-device-profile.md`（确认设备状态没变）
- [ ] 已备份 `boot_b_magisk.img`，并校验 sha256 与设备一致
- [ ] 已取得同版本 OTA 的 `stock_boot.img`（`magiskboot unpack` 能正常解析）
- [ ] 已确认构建机（GitHub Actions / Linux VM）可用，LLVM 工具链下载成功
- [ ] 已确认内核源码 checkout 到 `21b3312486b8`
- [ ] 构建后 `cat out/include/config/kernel.release` = `5.4.302-qgki-g21b3312486b8`
- [ ] 构建后 `grep CONFIG_KSU=y out/.config` 命中
- [ ] `new-boot.img` 用 `magiskboot unpack` 能二次解包、大小合规
- [ ] 刷入后按 `docs/06-verification.md` 逐项验收
- [ ] 保留 `boot_b_magisk.img` 与 `new-boot.img` 原件到电脑

## 5. 需要拍板的事（默认值已写进 env/device.env）

| 决策点 | 默认 | 可选项 |
|---|---|---|
| 构建环境 | GitHub Actions | Linux VM / 本机 Termux（不推荐） |
| SukiSU 分支 | `main`（kprobe，无需手改源码） | `builtin-new`（手动 hook，SUSFS 在这条线） |
| SUSFS 隐藏 | 第一阶段不开 | 第二阶段切换 builtin 分支 |
| 管理器 | Nova v3.0.0 | 无 |
| 刷入方式 | dd（免 PC） | fastboot（USB） |

## 6. 验收定义（"可用的内核"）

同时满足即视为交付成功：

1. 设备正常开机、无 bootloop；
2. `su -c id` 返回 uid 0，且管理器识别内核（KernelSU 已安装，版本 3.0.0）；
3. 厂商模块正常加载（Wi-Fi / 移动数据 / 通话 / 摄像头 / 触控 / 声音 冒烟通过）；
4. `dmesg` 无 `vermagic` / `disagrees about version` / `Unknown symbol` 报错；
5. 回退路径可用（刷回 `boot_b_magisk.img` 能恢复 Magisk root）。

任何一条不满足 → 按 `docs/07-troubleshooting.md` 处理；无法解决则回退并上报现象与日志。
