# 06 · 验收清单（"可用的内核"定义）

> 刷入后逐项勾选；任何一项失败按 `docs/07-troubleshooting.md` 处理。

## A. 开机与系统

- [ ] 设备正常开机，无 bootloop / 无自动重启
- [ ] 能解锁进入桌面，触控正常
- [ ] 设置 → 关于手机：内核版本显示 `5.4.302-qgki-g21b3312486b8`

## B. SukiSU 内核

```bash
adb shell su -c id                     # uid=0(root)
adb shell su -c 'cat /proc/kallsyms | grep -c " t ksu"'   # 存在 ksu 符号（>0）
adb shell su -c 'ls -la /data/adb/ksu'                    # 目录出现
adb shell su -c 'cat /data/adb/ksu/kernel/version 2>/dev/null'  # 3.0.0（若路径存在）
adb shell dumpsys package com.sukisu.ultra | grep versionName   # v3.0.0
```

- [ ] 管理器显示 KernelSU：已安装（版本 3.0.0，非 "未安装"）
- [ ] `su` 授权流程正常（请求 → 弹窗 → 允许 → root）
- [ ] App Profile 页面可打开（无崩溃）

## C. 厂商模块（最关键，易翻车）

```bash
adb shell 'cat /proc/modules | wc -l'                 # 应有几十个模块
adb shell 'dmesg | grep -iE "vermagic|disagrees about version|Unknown symbol" | head'
adb shell 'dmesg | grep -iE "module.*(load|init).*fail" | head'
```

- [ ] `dmesg` 无 vermagic / version disagree / Unknown symbol 报错
- [ ] Wi-Fi 可开可连
- [ ] 移动数据（4G/5G）可用，能通话
- [ ] 摄像头前后均可用
- [ ] 声音（扬声器/听筒/麦克风）正常
- [ ] 指纹解锁正常
- [ ] 蓝牙可开
- [ ] （可选）NFC、热点

## D. 稳定性

- [ ] 重启 2 次仍正常
- [ ] 放置 10 分钟无 kernel panic / 无频繁重启（`dmesg | grep -iE "panic|oops|watchdog"` 为空）
- [ ] 电池/发热无异常飙升

## E. 回退验证（建议做一次）

- [ ] 刷回 `boot_b_magisk.img` 可正常开机并恢复 Magisk root
- [ ] 再刷回 `new-boot.img` 仍正常（证明双向可逆）

## F. 记录归档

把以下内容写进交接记录（`docs/08-handover-log.md` 可新建）：

```
构建时间 / 构建机 / 提交 21b3312486b8 / SukiSU tag v3.0.0
kernel.release 值
Image sha256 / new-boot.img sha256
刷入方式 / 槽位
验收结果（A~E 勾选）
遗留问题
```
