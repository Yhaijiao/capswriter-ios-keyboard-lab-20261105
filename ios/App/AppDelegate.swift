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

final class LabViewController: UIViewController {
    private let editor = UITextView()
    private let address = UITextField()
    private let token = UITextField()
    private let status = Lab.label("未连接电脑 · 基本键盘输入无需联网", size: 14, color: Lab.muted)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CapsWriter Lab"
        view.backgroundColor = Lab.background
        let scroll = UIScrollView()
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
        stack.addArrangedSubview(Lab.label("v\(Lab.version) · 免费侧载实验版\n左滑循环切换：语音页 → EN → 拼音。支持英文大小写、数字标点与基础离线拼音选字。大麦克风按钮插入测试文字，不录音。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.label("1  启用键盘", size: 21))
        stack.addArrangedSubview(Lab.label("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → CapsWriter Lab。\n基础输入无需开启“允许完全访问”。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.button("打开 App 设置", symbol: "gearshape") {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        stack.addArrangedSubview(Lab.label("2  在这里试一试", size: 21))
        editor.text = "点击这里，长按地球键切换到 CapsWriter Lab。\n"
        editor.font = .systemFont(ofSize: 18)
        editor.textColor = .white; editor.backgroundColor = Lab.surface
        editor.layer.cornerRadius = 18; editor.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        editor.accessibilityIdentifier = "lab-editor"
        editor.heightAnchor.constraint(equalToConstant: 160).isActive = true
        stack.addArrangedSubview(editor)
        stack.addArrangedSubview(Lab.button("清空测试区", symbol: "trash") { [weak self] in self?.editor.text = "" })
        stack.addArrangedSubview(Lab.label("3  电脑热词一致性实验（可选）", size: 21))
        stack.addArrangedSubview(Lab.label("电脑启动 bridge/server.py 后，填入地址和配对码。两端请求同一个电脑纠错引擎，响应带词库及算法版本。\n此入口只处理你主动提交的测试文字。", size: 15, color: Lab.muted))
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
        stack.addArrangedSubview(Lab.label("4  免费安装与续签", size: 21))
        stack.addArrangedSubview(Lab.label("使用同一个 Apple 账号和相同 Bundle ID 续签。Sideloadly 中开启自动刷新，电脑保持运行并能找到手机。免费签名每 7 天到期；实际自动刷新需要跨日观察。\n如果过期，重新签名安装；先备份重要测试内容。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.label("隐私：无广告、无分析统计、无云端语音接口。主 App 与键盘设置独立保存，本版不依赖 App Groups。", size: 13, color: Lab.muted))
    }

    private func configure(_ field: UITextField, placeholder: String, key: String) {
        field.placeholder = placeholder; field.text = UserDefaults.standard.string(forKey: key)
        field.borderStyle = .roundedRect; field.autocorrectionType = .no
        field.autocapitalizationType = .none; field.font = .systemFont(ofSize: 16)
        field.heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
    private func connect(correct: Bool) {
        let a = address.text ?? "", t = token.text ?? ""
        UserDefaults.standard.set(a, forKey: "bridge.address")
        UserDefaults.standard.set(t, forKey: "bridge.token")
        status.text = "正在连接…"
        BridgeClient.request(address: a, token: t, text: correct ? editor.text : nil) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let reply):
                self.status.text = "模式：\(reply.mode ?? "未知")\n词库：\(reply.version ?? "未知")\n算法：\(reply.source_version ?? "未知")\n词条：\(reply.terms ?? 0)"
                if correct, let text = reply.text { self.editor.text = text }
            case .failure(let error): self.status.text = error.localizedDescription
            }
        }
    }
}
