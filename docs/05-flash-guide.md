# 05 · 重打包 boot、刷机与回退

> 顺序：备份 → 取 stock boot → 重打包 → 校验 → 刷入 → 验收。**未备份不得刷机。**

## 5.1 备份当前 boot_b（先做）

```bash
bash scripts/00-backup-boot.sh
# 产出：boot_b_magisk.img（当前 Magisk 内核，回退用）
```

手动等效命令：

```bash
adb shell su -c 'dd if=/dev/block/by-name/boot_b of=/sdcard/boot_b_magisk.img bs=1M conv=fsync'
adb pull /sdcard/boot_b_magisk.img .
adb shell su -c 'sha256sum /sdcard/boot_b_magisk.img'
sha256sum boot_b_magisk.img          # 两者必须一致
```

## 5.2 取 stock boot.img（重打包的底包）

**不能用**当前 Magisk 补丁过的镜像当底包（ramdisk 里带 magiskinit）。要从同版本 OTA 里取干净的 boot：

1. 打开 <https://download.lineageos.org/lemonade>，确认版本 `23.2-20260525-NIGHTLY-lemonade` 仍可下载（Nightly 滚动，若已下架可在镜像站按文件名检索，或下载当前 branch 的最近版本——**但内核源码提交必须与之对应**，见 §5.6）。
2. 解包 OTA zip 里的 `payload.bin`：

```bash
# payload-dumper-go（跨平台，GitHub releases 下载对应平台二进制）
payload-dumper-go -partitions boot lineage-23.2-20260525-NIGHTLY-lemonade.zip
# 或：先 unzip 出 payload.bin，再 payload-dumper-go -partitions boot payload.bin
```

产出 `boot.img`（干净 stock，约 60~120 MiB）。

3. 校验：

```bash
/data/adb/magisk/magiskboot unpack boot.img   # 在手机上跑（见 §5.3）；PC 上没有 magiskboot
```

若报错“不支持的格式”，说明提取的镜像不对（可能拿到的是 recovery 或增量包）。

## 5.3 重打包（在手机上用设备自带 magiskboot，最省事）

设备上已有 `/data/adb/magisk/magiskboot`（Magisk Kitsune 提供），直接用 adb 在手机端执行：

```bash
adb push stock_boot.img /sdcard/stock_boot.img
adb push out/arch/arm64/boot/Image /sdcard/Image

adb shell su -c 'rm -rf /data/local/tmp/repack && mkdir -p /data/local/tmp/repack \
  && cd /data/local/tmp/repack \
  && /data/adb/magisk/magiskboot unpack /sdcard/stock_boot.img \
  && cp /sdcard/Image kernel \
  && /data/adb/magisk/magiskboot repack /sdcard/stock_boot.img /sdcard/new-boot.img'

adb pull /sdcard/new-boot.img .
sha256sum new-boot.img
```

预期：`magiskboot unpack` 打印 header 信息（version 3、pagesize 4096 等）并生成 `kernel`、`ramdisk.cpio`、`dtb` 等文件；`repack` 生成 `new-boot.img`。

脚本封装：`STOCK_BOOT=stock_boot.img IMAGE=out/arch/arm64/boot/Image bash scripts/04-make-boot-image.sh`

## 5.4 刷机前校验

```bash
ls -l new-boot.img                       # 必须 ≤ 201326592 字节
adb shell su -c '/data/adb/magisk/magiskboot unpack /sdcard/new-boot.img'  # 能解包
adb shell getprop ro.boot.slot_suffix    # 必须是 _b（脚本会复核）
```

## 5.5 刷入（两种方式，任选）

### 方式 A：设备内 dd（免 PC，推荐）

```bash
adb shell su -c 'dd if=/sdcard/new-boot.img of=/dev/block/by-name/boot_b bs=1M conv=fsync'
# 回读校验（比较前 N 字节）
adb shell su -c 'head -c $(stat -c %s /sdcard/new-boot.img) /dev/block/by-name/boot_b | sha256sum'
adb shell su -c 'sha256sum /sdcard/new-boot.img'
```

两个 sha256 必须一致。然后 `adb reboot`。

### 方式 B：fastboot（PC，兜底/救砖）

```bash
adb reboot bootloader
fastboot devices
fastboot getvar current-slot      # 必须 b
fastboot flash boot_b new-boot.img
fastboot reboot
```

脚本：`bash scripts/05-flash.sh new-boot.img`（默认 dd，设 `FLASH_METHOD=fastboot` 走 B）。

## 5.6 首次启动预期

- 开机变慢（首次干净 ramdisk + 无 magiskinit），可能 2~3 分钟；
- 进入系统后 Magisk 失效（boot 是干净 ramdisk），**SukiSU 内核已生效**；
- 安装 Nova v3.0.0 管理器（`env/device.env` 有 URL 与 sha256）：
  ```bash
  adb install -r SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk   # 若版本号冲突见 07
  ```
- 打开管理器：应显示 KernelSU 已安装/版本 3.0.0；shell（或首选 App）授权 `su` 后 `su -c id` 应返回 uid 0；
- 成功后可选卸载 Magisk App（减少检测面）。

## 5.7 回退

```bash
# dd 方式
adb shell su -c 'dd if=/sdcard/boot_b_magisk.img of=/dev/block/by-name/boot_b bs=1M conv=fsync'
# 或 fastboot
fastboot flash boot_b boot_b_magisk.img && fastboot reboot
```

回退后应恢复 Magisk Kitsune root（`su -c id` 上下文 `u:r:magisk:s0`）。

## 5.8 OTA 之后

LineageOS OTA 会替换 boot（A/B 可能切槽）→ root 消失。处理：

```bash
bash scripts/06-post-ota-reflash.sh new-boot.img
# 或 fastboot 按新槽位重刷
```

**注意**：若 OTA 升级到了新的内核版本（`uname -r` 变化），旧 `new-boot.img` 不可再用——必须按新 release 串重新锁定提交、重新构建。每次 OTA 后先 `uname -r` 对比。
