# 02 · SukiSU 原理与两种集成形态

## 1. 一句话

SukiSU（现名 **SukiSU Nova**）是 KernelSU 的社区分支：**root 能力做进内核**（hook `execve` 等系统调用，在内核态按策略把进程凭据提升为 root），管理器 App 与 `ksud` 只做授权 UI/辅助。这与 Magisk 的"ramdisk 注入 + magiskd 用户态守护"是两条路。

## 2. 与 Magisk 的对比

| | Magisk Kitsune（本机现状） | SukiSU Nova（目标） |
|---|---|---|
| root 产生 | 用户态守护进程 magiskd | 内核 hook + 内核侧 allowlist |
| 启动依赖 | 必须改 boot ramdisk（magiskinit） | 内置模式不需要改 ramdisk |
| 授权 | magiskd 查库弹窗 | 内核裁决，ksud/管理器辅助 |
| 隐藏 | DenyList + Zygisk + 挂载面 | App Profile + SUSFS（文件/挂载/进程级） |
| 模块 | overlayfs | overlayfs，兼容 Magisk 模块（部分不通用） |

## 3. 核心机制

1. **sucompat / execve hook**：进程执行 `su` → 内核 hook 截获 → 未授权转 `ksud`（用户态）→ socket 通知管理器 → 用户允许后写入 allowlist → 内核按 App Profile 提权（uid/gid/groups/capabilities/SELinux 上下文）。
2. **app_profile**：每个 App 可配独立 profile，实现"隔离 root"。
3. **文件/挂载隐藏**：模块经 overlayfs 挂载；对目标 App，内核在 `stat`/`access`/`read` 等 hook 里隐藏 su 路径、模块文件、挂载点。SUSFS 是增强版。
4. **模块系统**：`/data/adb/ksu` 下模块，开机由 ksud 处理；**KPM**（Kernel Patch Module）需要 `CONFIG_KPM=y`。
5. **安全模式**：输入 hook（音量键）在启动时触发，禁用模块防 bootloop。

## 4. 两种集成形态（对应"装法"）

| 形态 | 适用 | 做法 |
|---|---|---|
| **LKM** | GKI 2.0（内核 5.10+） | 内核本体不动，`kernelsu.ko` 由 ksud 在 init 阶段加载；管理器一键打补丁 |
| **源码集成** | 非 GKI（≤5.9，本机 5.4） | `CONFIG_KSU=y` 编进 `Image`；hook 用 kprobe（main 分支）或手动 hook（builtin 分支） |

**本机 5.4 qGKI 属第二种。** 官方 release 的 LKM 资产只覆盖 `android12-5.10 / android13-5.10 / android13-5.15 / android14-5.15 / android14-6.1 / android15-6.6 / android16-6.12 / android17-6.18`，**没有 5.4**。

## 5. 两个分支怎么选

| 分支 | hook 方式 | 适合 |
|---|---|---|
| `main`（默认） | kprobe/kretprobe + sys_enter tracepoint，运行时注册，**不改内核源码 hook 点** | 本机首选（5.4 不需要手改 fs/exec.c 等） |
| `builtin` / `builtin-new` | 手动 hook：需在 `fs/exec.c`、`fs/open.c`、`fs/read_write.c`、`fs/stat.c`、`drivers/input/input.c` 等处加调用 | 想要 SUSFS 全套 / 精细控制；工作量大、需按 5.4 对齐补丁 |

**决策：第一阶段用 `main` 分支（kprobe）**。SUSFS 在 builtin 分支线，作为第二阶段可选（见 `docs/03`）。

## 6. SukiSU 版本匹配

- 内核侧版本由仓库 tag 决定：本包锁定 **`v3.0.0`**（仓库 `git ls-remote` 实测存在 `v3.0.0` / `v3.0.0-r1` / 分支 `main`、`builtin`、`builtin-new`）；
- 管理器必须配套：**Nova v3.0.0**（`com.sukisu.ultra`，versionCode 35000）。本机现有 v4.1.2 是旧 Ultra 版本，版本号更高但内核代码不配套，**需先卸载再装 Nova**（其 data 目录为空，卸载无损失）。

## 7. 为什么本机不能"LKM 一键装"

1. LKM 资产按官方 KMI 发布，5.4 qGKI 不在列表；
2. 非 GKI 的 LKM 官方不支持（需自编 .ko，仍要内核源码与匹配工具链，不省事）；
3. 因此唯一正路 = 源码集成 + 编 `Image` + 换 boot 镜像。

## 8. 产物长什么样

内核 `Image`（`BOARD_KERNEL_IMAGE_NAME := Image`，header v3、pagesize 4096）→ 与同版本 OTA 的 stock boot `ramdisk` 重打包成 `boot.img` → 刷 `boot_b`。系统其余分区不动；`vendor_dlkm` 里的厂商模块继续复用（前提：release 串一致，见 README 硬性约束 1）。
