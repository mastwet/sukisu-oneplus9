# 03 · 决策日志、风险与备选方案

## 1. 决策日志（已定 + 理由）

| # | 决策 | 理由 |
|---|---|---|
| D1 | 走"源码集成内核"而非 LKM | 5.4 qGKI 非 GKI 2.0，官方无 5.4 LKM 资产；非 GKI 官方只支持源码集成 |
| D2 | 内核提交锁定 `21b3312486b8` | 本机 release 串 `5.4.302-qgki-g21b3312486b8` 由该提交产出；换提交会导致 vermagic 不匹配、厂商模块加载失败 |
| D3 | SukiSU 分支用 `main`（kprobe） | 5.4 只需 `CONFIG_KPROBES=y` + `CONFIG_EXT4_FS=y`（都有），不用手改内核源码；builtin 手动 hook 留作第二阶段 |
| D4 | SukiSU 版本锁 `v3.0.0`，管理器用 Nova v3.0.0 | 版本必须配套；旧 4.x 内核源码已不可得（仓库改名、旧 release 下架） |
| D5 | `CONFIG_KSU=y` 内置 | `CONFIG_MODVERSIONS=y` 下 `.ko` 方式易出 CRC/vermagic 问题；内置最稳 |
| D6 | 保留 LTO/CFI 配置 | 厂商模块是 LTO/CFI 编译；关掉会拒绝加载 |
| D7 | 刷入默认 dd（免 PC），fastboot 兜底 | 当前槽 `_b`、已 root、bootloader 解锁，dd 写 block 设备可行；fastboot 作为保险 |
| D8 | 第一阶段不开 SUSFS | SUSFS 在 builtin 分支，需手动 hook；先拿到"能开机 + root 可用"的最小可用版本 |
| D9 | 用 LLVM 21.1.0 官方 tarball 构建 | 已验证可下载；与 ROM 使用的 clang r563880（LLVM 21）同代 |

## 2. 风险表

| 风险 | 影响 | 概率 | 缓解 |
|---|---|---|---|
| 厂商模块 vermagic/CRC 不匹配 | Wi-Fi/基带/摄像头等失效，甚至 bootloop | 中（若提交或配置不一致） | 锁提交 21b3312486b8；构建后核对 `kernel.release`；失败则一并重编并刷 `vendor_dlkm`（见 07） |
| LTO 链接 OOM（CI 小机器） | 构建失败 | 中 | 用 ≥16GB 机器/大 runner；`-j` 调低；加 swap |
| bootloop（kprobe 兼容问题） | 设备无法开机 | 中低 | 保留 `boot_b_magisk.img`，fastboot 刷回；先编"纯原版内核"验证工具链 |
| 管理器不识别内核 | 无法授权 | 中 | 内核/管理器版本配套；确认 `CONFIG_KSU=y` 生效 |
| 刷错槽位 | 更新错分区 / 无效 | 低 | 刷前 `getprop ro.boot.slot_suffix`；脚本自动判断 |
| dd 写坏 boot | 无法开机 | 低 | 写后回读 sha256 校验；fastboot 可救 |
| OTA 覆盖 boot | root 消失 | 必然（每次 OTA） | 保留 `new-boot.img`，OTA 后 `scripts/06-post-ota-reflash.sh` |
| userdebug 暴露 | 风控/检测 | 中 | 属 ROM 属性，非本次范围；SUSFS 第二阶段再谈 |

## 3. 备选方案（未被采用，供接手人了解）

1. **LKM**：不可行（无 5.4 KMI 资产；非 GKI 不支持）。
2. **社区现成内核包**（Telegram / Action-Build 产物）：OP9 不在主流 Action-Build 覆盖（那些面向 GKI2.0 机型）；来源不可校验、无法跟进 OTA，**不采用**。
3. **继续用 Magisk**：当前 Kitsune v30.7 已能用；若目标只是"root"，无需本工程。换 SukiSU 的收益是 SUSFS/App Profile/KPM/内置 Zygisk。
4. **先刷"纯原版内核"验证工具链**：把同一 defconfig（不加 KSU）编出的 Image 先刷一次，确认工具链/提交正确、设备能起，再加 KSU。**推荐作为排障手段**。
5. **本机 Termux 直接编**：理论可行（8 核 7.2G / 78G 空间），但需装 ~2GB clang 工具链、编译 1~2 小时、满载发热；**不推荐**，仅作为无其他机器的兜底。

## 4. 待接手人确认的开放问题

- [ ] 构建环境最终选哪个（Actions / VM / 其他）？
- [ ] 是否需要第二阶段加 SUSFS（builtin 分支 + 手动 hook）？
- [ ] 仓库里的 `new-boot.img` 是否需要制作 AnyKernel3 刷机包，方便 OTA 后一键重刷？
- [ ] 是否要在切到 SukiSU 后卸载 Magisk App（减少检测面）？
