# CapsWriter Lab — 零年费 iPhone 键盘实验

目标：在 iPhone 15 Pro Max / iOS 26.6.1 上验证第三方键盘安装、插入文字和免费签名续期。

v0.4.5 是零年费侧载实验版，支持语音 / EN / 拼音连续滑动与顶部点选。中英文四行按键位置一致，三页 Return 下沿对齐，空闲界面去除常驻操作提示。主 App 开启限时麦克风会话后，可在键盘开始、停止录音，最终识别结果自动上屏。拼音支持全拼、简拼、混拼组合、末音节补全和分段选字；删除键支持长按加速。Return 有待选拼音时先上屏，否则换行。

## 当前功能

- 原生 iOS 主 App＋键盘扩展，iOS 17+，不需要 App Groups。
- 类似参考截图的深色语音键盘布局，使用独立名称和系统图标。
- 英文大小写、数字标点、离线全拼组合、删除、空格、Return、地球键。
- 拼音词库约 3.1 万字词，最多保留 64 个拼音字母，提供最多 40 项候选。wom 可提供我们、我妈等组合，nihaom 可组合你好吗；长句可分段选字。候选栏支持横向滚动和下箭头展开网格。
- 语境模型和个人词频学习仍待后续开发；当前排序由公共词频、常见词种子和读音优先级决定。
- 缩小三页共同高度；语音页右下方打开热词管理，可读取五个词库并保存 hot.txt，检测版本冲突并保留备份。其他四个词库保持只读。
- 配置成功后，每次真正进入主 App 默认开启 10 分钟语音会话。iOS 键盘扩展本身没有麦克风权限，尚不能在冷启动状态一键完成开启会话和录音。
- 支持经过正常证书验证的公网 HTTPS 服务和电脑/云端 hot.txt 双向同步；云端使用同一份私有识别模型、数字处理和热词源码。
- 主 App 内置测试文本区、启用键盘说明。
- 可选的局域网文字纠错测试：调用自己电脑现有的 CapsWriter 热词与规则源码，响应显示词库和源码版本。
- 无广告、统计、收费 API；基本键盘不需要“允许完全访问”。

## 安装

详细步骤见 [docs/INSTALL.zh-CN.md](docs/INSTALL.zh-CN.md)。

1. 在 Actions 下载 `CapsWriterLab-iPhone` 构建产物并解压。
2. 把 `CapsWriterLab-0.4.5-unsigned.ipa` 拖入官方下载的 Sideloadly。
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

公开内容只包含新项目源码、演示短句和构建脚本。不上传桌面配置、热词、录音、测试文本、配对密钥、签名证书和账号信息。局域网桥接默认只绑定回环地址，手机测试需手动指定 LAN 地址。可选云端部署工具见 [部署说明](docs/CLOUD.zh-CN.md)，识别与网关端口保持回环绑定，通过带认证的 HTTPS 入口访问，不开放跨域访问。临时服务器的配对配置应带到期时间，防止实例停机释放地址后继续请求该地址。

## 官方参考

- [Apple 免费账号和 7 天描述文件](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Apple 第三方键盘权限](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [GitHub 标准运行器](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Sideloadly 官方 FAQ](https://sideloadly.io/faq)
