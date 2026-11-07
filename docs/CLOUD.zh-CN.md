# 可选私人云端识别

云端保留同一套私人 CapsWriter 模型、数字处理和热词源码；公开仓库仅提供启动、校验、HTTPS 和同步工具，不包含这些私人文件。此方式需要服务器费用，与免费的 Apple 个人签名是两件事。

## 准备和启动

1. 核对实例类型、按小时价格、磁盘、IPv4、额度适用性及试验预算。`cloud/pricing-ohio.json` 是指定时间的价格快照，后续应重新核对。
2. 使用 Ubuntu 24.04 x86_64。SSH 只放行管理者地址，公网只开放 80/443；6016 和 8765 始终监听回环地址。
3. 使用 `cloud/export_private.py` 导出经过清理的私人源码、必要热词及模型哈希。按导出清单传输模型，使用 `cloud/unpack_private.py` 解包并校验。禁止把导出内容加入公开仓库。
4. 将公开 `bridge/`、`cloud/` 放到 `/srv/capswriter/app`，私人导出放到 `/srv/capswriter/private/desktop`。
5. 用户确认 EC2 的 Shutdown behavior 为 Stop 后，安装 `cloud/install_trial_guard.sh --confirmed-shutdown-behavior=stop`。它安排 22 小时后关机，已有截止时间不会被延长。停止实例不会删除或停止收取 EBS 费用。
6. 用户接受 Let's Encrypt 协议后运行 `cloud/install_tls.sh`（先查看其参数）。IP 证书为短期证书，必须保持续期任务和 80 端口可用。
7. 运行 `sudo bash /srv/capswriter/app/cloud/install.sh`。固定版本的官方 Linux 原生库会安装到各识别绑定各自的 `bin` 目录。预检校验模型、源码和导入，随后必须通过真实合成语音识别探针；只有探针成功才让网关声明就绪。

识别与网关均由 systemd 管理，重启后重新运行真实语音探针。服务不记录音频、转写或请求体；配对密钥保存在服务器私有文件中。HTTPS 必须使用正常证书验证，不能跳过验证。

## 手机配对与临时服务器

在 Lab 的「连接识别服务」选择「家里电脑」或「AWS 云端」，输入地址和配对码后点「保存配对并检查连接」，也可用 `capswriterlab://pair?address=...&token=...&expires=...` 二维码更新当前所选服务。两份配对独立保存，键盘从共享钥匙串读取当前选择。首次切换前，给 CapsWriter 键盘开启完全访问并打开一次键盘。切换时已有语音会话结束，下一段交给所选服务。AWS 实例在 AWS 控制台手动启停。二维码和配对密钥只保存在私人目录。

Lab 和 CapsWriterKeyboard 签名时需要同一个 `keychain-access-groups` 条目 `$(AppIdentifierPrefix)org.capswriterlab.voice-pairings`，并将其放在各自访问组列表的第一项。`-sideload.ipa` 在两个可执行文件中带有 `CAPSWTEST0` 占位前缀，仍需用你的 Apple ID 重签。重签工具须保留后缀并替换占位前缀，安装时保留键盘与实时活动扩展。SideStore 的 [签名库源码](https://github.com/SideStore/SideSign/blob/main/Sources/CodeSigning/CodeSignerAPI.swift) 包含这项处理，具体侧载版本和真机仍待实测。Sideloadly 免费版能否自动保留此组尚未验证。用 Xcode 签名时可直接对两个目标选择同一团队。签名器未保留共享能力时，Lab 会停用切换；从未使用共享配置的安装可继续旧版单服务配对流程。

`expires` 是 Unix 秒时间戳。试验配对需在实例停机释放公网地址之前到期；到期后 App 和键盘拒绝发起请求。电脑同步也应传入同样的 `--expires-at`，到期即停止。正式长期运行需另行确定稳定地址、预算和备份安排。

## 热词共用

见 [热词同步](HOTWORD-SYNC.zh-CN.md)。手机能读取五个文件，只有 `hot.txt` 可以保存。保存检查版本、备份原始内容并原子替换，冲突时保留双方版本。电脑同步只读写明确授权的 `hot.txt`，状态、备份、冲突副本放在单独的私人目录。

云端语音成功不等于手机公网录音已经验收。发布前分别检查正常 TLS、未授权 401、完整语音提交、热词版本冲突、同步；安装后还需在手机关闭 Wi-Fi，使用移动网络录音并确认自动上屏。
