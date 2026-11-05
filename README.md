# CapsWriter Lab — 零年费 iPhone 键盘实验

目标：在 iPhone 15 Pro Max / iOS 26.6.1 上验证第三方键盘安装、插入文字和免费签名续期。

**这是键盘实验版，不是已完成的语音输入产品。** 大麦克风按钮插入固定测试文字，不录音。EN 提供基本小写字母与标点；“中”是中文示例输入，不是拼音输入法。Return 只插入换行，不模拟发送消息。

## 当前功能

- 原生 iOS 主 App＋键盘扩展，iOS 17+，不需要 App Groups。
- 类似参考截图的深色语音键盘布局，使用独立名称和系统图标。
- 插入中文示例、英文基本键、删除、空格、@、Return、地球键。
- 主 App 内置测试文本区、启用键盘说明。
- 可选的局域网文字纠错测试：调用自己电脑现有的 CapsWriter 热词与规则源码，响应显示词库和源码版本。
- 无广告、统计、收费 API；基本键盘不需要“允许完全访问”。

## 安装

详细步骤见 [docs/INSTALL.zh-CN.md](docs/INSTALL.zh-CN.md)。

1. 在 Actions 下载 `CapsWriterLab-iPhone` 构建产物并解压。
2. 把 `CapsWriterLab-0.1.0-unsigned.ipa` 拖入官方下载的 Sideloadly。
3. 使用自己的免费 Apple 账号在本地签名。**保留键盘扩展，不要移除 PlugIns。**
4. iPhone 信任电脑、启用开发者模式、按提示信任开发者。
5. 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → CapsWriter Lab。
6. 在备忘录或主 App 测试区，用地球键切换到本键盘，测试输入。

未签名 IPA 需要本地签名后才能安装，不支持在 Safari 点击即装。无需向项目作者或 CI 提供 Apple 密码。

## 免费构建

公开仓库使用 GitHub 标准 macOS runner。工作流仅编译未签名安装包，不接触 Apple 账号、个人词库或录音。私有仓库需要自行检查免费分钟配额。

本地 Mac 也可运行：

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project CapsWriterKeyboard.xcodeproj -scheme CapsWriterLab \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
```

## 电脑热词共用

见 [docs/SHARED-HOTWORDS.zh-CN.md](docs/SHARED-HOTWORDS.zh-CN.md)。第一阶段共用电脑上实际的热词纠错源码，避免另写 Swift 模糊匹配导致差异。此桥接只处理文字，尚未接入 ASR、数字处理前段或 LLM。

```sh
python -B bridge/server.py --demo
python -B -m unittest discover -s bridge -p 'test_*.py' -v
```

私人模式需要在本地安装 `bridge/requirements.txt` 并传入 `--desktop`。项目不包含上游源码、个人热词或模型权重。上游源码通过用户本机路径只读加载，执行代码前应信任自己的桌面安装。

## 免费续签的边界

- 免费个人签名通常 7 天到期，Sideloadly 自动刷新需要电脑与手机可连接。
- 首次 USB 配对、Apple 登录、手机信任与开发者模式需要机主操作。
- 过夜准备不能验证一整个 7 天续签周期；应另外记录手动刷新和跨日自动刷新结果。
- 系统密码输入框及拒绝第三方键盘的 App 无法使用本键盘。
- 本项目未承诺 App Store / TestFlight 分发、永久免续签、与商业产品相同的后台录音体验。

## 隐私与发布

公开内容只包含新项目源码、演示短句和构建脚本。不上传桌面配置、热词、录音、测试文本、配对密钥、签名证书和账号信息。局域网桥接默认只绑定回环地址，手机测试需手动指定 LAN 地址；不提供公网服务和跨域访问。

## 官方参考

- [Apple 免费账号和 7 天描述文件](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Apple 第三方键盘权限](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [GitHub 标准运行器](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Sideloadly 官方 FAQ](https://sideloadly.io/faq)
