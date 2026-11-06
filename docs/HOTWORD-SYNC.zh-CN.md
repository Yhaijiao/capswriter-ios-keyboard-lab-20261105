# 电脑与云端的 hot.txt 双向同步

`scripts/sync_hotwords.py` 在电脑运行，把明确指定的 `hot.txt` 与已配对的云端词库同步。手机在云端保存后，电脑下次轮询可拉取；电脑修改后，下次轮询可推送。同步不上传录音，也不修改其他桌面配置文件。

需要先由部署过程把同一份初始 `hot.txt` 放到云端。首次启动时两边内容一致，脚本才建立基线；首次内容不同会保存两份冲突副本并停止自动覆盖。CRLF/LF 和 UTF-8 BOM 差异不造成重复改写。

## 运行

先单次检查，再启动持续同步。配对令牌只从指定文件读取，不放在命令行。下列地址为示例，需替换为实际部署的 HTTPS 地址：

```powershell
python -B scripts/sync_hotwords.py `
  --endpoint https://voice.example.com `
  --token-file "$env:USERPROFILE\CodexShare\CapsWriter-iOS-ZeroFee-20261105\private\cloud-token.txt" `
  --desktop-hot-file "$env:USERPROFILE\Desktop\CapsWriter-Offline\CapsWriter-v3\hot.txt" `
  --state-dir "$env:USERPROFILE\CodexShare\CapsWriter-iOS-ZeroFee-20261105\private\hotword-sync" `
  --enable-desktop-save --once
```

确认单次结果后，移除 `--once`，可加 `--interval 10` 每 10 秒轮询。`--enable-desktop-save` 是明确允许写回电脑 `hot.txt` 的开关；未加时可以建立匹配基线或推送电脑改动，但不会拉取覆盖桌面文件。实际运行仍应遵守用户授予的单文件写入范围。

云端默认必须使用有效证书的 HTTPS。仅本机或私人局域网测试可显式使用 `--allow-lan-http`；公网 HTTP 不允许。HTTP 重定向一律拒绝，避免配对令牌被转发，或保存请求被重定向成读取请求。需要直接配置最终服务地址。

## 同步与冲突

- 只有电脑变化：使用已读到的云端版本号保存，云端版本变更会返回 409，脚本不会强行重试覆盖。
- 只有云端变化：使用电脑当前原始文件哈希保存，通过现有热词存储逻辑备份并原子替换。
- 两边都变化且内容一致：更新版本基线，不改写文件。
- 两边都变化且内容不同：保留当前两边内容，不更新旧基线，在状态目录保存冲突快照。

冲突时，查看 `state-dir/conflicts/` 中的 `desktop.txt` 和 `cloud.txt`。手动把需要的词合并，并让电脑和手机云端保存为相同内容；后续轮询会自动重新对齐。没有“自动以一方覆盖另一方”的默认策略。

状态目录还包含 `state.json`、进程锁和 `backups/`。日志只打印固定状态或错误码，不打印词条、配对令牌和服务器错误正文。备份与冲突副本包含私人热词，应留在 CodexShare 私有项目区域，不上传公开仓库。状态文件绑定指定的桌面路径与服务地址，换服务器应使用新状态目录。轮换配对令牌后重新启动同步进程。

多个进程不能同时使用同一状态目录。临时连接错误按间隔退避重试，连续相同状态不反复刷日志；进程被中断后系统会释放锁。`--once` 正常退出码为 0，冲突为 2，配置或服务错误为 1。

## 验证范围

20 项测试覆盖首次匹配/不匹配、两种单向变化、双向冲突、相同内容对齐、CRLF/BOM、版本 409、保存期间并发修改、原始文件备份、显式桌面写入开关、状态绑定和进程锁。HTTP 测试使用本机临时服务器验证真实桥接的读写接口、跨源重定向不转发令牌，以及错误日志不泄漏词条或令牌。测试文件全部为演示数据，测试目录在 CodexShare 内；未写入用户真实桌面词库。
