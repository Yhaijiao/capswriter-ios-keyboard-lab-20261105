# CapsWriter Lab — 零年费 iPhone 键盘实验

目标：在 iPhone 15 Pro Max / iOS 26.6.1 上验证第三方键盘安装、插入文字和免费签名续期。

v0.4.3 是零年费侧载实验版，支持语音 / EN / 拼音连续滑动与顶部点选。中英文四行按键位置一致，三页 Return 下沿对齐，空闲界面去除常驻操作提示。主 App 开启限时麦克风会话后，可在键盘开始、停止录音，最终识别结果自动上屏。拼音支持全拼、简拼、混拼组合、末音节补全和分段选字；删除键支持长按加速。Return 有待选拼音时先上屏，否则换行。

## 当前功能

- 原生 iOS 主 App＋键盘扩展，iOS 17+，不需要 App Groups。
- 类似参考截图的深色语音键盘布局，使用独立名称和系统图标。
- 英文大小写、数字标点、离线全拼组合、删除、空格、Return、地球键。
- 拼音词库约 3.1 万字词，最多保留 64 个拼音字母，提供最多 40 项候选。wom 可提供我们、我妈等组合，nihaom 可组合你好吗；长句可分段选字。候选栏横向滚动。
- 语境模型、个人词频学习和展开候选网格仍待后续开发；当前排序由公共词频、常见词种子和读音优先级决定。
- 主 App 内置测试文本区、启用键盘说明。
- 可选的局域网文字纠错测试：调用自己电脑现有的 CapsWriter 热词与规则源码，响应显示词库和源码版本。
- 无广告、统计、收费 API；基本键盘不需要“允许完全访问”。

## 安装

详细步骤见 [docs/INSTALL.zh-CN.md](docs/INSTALL.zh-CN.md)。

1. 在 Actions 下载 `CapsWriterLab-iPhone` 构建产物并解压。
2. 把 `CapsWriterLab-0.4.3-unsigned.ipa` 拖入官方下载的 Sideloadly。
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

见 [docs/SHARED-HOTWORDS.zh-CN.md](docs/SHARED-HOTWORDS.zh-CN.md)。文字纠错共用桌面实际源码。v0.3 新增可选的录音转发，调用桌面已运行的 ASR 和数字处理，再接同一热词/规则。尚不包含 LLM 与手机独立离线识别。详见 [真实语音实验](docs/VOICE.zh-CN.md)。

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
