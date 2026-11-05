# 电脑与手机共用热词：先共用引擎，再做离线同步

## 目标和当前范围

你在电脑修改热词、别名、排除词和热词纠错算法后，手机测试尽可能立即用到同一版本。**相同词库并不保证不同 ASR 模型输出相同。** 当前桥接验证的是“同一段识别后的文字 → 热词纠错 → 中立 App 上下文的末尾标点处理 → 正则规则”。

此阶段尚未提供录音、ASR、数字识别前处理、LLM、跨设备音频识别一致性或手机断网模糊纠错。

## 实现

```text
桌面 CapsWriter（原有软件继续运行）
     ↑ 只读：hot / aliases / auto / rule / 纠错源码 / 部分配置
电脑 bridge/server.py
     ↑ 带配对码的局域网 HTTP，明文 LAN 测试
iPhone 主 App 或键盘的显式测试按钮
     ↓ 返回文本 + 词库版本 + 纠错源码版本 + 模式
机主先预览，再点击插入
```

适合自己的可信家庭网络，不要做公网端口转发。桥接默认只监听 `127.0.0.1`，需显式指定自己的 LAN IP 才允许手机访问。程序不自动改防火墙；若 Windows 首次提示，机主只为可信专用网络授权。

## 为什么不把 hot 文件放到公开 GitHub

个人词库可能包含人名、工作词汇和你的使用习惯。公开仓库只放示例。桥接读取你原目录的实际词库，不复制到仓库、不记录提交文本、不保存录音。

## 只读桌面适配器

- 使用本机 `PhonemeCorrector`、`RuleCorrector` 和 `HotwordManager.correct` 方法本身；不另写一套 Swift 模糊匹配。
- 不启动桌面客户端、不导入键盘钩子、不启动自动热词更新器、不创建缺失词库、不写日志到桌面目录。
- 每次请求检查受支持的源码、配置和四份词库内容，变更后在内存重建引擎。
- 读两遍确认文件内容稳定。持续变动或加载失败返回错误，手机保留原输入，不自动应用旧结果。
- 开启繁体转换时明确拒绝此适配器，避免悄悄声称完全一致。
- 桌面特定 App 强制去标点、LLM、数字处理前段等仍可能产生差别；响应 scope 显示边界。

后续可以在同一服务加入电脑现有 ASR，再由手机主 App 录音上传；这样模型也共用，但电脑必须开机且可连接。

## 本机启动

依赖：Python 3.11+，`pypinyin`、`rapidfuzz`。建议把依赖装到项目的私有目录，避免修改系统 Python。

```powershell
# 这些路径由你按实际项目目录填写；personal/private 目录不要提交 Git。
$taskRoot = 'C:\Users\YOURNAME\CodexShare\CapsWriter-iOS-ZeroFee-20261105'
$env:PYTHONPATH = "$taskRoot\private\python-deps"
python -B "$taskRoot\project\bridge\server.py" `
  --desktop 'C:\Users\YOURNAME\Desktop\CapsWriter-Offline\CapsWriter-v3' `
  --host 192.168.1.20 `
  --token-file "$taskRoot\private\bridge-token.txt"
```

把自己的 LAN 地址换进去。配对码仅打印在本地控制台，主 App 手动输入。Ctrl+C 停止。`--demo` 可用纯演示词，不读取桌面软件，响应明确显示 `demo-exact-aliases`。

## 下一阶段：独立离线手机

设计一个可导出的 `lexicon.json`：schemaVersion、词库版本、标准词、别名、排除词、纠错阈值、规则、来源、更新时间和校验值。电脑是唯一编辑源，手机单向下载并缓存；同步失败保留最后一个有效包。个人数据只走机主控制的私有通道或手动文件导入。

还需共享纠错算法版本和一组回归样本：同一输入及同一配置在两端输出一致才发布。Python 正则、Unicode、音素分词与 Swift/ICU 的差异不能只靠复制词库解决。第一阶段桥接保留原 Python 纠错，是验证这一点的基准。

## 版本解释

- `version`：四份词库内容的 SHA-256 截断标识。
- `source_version`：支持的纠错源码和配置内容标识，不代表整个 CapsWriter 安装版本。
- `mode`：真实桌面源码模式或明确标注的 demo 模式。
- 两端测试要比较这两个版本，以及同一输入。仅词条数相同不能证明内容相同。
