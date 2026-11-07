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
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme == "capswriterlab", url.host == "pair",
              let navigation = window?.rootViewController as? UINavigationController,
              let controller = navigation.viewControllers.first as? LabViewController else { return false }
        controller.offerPairing(url); return true
    }
}

final class LabViewController: UIViewController, UITextViewDelegate {
    private let scroll = UIScrollView()
    private let editor = UITextView()
    private let address = UITextField()
    private let token = UITextField()
    private let updateStatus = Lab.label("", size: 14, color: Lab.muted)
    private let bridgeTarget = UISegmentedControl(items: BridgeTarget.allCases.map(\.title))
    private let bridgeSwitchStatus = Lab.label("", size: 14, color: Lab.muted)
    private var profiles: BridgeProfiles?
    private var connectionRequest = UUID()
    private let voice = VoiceIntentCoordinator.shared.session
    private let automaticSession = UISwitch()
    private let recognitionMode = UISegmentedControl(items: ["识别服务", "手机中文", "手机英文"])
    private let duration = UISegmentedControl(items: ["10 分钟", "30 分钟", "60 分钟"])
    private var autoStartPolicy = VoiceSessionAutoStartPolicy()
    private let voiceStatus = Lab.label("语音会话未开启 · 麦克风关闭", size: 14, color: Lab.muted)
    private let status = Lab.label("未连接识别服务 · 基本键盘输入无需联网", size: 14, color: Lab.muted)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CapsWriter Lab"
        UserDefaults.standard.register(defaults: ["voice.autoStart": true])
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
        stack.addArrangedSubview(Lab.label("v\(Lab.version) · 免费侧载实验版\n手机采集语音，交给你配对的识别服务处理。支持英文输入、离线拼音与三页滑动切换。", size: 15, color: Lab.muted))
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
        stack.addArrangedSubview(Lab.label("3  连接识别服务", size: 21))
        stack.addArrangedSubview(Lab.label("家里电脑和 AWS 各保存一份配对，键盘跟随 Lab 的选择。请在 AWS 控制台启停实例。局域网可用 HTTP，公网必须用 HTTPS。", size: 15, color: Lab.muted))
        bridgeTarget.accessibilityIdentifier = "bridge-target"
        bridgeTarget.addTarget(self, action: #selector(bridgeTargetChanged), for: .valueChanged)
        stack.addArrangedSubview(bridgeTarget)
        bridgeSwitchStatus.isHidden = true
        stack.addArrangedSubview(bridgeSwitchStatus)
        configure(address, placeholder: "http://局域网IP 或 https://服务器IP")
        address.keyboardType = .URL
        configure(token, placeholder: "识别服务配对码")
        token.isSecureTextEntry = true
        stack.addArrangedSubview(address); stack.addArrangedSubview(token)
        stack.addArrangedSubview(Lab.button("保存配对并检查连接", symbol: "arrow.triangle.2.circlepath") { [weak self] in self?.connect(correct: false) })
        let legacyCopy = Lab.button("复制旧版键盘配对配置", symbol: "doc.on.doc") { [weak self] in
            guard let self = self else { return }
            guard let pairing = self.savePairing() else { return }
            guard !pairing.isExpired() else { self.status.text = "试验服务器配置已到期，请更新配对配置。"; return }
            var value = ["address": pairing.address, "token": pairing.token]
            if let expiry = pairing.expires { value["expires"] = String(expiry) }
            guard let data = try? JSONSerialization.data(withJSONObject: value),
                  let text = String(data: data, encoding: .utf8) else { return }
            UIPasteboard.general.setItems([["public.utf8-plain-text": "cwlab:v1:" + text]],
                                          options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
            self.status.text = "配对配置已复制，5 分钟后过期。键盘 → 热词 → 齿轮 → 粘贴配对配置。"
            self.beginAutomaticSessionIfNeeded()
        }
        stack.addArrangedSubview(legacyCopy)
        loadBridgeProfiles()
        legacyCopy.isHidden = profiles != nil || BridgePairingStore.hasUsedSharedProfiles
        stack.addArrangedSubview(Lab.button("用服务规则处理测试区文字", symbol: "text.badge.checkmark") { [weak self] in self?.connect(correct: true) })
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(Lab.label("4  开启语音会话", size: 21))
        stack.addArrangedSubview(Lab.label("保存配对配置后，打开 Lab 自动开启 10 分钟语音会话，无需选择时长或再点开启；已有会话沿用原计时。\n开启期间麦克风持续工作，系统显示录音指示；只有键盘主动开始、停止的片段会提交识别，待机声音丢弃。\n回到输入框：点击麦克风 → 看到正在录音后说话 → 停止 → 识别完成后自动上屏。单段最长 5 分钟。", size: 15, color: Lab.muted))
        automaticSession.isOn = UserDefaults.standard.bool(forKey: "voice.autoStart")
        automaticSession.accessibilityIdentifier = "voice-auto-start"
        automaticSession.addTarget(self, action: #selector(automaticSessionChanged), for: .valueChanged)
        let autoRow = UIStackView(arrangedSubviews: [Lab.label("打开 Lab 自动开启 10 分钟", size: 16), automaticSession])
        autoRow.axis = .horizontal; autoRow.spacing = 12; autoRow.alignment = .center
        stack.addArrangedSubview(autoRow)
        stack.addArrangedSubview(Lab.label("识别方式 · 手机为可撤回实验", size: 16))
        let savedMode = UserDefaults.standard.string(forKey: "voice.recognitionMode") ?? "cloud"
        recognitionMode.selectedSegmentIndex = ["cloud", "phone-zh", "phone-en"].firstIndex(of: savedMode) ?? 0
        recognitionMode.accessibilityIdentifier = "voice-recognition-mode"
        recognitionMode.addTarget(self, action: #selector(recognitionModeChanged), for: .valueChanged)
        stack.addArrangedSubview(recognitionMode)
        stack.addArrangedSubview(Lab.label("手机模式由 Apple 本地识别，首次需准备语言模型；文字仍交给所选服务应用热词。点“识别服务”可切回服务端识别。", size: 13, color: Lab.muted))
        stack.addArrangedSubview(Lab.label("也可手动选择时长并重新开启：", size: 14, color: Lab.muted))
        let savedMinutes = UserDefaults.standard.integer(forKey: "voice.sessionMinutes")
        duration.selectedSegmentIndex = [10, 30, 60].firstIndex(of: savedMinutes) ?? 0
        duration.accessibilityIdentifier = "voice-session-duration"
        stack.addArrangedSubview(duration)
        stack.addArrangedSubview(Lab.button("手动开启 / 重新计时", symbol: "mic.fill") { [weak self] in
            guard let self = self else { return }
            self.view.endEditing(true)
            guard let pairing = self.savePairing() else { return }
            self.autoStartPolicy.userStoppedOrStarted()
            let minutes = [10, 30, 60][max(0, min(2, self.duration.selectedSegmentIndex))]
            UserDefaults.standard.set(minutes, forKey: "voice.sessionMinutes")
            if self.voice.active || self.voice.starting { self.voice.stop(message: "正在重新开启语音会话…") }
            self.voice.start(pairing: pairing, sessionMinutes: minutes)
        })
        stack.addArrangedSubview(Lab.button("关闭本次语音会话", symbol: "stop.circle") { [weak self] in
            guard let self = self else { return }
            self.autoStartPolicy.userStoppedOrStarted()
            self.voice.stop(message: self.automaticSession.isOn ? "本次语音会话已关闭。重新打开 Lab 时会自动开启；也可关闭上方自动开关。" : "语音会话已关闭，麦克风已停止。")
        })
        voice.onStatus = { [weak self] text in self?.voiceStatus.text = text }
        stack.addArrangedSubview(voiceStatus)
        stack.addArrangedSubview(Lab.label("5  更新与续签", size: 21))
        stack.addArrangedSubview(Lab.label("首次用电脑设置 SideStore 后，连 Wi-Fi 和 LocalDevVPN，点下方按钮可安装最新实验版。免费签名仍需每 7 天续签。", size: 15, color: Lab.muted))
        stack.addArrangedSubview(Lab.button("用 SideStore 安装更新", symbol: "arrow.down.app") { [weak self] in self?.openSideStoreUpdate() })
        stack.addArrangedSubview(updateStatus)
        stack.addArrangedSubview(Lab.label("隐私：无广告、无统计。仅连接你确认配对的识别服务。公网使用 HTTPS；局域网 HTTP 仅用于可信网络。配对保存在本机，热词仅在你点击保存时写回。", size: 13, color: Lab.muted))
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardLayoutChanged),
            name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardLayoutChanged),
            name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        beginAutomaticSessionIfNeeded()
    }

    @objc private func appBecameActive() { beginAutomaticSessionIfNeeded() }
    @objc private func appEnteredBackground() { autoStartPolicy.enteredBackground() }
    @objc private func recognitionModeChanged() {
        let value = ["cloud", "phone-zh", "phone-en"][max(0, min(2, recognitionMode.selectedSegmentIndex))]
        UserDefaults.standard.set(value, forKey: "voice.recognitionMode")
        voice.stop(message: "识别方式已切换，正在准备新的语音会话…")
        autoStartPolicy.configurationChanged()
        guard let pairing = savePairing() else { return }
        voice.start(pairing: pairing,
                    sessionMinutes: [10, 30, 60][max(0, min(2, duration.selectedSegmentIndex))])
    }
    @objc private func automaticSessionChanged() {
        UserDefaults.standard.set(automaticSession.isOn, forKey: "voice.autoStart")
        if automaticSession.isOn {
            autoStartPolicy.configurationChanged(); beginAutomaticSessionIfNeeded()
        } else {
            autoStartPolicy.userStoppedOrStarted()
            voice.stop(message: "自动开启已关闭，麦克风已停止。需要时可手动开启。")
        }
    }
    private func beginAutomaticSessionIfNeeded() {
        guard let pairing = BridgePairingStore.activePairing(), !pairing.isExpired() else { return }
        let visible = isViewLoaded && view.window != nil && UIApplication.shared.applicationState == .active
        guard autoStartPolicy.shouldStart(enabled: automaticSession.isOn,
            configured: true, foreground: visible,
            busy: voice.active || voice.starting) else { return }
        voice.start(pairing: pairing, sessionMinutes: 10)
    }

    func textViewDidBeginEditing(_ textView: UITextView) { revealEditor() }
    @objc private func keyboardLayoutChanged() { revealEditor() }
    private func revealEditor() {
        guard editor.isFirstResponder else { return }
        view.layoutIfNeeded()
        scroll.scrollRectToVisible(editor.convert(editor.bounds, to: scroll).insetBy(dx: 0, dy: -12), animated: false)
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect; field.autocorrectionType = .no
        field.autocapitalizationType = .none; field.font = .systemFont(ofSize: 16)
        field.heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
    func offerPairing(_ url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let values = parts.queryItems ?? []
        guard let a = values.first(where: { $0.name == "address" })?.value,
              let t = values.first(where: { $0.name == "token" })?.value,
              t.count >= 24, t.count <= 128, BridgeClient.isValidToken(t),
              let endpoint = BridgeEndpoint(address: a) else { return }
        let expiry = values.first(where: { $0.name == "expires" })?.value
        if let expiry, Double(expiry) == nil { return }
        guard let pairing = BridgePairing(address: endpoint.normalizedAddress, token: t, expires: expiry.flatMap { Double($0) }) else { return }
        let target = profiles?.selected
        let alert = UIAlertController(title: "配对\(target?.title ?? "识别服务")", message: "服务器：\(pairing.address)\n请确认这是你自己的服务器。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "使用此服务", style: .default) { [weak self] _ in
            guard let self, self.profiles?.selected == target else { return }
            guard !pairing.isExpired() else { self.status.text = "试验服务器配置已到期，请更新配对配置。"; return }
            if self.persist(pairing) { self.checkConnection(pairing, correct: false) }
        })
        present(alert, animated: true)
    }
    private func connect(correct: Bool) {
        guard let pairing = savePairing() else { return }
        checkConnection(pairing, correct: correct)
    }

    private func checkConnection(_ pairing: BridgePairing, correct: Bool) {
        let request = UUID(); connectionRequest = request
        let title = profiles?.selected.title ?? "识别服务"
        status.text = "正在连接…"
        BridgeClient.request(pairing: pairing, text: correct ? editor.text : nil) { [weak self] result in
            guard let self, self.connectionRequest == request else { return }
            switch result {
            case .success(let reply):
                let ready = reply.voice_enabled == true && reply.asr_ready == true
                self.status.text = "\(title) · \(ready ? "已就绪" : "语音服务未就绪")\n词库：\(reply.version ?? "未知") · 词条：\(reply.terms ?? 0)"
                if correct, let text = reply.text { self.editor.text = text }
                if !correct { self.beginAutomaticSessionIfNeeded() }
            case .failure(let error): self.status.text = "\(title) · \(error.localizedDescription)"
            }
        }
    }
    private func savePairing() -> BridgePairing? {
        let rawAddress = (address.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let t = (token.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = BridgeEndpoint(address: rawAddress) else {
            status.text = BridgeError.invalidAddress.localizedDescription; return nil
        }
        let current = BridgePairingStore.activePairing()
        let expiry = current?.address == endpoint.normalizedAddress ? current?.expires : nil
        guard let pairing = BridgePairing(address: endpoint.normalizedAddress, token: t, expires: expiry) else {
            status.text = BridgeError.invalidToken.localizedDescription; return nil
        }
        return persist(pairing) ? pairing : nil
    }

    private func persist(_ pairing: BridgePairing) -> Bool {
        let previous = BridgePairingStore.activePairing()
        do {
            if var next = profiles {
                next[next.selected] = pairing
                try BridgePairingStore.save(next)
                profiles = next
            } else {
                guard !BridgePairingStore.hasUsedSharedProfiles else { throw BridgePairingStore.StoreError.unavailable }
                pairing.saveLegacy()
            }
        } catch { status.text = error.localizedDescription; return false }
        if previous != pairing {
            voice.stop(message: "连接配置已更新，正在准备新的语音会话。")
            autoStartPolicy.configurationChanged()
            connectionRequest = UUID()
        }
        showPairing(pairing)
        return true
    }

    private func loadBridgeProfiles() {
        do {
            if let saved = try BridgePairingStore.load() {
                profiles = saved
            } else {
                let initial = BridgeProfiles(legacy: BridgePairing.legacy())
                try BridgePairingStore.save(initial)
                profiles = initial
            }
            bridgeTarget.selectedSegmentIndex = BridgeTarget.allCases.firstIndex(of: profiles?.selected ?? .aws) ?? 0
            showPairing(profiles?.active)
            if profiles?.active?.isExpired() == true {
                status.text = "试验服务器配置已到期，请更新配对配置。"
            } else if let pairing = profiles?.active, let target = profiles?.selected {
                status.text = "\(target.title) · 已配对 \(pairing.address)"
            }
        } catch {
            bridgeTarget.isEnabled = false
            showPairing(BridgePairingStore.activePairing())
            bridgeSwitchStatus.text = "一键切换不可用。\(error.localizedDescription)"
            bridgeSwitchStatus.isHidden = false
        }
    }

    @objc private func bridgeTargetChanged() {
        let index = bridgeTarget.selectedSegmentIndex
        guard var next = profiles, BridgeTarget.allCases.indices.contains(index) else { return }
        view.endEditing(true)
        let previous = next.selected
        next.selected = BridgeTarget.allCases[index]
        guard BridgePairingStore.keyboardReady else {
            bridgeTarget.selectedSegmentIndex = BridgeTarget.allCases.firstIndex(of: previous) ?? 0
            status.text = "请先开启键盘的完全访问并打开一次 CapsWriter 键盘。若仍无法切换，请检查签名。"
            return
        }
        do {
            try BridgePairingStore.save(next)
        } catch {
            bridgeTarget.selectedSegmentIndex = BridgeTarget.allCases.firstIndex(of: previous) ?? 0
            status.text = error.localizedDescription
            return
        }
        profiles = next
        connectionRequest = UUID()
        voice.stop(message: "已选择\(next.selected.title)。")
        autoStartPolicy.configurationChanged()
        showPairing(next.active)
        if let pairing = next.active { checkConnection(pairing, correct: false) }
        else { status.text = "\(next.selected.title)尚未配对。请输入地址和配对码，或扫描配对二维码。" }
    }

    private func showPairing(_ pairing: BridgePairing?) {
        address.text = pairing?.address
        token.text = pairing?.token
    }

    private func openSideStoreUpdate() {
        view.endEditing(true)
        guard let url = SideStoreUpdateLink.make() else {
            updateStatus.text = "无法生成更新链接。"
            return
        }
        UIApplication.shared.open(url) { [weak self] opened in
            self?.updateStatus.text = opened
                ? "已打开 SideStore，请在那里确认安装。"
                : "无法打开 SideStore，请先完成 SideStore 的首次设置。"
        }
    }
}
