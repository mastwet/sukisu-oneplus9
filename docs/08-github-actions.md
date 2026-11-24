# 08 · GitHub Actions 构建（推荐路径）

> 思路：内核编译外包给 GitHub Actions，本机只做「重打包 boot.img + 刷机」。
> 适用于不想在本机装 30G 工具链/源码、或本机内存不足跑 LTO 的情况。

## 1. 一次性准备：推到 GitHub

工作流已放在 `.github/workflows/build-kernel.yml`。把本仓库推到 GitHub 即可：

```bash
git init
git add -A
git commit -m "SukiSU kernel build handover"
git branch -M main
git remote add origin git@github.com:<你的用户名>/<仓库名>.git
git push -u origin main
```

- **公开仓库**：Actions 额度无限；
- **私有仓库**：免费 2000 分钟/月，单次构建约 30~60 分钟，够用。

## 2. 触发构建

1. 仓库页面 → **Actions** → 左侧 **build-sukisu-kernel-lemonade** → **Run workflow**；
2. 参数：
   - `jobs`：并行数，默认 `3`。若日志出现 OOM/被杀，降到 `2`；
   - `sukisu_tag`：默认 `v3.0.0`（必须与管理器 Nova v3.0.0 配套）。
3. 首次构建中，流水线会自动：
   - 腾磁盘（删 dotnet/android/ghc 等预装，防 `No space left`）；
   - 装依赖 + 下载 LLVM 21.1.0；
   - 拉内核源码并锁定 `21b3312486b8`；
   - 集成 SukiSU（自建 Git 优先，失败自动回退 GitHub 镜像）；
   - 编译 `Image` 并自检 `kernel.release == 5.4.302-qgki-g21b3312486b8`。

> 若失败，先看是哪一步：磁盘 → 加大腾盘/换 larger runner；OOM → 降低 `jobs`；SukiSU → 看是否走了 GitHub 兜底。

## 3. 下载产物

构建成功后，Actions 运行详情页底部 **Artifacts** → 下载 `kernel-image.zip`，解压得到：

```
Image                        ← 核心，交给 04-make-boot-image.sh
include/config/kernel.release
.config
System.map
build-meta.txt               ← 记录 commit / tag / clang / sha256
Image.sha256
```

**务必核对 `kernel.release`** = `5.4.302-qgki-g21b3312486b8`，否则厂商模块不匹配、别刷。

## 4. 重打包 + 刷机（回到本机）

产物 `Image` 放到本仓库的 `out/arch/arm64/boot/Image`（或用 `IMAGE=` 指定路径），然后按原流程：

```bash
# 先在 PC 上备份当前 Magisk boot（唯一回退保险）
bash scripts/00-backup-boot.sh

# 用同版本 OTA 的 stock_boot.img + 新 Image 重打包
STOCK_BOOT=stock_boot.img IMAGE=Image bash scripts/04-make-boot-image.sh

# 刷入（默认 dd 免 PC；或 FLASH_METHOD=fastboot）
bash scripts/05-flash.sh new-boot.img
```

验收见 `docs/06-verification.md`；失败回退 `bash scripts/05-flash.sh boot_b_magisk.img`。

## 5. 备注

- 免费 runner 规格有限（公开仓库通常 4 核/16G，根盘腾挪后约 30~40G），LTO 链接是单线程、吃内存；实在不够就把 `jobs` 降为 `2`，或换 GitHub larger runner / 自托管。
- 构建产物 `Image` 未压缩，约 30~60 MiB；`new-boot.img` 正常 60~120 MiB，必须 ≤ `BOOT_SIZE`（201326592 字节）。
- `ci/build-kernel.yml` 为原始版本，保留作对照；实际使用以 `.github/workflows/build-kernel.yml` 为准。
