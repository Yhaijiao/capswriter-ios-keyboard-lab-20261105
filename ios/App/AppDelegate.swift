import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: LabViewController())
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class LabViewController: UIViewController, UITextViewDelegate {
    private let scroll = UIScrollView()
    private let editor = UITextView()
    private let address = UITextField()
    private let token = UITextField()
    private let voice = VoiceSession()
    private let voiceStatus = Lab.label("语音会话未开启 · 麦克风关闭", size: 14, color: Lab.muted)
    private let status = Lab.label("未连接电脑 · 基本键盘输入无需联网", size: 14, color: Lab.muted)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CapsWriter Lab"
        view.backgroundColor = Lab.background
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        let title = Lab.label("你的声音，\n从这里开始。", size: 34)
        title.font = .boldSystemFont(ofSize: 34)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(Lab.label("v\(Lab.version) · 免费侧载实验版\n语音由手机采集，在自己的电脑识别。支持英文输入、基础离线拼音与三页滑动切换。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.label("1  启用键盘", size: 21))
        stack.addArrangedSubview(Lab.label("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → CapsWriter Lab。\n基础输入无需开启“允许完全访问”。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.button("打开 App 设置", symbol: "gearshape") {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        stack.addArrangedSubview(Lab.label("2  在这里试一试", size: 21))
        editor.text = "点击这里，长按地球键切换到 CapsWriter Lab。\n"
        editor.delegate = self
        editor.font = .systemFont(ofSize: 18)
        editor.textColor = .white; editor.backgroundColor = Lab.surface
        editor.layer.cornerRadius = 18; editor.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        editor.accessibilityIdentifier = "lab-editor"
        editor.heightAnchor.constraint(equalToConstant: 160).isActive = true
        stack.addArrangedSubview(editor)
        stack.addArrangedSubview(Lab.button("清空测试区", symbol: "trash") { [weak self] in self?.editor.text = "" })
        stack.addArrangedSubview(Lab.label("3  连接自己的电脑", size: 21))
        stack.addArrangedSubview(Lab.label("电脑开启 CapsWriter 识别服务和语音桥接后，填入局域网地址与配对码。手机复用电脑模型、数字处理、热词和纠正规则。电脑修改热词后，下次请求自动重载。", size: 15, color: Lab.muted))
        configure(address, placeholder: "http://192.168.1.20:8765", key: "bridge.address")
        configure(token, placeholder: "电脑端配对码", key: "bridge.token")
        token.isSecureTextEntry = true
        stack.addArrangedSubview(address); stack.addArrangedSubview(token)
        stack.addArrangedSubview(Lab.button("检查电脑词库版本", symbol: "arrow.triangle.2.circlepath") { [weak self] in self?.connect(correct: false) })
        stack.addArrangedSubview(Lab.button("复制配对配置，交给键盘", symbol: "doc.on.doc") { [weak self] in
            guard let self = self else { return }
            let value = ["address": self.address.text ?? "", "token": self.token.text ?? ""]
            guard let data = try? JSONSerialization.data(withJSONObject: value),
                  let text = String(data: data, encoding: .utf8) else { return }
            UIPasteboard.general.setItems([["public.utf8-plain-text": "cwlab:v1:" + text]],
                                          options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
            self.status.text = "配对配置已复制，5 分钟后过期。切换键盘 → 电脑 → 粘贴配对配置。"
        })
        stack.addArrangedSubview(Lab.button("用电脑规则处理测试区文字", symbol: "text.badge.checkmark") { [weak self] in self?.connect(correct: true) })
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(Lab.label("4  开启语音会话", size: 21))
        stack.addArrangedSubview(Lab.label("先将配对配置交给键盘，并在键盘设置允许完全访问。\n开启后麦克风会持续工作，系统显示录音指示，10 分钟后自动关闭。只有在键盘点击开始、停止的片段会提交给电脑；待机声音丢弃，不保存录音。\n切回任意输入框：点击麦克风 → 看到正在录音后说话 → 点击停止 → 预览 → 插入文字。单段最长 60 秒。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.button("开启 10 分钟语音会话", symbol: "mic.fill") { [weak self] in
            guard let self = self else { return }
            self.view.endEditing(true); self.savePairing()
            self.voice.start(address: self.address.text ?? "", token: self.token.text ?? "")
        })
        stack.addArrangedSubview(Lab.button("关闭语音会话", symbol: "stop.circle") { [weak self] in self?.voice.stop() })
        voice.onStatus = { [weak self] text in self?.voiceStatus.text = text }
        stack.addArrangedSubview(voiceStatus)
        stack.addArrangedSubview(Lab.label("5  免费安装与续签", size: 21))
        stack.addArrangedSubview(Lab.label("使用同一个 Apple 账号和相同 Bundle ID 续签。Sideloadly 中开启自动刷新，电脑保持运行并能找到手机。免费签名每 7 天到期；实际自动刷新需要跨日观察。\n如果过期，重新签名安装；先备份重要测试内容。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.label("隐私：无广告、无统计。录音通过已配对的局域网电脑处理，不发到云端；当前局域网传输使用 HTTP，仅在可信的私人网络测试。主 App 与键盘设置独立，不依赖 App Groups。", size: 13, color: Lab.muted))
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardLayoutChanged),
            name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardLayoutChanged),
            name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    func textViewDidBeginEditing(_ textView: UITextView) { revealEditor() }
    @objc private func keyboardLayoutChanged() { revealEditor() }
    private func revealEditor() {
        guard editor.isFirstResponder else { return }
        view.layoutIfNeeded()
        scroll.scrollRectToVisible(editor.convert(editor.bounds, to: scroll).insetBy(dx: 0, dy: -12), animated: false)
    }

    private func configure(_ field: UITextField, placeholder: String, key: String) {
        field.placeholder = placeholder; field.text = UserDefaults.standard.string(forKey: key)
        field.borderStyle = .roundedRect; field.autocorrectionType = .no
        field.autocapitalizationType = .none; field.font = .systemFont(ofSize: 16)
        field.heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
    private func connect(correct: Bool) {
        let a = address.text ?? "", t = token.text ?? ""
        savePairing()
        status.text = "正在连接…"
        BridgeClient.request(address: a, token: t, text: correct ? editor.text : nil) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let reply):
                self.status.text = "模式：\(reply.mode ?? "未知")\n词库：\(reply.version ?? "未知")\n算法：\(reply.source_version ?? "未知")\n词条：\(reply.terms ?? 0)\n语音桥接：\(reply.voice_enabled == true ? "已启用" : "未启用") · 识别服务：\(reply.asr_ready == true ? "可连接" : "未连接")"
                if correct, let text = reply.text { self.editor.text = text }
            case .failure(let error): self.status.text = error.localizedDescription
            }
        }
    }
    private func savePairing() {
        let a = address.text ?? "", t = token.text ?? ""
        UserDefaults.standard.set(a, forKey: "bridge.address")
        UserDefaults.standard.set(t, forKey: "bridge.token")
    }
}
