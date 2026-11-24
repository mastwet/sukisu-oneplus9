# OnePlus 9（LineageOS 23.2）× SukiSU 落地洞察报告

> 本报告基于 2026-11 对本机的实测（命令/属性/分区/内核配置），不依赖此前讨论的上下文。
> 结论先行：**要跑 SukiSU，需要重新编译内核并刷 boot 分区——但不需要重编整个 ROM。**
> 这台机器是 5.4 qGKI（Qualcomm GKI 1.0），不在 SukiSU 官方 LKM 支持范围（仅 5.10/5.15/6.1/6.12/6.18 KMI），5.4 只能"自己编内核"。前置条件全部满足，真正要准备的是构建环境和版本配套。

---

## 1. 本机画像（全部实测）

| 项目 | 实测值 | 备注 |
|---|---|---|
| 机型 | OnePlus 9（LE2110），OnePlus/OnePlus9 | `ro.product.*` |
| SoC | Qualcomm SM8350（lahaina，骁龙 888） | `ro.board.platform=lahaina` |
| 内核 | Linux 5.4.302-qgki-g21b3312486b8 | clang 21.0.0（r563880，LLVM 21），2026-05-25 构建 |
| 系统 | LineageOS 23.2 NIGHTLY（lemonade），Android 16（SDK 36.1），userdebug | `23.2-20260525-NIGHTLY-lemonade` |
| 槽位 | `_b` 激活（A/B 设备） | `ro.boot.slot_suffix=_b` |
| Bootloader | 已解锁 | `ro.boot.verifiedbootstate=orange` |
| 当前 root | **Magisk Kitsune v30.7**（`u:r:magisk:s0`，`su -c id` → uid 0） | `/data/adb/magisk` 完整，`magisk.db` 在 |
| SukiSU 管理器 | **com.sukisu.ultra v4.1.2 已安装（2026-05-25 23:16）但从未启动** | 无 `/data/data` 目录、无 `user_de` 目录 |
| 内核里的 KSU | **不存在**：无 `CONFIG_KSU`，`/proc/kallsyms` 无 `ksu_*` 符号 | 只有 `chksum_*` 之类误匹配 |
| 分区布局 | A/B：`boot_a/b`（sde16/sde43，各 192MiB）、`vendor_boot_a/b`、`dtbo`、`vbmeta`；**无 init_boot**（5.4 老布局） | `blockdev --getsize64 boot_b` = 201326592 字节，与设备树 `BOARD_BOOTIMAGE_PARTITION_SIZE` 一致 |
| 可用空间 | `/data` 78G 可用 / 共 102G | 够放内核源码与产物 |
| 硬件 | 8 核，7.2G RAM（约 8G 机型） | 内存偏紧，常驻内存较高 |

**内核配置关键项（`/proc/config.gz` 导出核对）**

```
CONFIG_KPROBES=y        CONFIG_KRETPROBES=y     CONFIG_KPROBES_QGKI=y
CONFIG_KALLSYMS=y       CONFIG_KALLSYMS_ALL=y
CONFIG_MODULES=y        CONFIG_MODULE_UNLOAD=y  # MODULE_SIG 未开启（可加载未签名 .ko）
CONFIG_EXT4_FS=y        CONFIG_OVERLAY_FS=y      CONFIG_HAVE_SYSCALL_TRACEPOINTS=y
没有：CONFIG_KSU / CONFIG_KPM / CONFIG_KSU_SUSFS
```

SukiSU（Nova）`main` 分支对非 GKI 内核的要求是 `CONFIG_KPROBES=y` + `CONFIG_EXT4_FS=y`，并推荐 `CONFIG_KRETPROBES`/`CONFIG_HAVE_SYSCALL_TRACEPOINTS` —— **这台全部满足**。

---

## 2. 为什么"装个 APK 点一下"跑不起来

SukiSU 官方（现为 **SukiSU Nova**，2026-11 改名）兼容性表写得很直白：

- **GKI 2.0（内核 5.10+）**：推荐 LKM（可加载内核模块）模式，管理器里一键装，不用编内核；
- **非 GKI / 老内核（≥4.14）**：**必须自己编译内核**，官方不提供非 GKI 的 boot 镜像。

官方 release 的 LKM 资产只有这些 KMI：`android12-5.10`、`android13-5.10`、`android13-5.15`、`android14-5.15`、`android14-6.1`、`android15-6.6`、`android16-6.12`、`android17-6.18` —— **没有 5.4**。

本机是 **5.4 qGKI**：Qualcomm 在 ACK 之外维护的 GKI 1.0 变体，不是 Android 官方 KMI。所以：

1. 用官方 LKM 资产 → 不匹配，装不上；
2. 自己编 `kernelsu.ko`（LKM）→ 仍要拉内核源码、配工具链、编出与 `-g21b3312486b8` vermagic 匹配的模块，**不比编内核省事**，且非 GKI 的 LKM 官方不支持；
3. **唯一官方路线 = 内核源码集成 + 编出 `Image` 换进 `boot.img`**。

---

## 3. 路线对比

| 路线 | 可行性 | 说明 |
|---|---|---|
| A. 内核源码集成（官方推荐） | ✅ 可行 | LineageOS 23.2 内核源码公开（`lineage-23.2` 分支），`setup.sh` 一行集成；编出 Image 重打包 boot 刷 `boot_b` |
| B. LKM 模块直装 | ❌ 不可行 | 无 5.4 KMI 资产；非 GKI 官方不支持 LKM |
| C. 找社区现成包 | ⚠️ 不建议 | GitHub 上 Action-Build 系列明确面向 GKI 2.0 机型，OP9 不在覆盖范围；Telegram 上的第三方包来源不可信、无校验、OTA 无法跟进 |

**推荐 A。** 所谓"改造"，就是把内核源码变成"自带 KSU 的内核"，再换掉 boot 镜像——与 GKI 手机"LKM 一键安装"是两套完全不同的流程。

---

## 4. 推荐方案（分步清单）

### 0) 先备份（关键，必须做）

```bash
# 当前 boot_b 是 Magisk 补丁版（可回退到 Magisk root）
su -c 'dd if=/dev/block/by-name/boot_b of=/sdcard/boot_b_magisk.img bs=1M'
# 拉到电脑保存；同时确认 fastboot 可用（BL 已解锁）
```

### 1) 管理器版本配套

已装的 v4.1.2 是 SukiSU **Ultra** 时代产物；项目已改名 **SukiSU Nova**（v3.0.0，旧 4.x release 已被隐藏）。内核集成代码要与管理器版本匹配，建议：

- 卸载当前 v4.1.2（其数据目录为空，无损失；同为 `com.sukisu.ultra` 包名，版本号 40545 → 35000 属降级，普通安装会被拒）；
- 安装 Nova **v3.0.0**：`SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk`
  （<https://github.com/SukiSU-Nova/SukiSU-Nova/releases/download/v3.0.0/SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk>，sha256 `1202adb8…d81ac85`）
- 若坚持 v4.1.2 管理器：编出的内核版本 3.0.0 会触发版本告警，部分功能可能受限，需实测。

### 2) 取内核源码（LineageOS 官方）

```bash
git clone -b lineage-23.2 https://github.com/LineageOS/android_kernel_oneplus_sm8350
# 设备树（sm8350-common）确认：TARGET_KERNEL_SOURCE := kernel/oneplus/sm8350
#                              TARGET_KERNEL_CONFIG := vendor/lahaina-qgki_defconfig
```

### 3) 集成 SukiSU（Nova main 分支，kprobe 方式，无需手改 5.4 源码）

在源码根目录执行官方脚本（会软链 `drivers/kernelsu` 并改 `drivers/Makefile`/`Kconfig`）：

```bash
curl -LSs "https://git.zako.shirkneko.top:20004/shirkneko/SukiSU/raw/branch/main/kernel/setup.sh" | bash -s builtin-new
```

然后在 `arch/arm64/configs/vendor/lahaina-qgki_defconfig` 加 `CONFIG_KSU=y`（`y` 内置，避免 `MODVERSIONS` 下 `.ko` 版本匹配问题）；按需：
- `CONFIG_KSU_SUSFS=y`：隐藏（SUSFS），SukiSU 的主要卖点；
- `CONFIG_KPM=y`：内核补丁模块（64 位内核，注意稳定性）。

### 4) 编译内核（环境二选一）

- **x86_64 Linux VM / 本地机器（推荐）**：Android prebuilt clang（r563880，LLVM 21）或等价工具链；
- **GitHub Actions**：写一个 workflow（checkout 源码 → 下载 clang → `make`），把产物 `Image` 当 artifact 取回。现成的 Action-Build 系列只面向 GKI2.0，需自写。

```bash
make O=out ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
     vendor/lahaina-qgki_defconfig
make O=out ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
     Image -j"$(nproc)"
```

### 5) 重打包 boot（用**同版本** OTA 里的干净 boot 做底包）

不要拿当前 Magisk 补丁过的 boot 当底包（会把 magiskinit 一起带进去）。

```bash
# 从 lineage-23.2-20260525-NIGHTLY-lemonade.zip 的 payload.bin 提取 stock boot.img
# （payload-dumper-go / extract-utils；也可从 LineageOS 下载页取同 build）
magiskboot unpack stock_boot.img      # 得到 kernel、ramdisk.cpio、dtb
cp out/arch/arm64/boot/Image kernel   # 替换内核
magiskboot repack stock_boot.img new-boot.img
```

### 6) 刷入并验证

```bash
fastboot flash boot_b new-boot.img
fastboot reboot
# 管理器里确认 kernel 已识别 → 授权 → su 可用
```

- 设备树参数已核对：header v3、pagesize 4096、boot 分区 192MiB、ramdisk LZ4；
- 当前槽 `_b`，刷 `boot_b` 生效；不要动 `vendor_boot`/`dtbo`/`vbmeta`（Magisk 已能启动，说明 vbmeta 已处于宽松状态）。

### 7) 回退路径

```bash
fastboot flash boot_b boot_b_magisk.img
```

保留"Magisk 版 boot"和"stock boot"两份，任何 bootloop 都能救回。

---

## 5. 风险清单

| 风险 | 说明 | 缓解 |
|---|---|---|
| LineageOS OTA 覆盖 boot | userdebug NIGHTLY 持续更新，每次 OTA 会替换 boot（A/B 切槽） | 保存 `new-boot.img`，更新后重刷；或改用 AnyKernel3 脚本化 |
| 版本不匹配 | 管理器 v4.1.2 vs 内核 3.0.0 | 统一用 Nova v3.0.0 配套 |
| 双 root 冲突 | 新 boot 带干净 ramdisk，Magisk 自动失效（等于卸载 Magisk），但 App 仍在 | 明确切换预期，可先备份 Magisk 方案 |
| 首次启动风险 | 非 GKI 集成可能 bootloop（kprobe 兼容性问题） | 备份 + fastboot 可回；先编同一 defconfig 的"纯原版内核"验证工具链 |
| 模块兼容 | 只换 boot 里的 Image，`vendor_dlkm` 里的厂商模块仍是旧产物 | 同源同配置构建，符号 CRC 通常不变；若模块加载失败需一并重编刷入 |
| 发热/电耗 | 内核编译在手机上跑会持续满载 | 用 VM/Actions 编，别在手机上硬编 |
| 检测面 | LineageOS userdebug 本身带调试属性 | SUSFS/KPM 可提升隐藏，但非万能 |

---

## 6. "本机能不能直接编？"

- 现状：本机 shell 有 `make`/`git`/`python3`/`pkg`，但**没有 clang/gcc/lld**；需要 `pkg install clang lld llvm` 等（约 1–2GB），再拉 2–3GB 内核源码；
- 理论可行：麒麟/骁龙手机上"Termux 编内核"是成熟折腾路线，8 核 7.2G 内存、78G 空间足够，编译约 1–2 小时；
- 但 LineageOS 官方用 x86_64 宿主 prebuilt clang，本机是 aarch64 宿主，需换 Termux clang 21，工具链兼容性要自己趟；手机满载发热、电量、误触断连风险高；
- **结论：能用，不推荐。** 优先 GitHub Actions 或任意 x86_64 Linux 机器。

---

## 7. 需要拍板的事项

1. **管理器**：是否切换到 Nova v3.0.0（推荐），还是保留 v4.1.2 硬试？
2. **构建环境**：GitHub Actions（推荐）／自有 Linux 机器／就在本机 Termux 硬编？
3. **要不要 SUSFS/KPM**：只求 root，还是也要隐藏/内核补丁模块？
4. **目标**：如果只是要"能 root"，当前 Magisk Kitsune 已够用；换 SukiSU 的收益是 SUSFS 隐藏、App Profile 隔离、KPM、管理器/模块生态——收益与折腾成本请权衡。

---

## 附：本次实测证据（可复现）

```text
uname -a            → Linux localhost 5.4.302-qgki-g21b3312486b8 #1 SMP PREEMPT ... aarch64 Android
su -c id            → uid=0(root) ... context=u:r:magisk:s0
magisk -V           → 30700（v30.7-kitsune）
pm list packages    → com.sukisu.ultra（v4.1.2，2026-05-25 安装）；io.github.x0eg0.magisk
dumpsys package     → com.sukisu.ultra versionName=v4.1.2
ls /data/data/com.sukisu.ultra → 不存在（从未启动）
zcat /proc/config.gz | grep -E 'KSU|KPROBES|KALLSYMS|EXT4_FS|MODULES' → 无 CONFIG_KSU；其余齐全
grep -i ksu /proc/kallsyms → 仅 chksum_* 误匹配，无 ksu_* 符号
getprop             → lineage_lemonade-userdebug，23.2-20260525-NIGHTLY-lemonade，slot _b，verifiedbootstate=orange
blockdev --getsize64 /dev/block/by-name/boot_b → 201326592（= 设备树 BOARD_BOOTIMAGE_PARTITION_SIZE）
```

参考来源：
- SukiSU Nova 集成文档：<https://sukisu.org/guide/how-to-integrate>
- SukiSU Nova 仓库/兼容性说明：<https://github.com/SukiSU-Nova/SukiSU-Nova>
- KernelSU 非 GKI 集成指南（kprobe 方式参考）：<https://kernelsu.org/guide/how-to-integrate-for-non-gki.html>
- LineageOS 内核源码（lemonade/sm8350）：<https://github.com/LineageOS/android_kernel_oneplus_sm8350/tree/lineage-23.2>
