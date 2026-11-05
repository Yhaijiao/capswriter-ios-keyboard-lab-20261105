import UIKit

final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
    private enum Mode: Int { case voice, english, pinyin }
    private var mode: Mode = .voice
    private var shifted = false
    private var symbols = false
    private var composition = ""
    private lazy var pinyin = PinyinEngine()
    private let content = UIStackView()
    private var heightConstraint: NSLayoutConstraint?
    private weak var globe: UIButton?
    private weak var feedback: UILabel?
    private weak var candidateRow: UIStackView?
    private weak var compositionLabel: UILabel?
    private var previewedText: String?
    private var bridgeRequestID = UUID()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Lab.background
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 318)
        heightConstraint?.priority = .defaultHigh; heightConstraint?.isActive = true
        content.axis = .vertical; content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction; swipe.delegate = self; view.addGestureRecognizer(swipe)
        }
        render()
    }
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews(); globe?.isHidden = !needsInputModeSwitchKey
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let item = target, item !== view {
            if item.tag == 700 || item.tag == 901 { return false }
            target = item.superview
        }
        return true
    }
    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        let delta = gesture.direction == .left ? 1 : 2
        changeMode(Mode(rawValue: (mode.rawValue + delta) % 3) ?? .voice)
    }
    private func changeMode(_ next: Mode) {
        if mode == .pinyin && next != .pinyin { commitComposition() }
        mode = next; shifted = false; symbols = false; render()
    }
    private func row(_ views: [UIView], equal: Bool = true) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views); row.spacing = 5
        if equal { row.distribution = .fillEqually }; return row
    }
    private func key(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> UIButton {
        let button = Lab.button(title, symbol: symbol, action: action)
        button.configuration?.cornerStyle = .medium
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
        button.heightAnchor.constraint(equalToConstant: 39).isActive = true; return button
    }
    private func render() {
        for item in content.arrangedSubviews { content.removeArrangedSubview(item); item.removeFromSuperview() }
        heightConstraint?.constant = mode == .voice ? 318 : (mode == .pinyin ? 384 : 350)
        let brand = Lab.label("◖ CapsWriter", size: 19); brand.font = .boldSystemFont(ofSize: 19)
        let selector = UISegmentedControl(items: ["波形", "EN", "拼"])
        selector.selectedSegmentIndex = mode.rawValue
        selector.accessibilityIdentifier = "keyboard-mode-selector"
        selector.addAction(UIAction { [weak self, weak selector] _ in
            self?.changeMode(Mode(rawValue: selector?.selectedSegmentIndex ?? 0) ?? .voice)
        }, for: .valueChanged)
        selector.widthAnchor.constraint(equalToConstant: 142).isActive = true
        let header = row([brand, UIView(), selector], equal: false); header.alignment = .center
        content.addArrangedSubview(header)
        if mode == .voice { renderVoice() } else { renderLetters() }
        let globe = key("", symbol: "globe") {}
        globe.accessibilityLabel = "切换键盘，按住选择输入法"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.widthAnchor.constraint(equalToConstant: 45).isActive = true; self.globe = globe
        let note = Lab.label(mode == .voice ? "实验版 · 不录音 · 左滑切换 EN / 拼" : "左滑切换：语音 → EN → 拼 → 语音", size: 10, color: Lab.muted)
        note.textAlignment = .center; self.feedback = note
        let bridge = key("", symbol: "network") { [weak self] in self?.showBridge() }
        bridge.accessibilityLabel = "电脑热词连接设置"
        bridge.widthAnchor.constraint(equalToConstant: 45).isActive = true
        content.addArrangedSubview(row([globe, note, bridge], equal: false))
    }
    private func renderVoice() {
        let spacer = UIView(); spacer.heightAnchor.constraint(equalToConstant: 12).isActive = true
        content.addArrangedSubview(spacer)
        let hint = Lab.label("Tap to test · 点击测试输入", size: 17, color: Lab.muted)
        hint.textAlignment = .center; content.addArrangedSubview(hint)
        let mic = Lab.button("", symbol: "mic.fill") { [weak self] in
            self?.textDocumentProxy.insertText(Lab.chineseSample)
            self?.feedback?.text = "已插入测试文字 · 本版本不录音"
        }
        mic.configuration?.baseBackgroundColor = UIColor(white: 0.94, alpha: 1)
        mic.configuration?.baseForegroundColor = .black
        mic.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 35)
        mic.accessibilityLabel = "插入测试文字。本版本不录音"
        mic.accessibilityIdentifier = "keyboard-test-button"
        mic.widthAnchor.constraint(equalToConstant: 152).isActive = true
        mic.heightAnchor.constraint(equalToConstant: 65).isActive = true
        let micRow = row([UIView(), mic, UIView()], equal: false); micRow.distribution = .equalCentering
        content.addArrangedSubview(micRow)
        let delete = key("", symbol: "delete.left") { [weak self] in self?.deleteCharacter() }
        delete.accessibilityLabel = "删除一个字符"
        content.addArrangedSubview(row([key("space") { [weak self] in self?.space() }, returnKey(), delete]))
        content.addArrangedSubview(row([
            key("，") { [weak self] in self?.input("，") },
            key("。") { [weak self] in self?.input("。") },
            key("@") { [weak self] in self?.input("@") }
        ]))
    }
    private func renderLetters() {
        if mode == .pinyin {
            let label = Lab.label("输入拼音，点击候选字词", size: 13, color: Lab.muted)
            label.accessibilityIdentifier = "pinyin-composition"
            label.heightAnchor.constraint(equalToConstant: 18).isActive = true
            self.compositionLabel = label; content.addArrangedSubview(label)
            let scroll = UIScrollView(); scroll.tag = 901; scroll.showsHorizontalScrollIndicator = false
            scroll.heightAnchor.constraint(equalToConstant: 32).isActive = true
            let candidates = UIStackView(); candidates.axis = .horizontal; candidates.spacing = 8
            candidates.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(candidates)
            NSLayoutConstraint.activate([
                candidates.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                candidates.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                candidates.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                candidates.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                candidates.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
            ])
            self.candidateRow = candidates; content.addArrangedSubview(scroll)
        }
        let layouts = symbols ? ["1234567890", "-/:;()$&@\"", ".,?!'%+="] : ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        for (index, line) in layouts.enumerated() {
            var buttons: [UIView] = []
            if index == 2 && !symbols {
                let shift = key("", symbol: shifted ? "shift.fill" : "shift") { [weak self] in
                    guard let self = self else { return }
                    if self.mode == .pinyin { self.changeMode(.english) }
                    else { self.shifted.toggle(); self.render() }
                }
                shift.accessibilityLabel = mode == .pinyin ? "切换到英文" : "大小写切换"
                buttons.append(shift)
            }
            for letter in line {
                let title = !symbols && mode == .english && shifted ? String(letter).uppercased() : String(letter)
                let button = key(title) { [weak self] in self?.input(title) }
                button.accessibilityIdentifier = "key-" + title; buttons.append(button)
            }
            if index == 2 {
                let delete = key("", symbol: "delete.left") { [weak self] in self?.deleteCharacter() }
                delete.accessibilityLabel = "删除一个字符"; buttons.append(delete)
            }
            content.addArrangedSubview(row(buttons))
        }
        let number = key(symbols ? "ABC" : "123") { [weak self] in
            guard let self = self else { return }; self.commitComposition(); self.symbols.toggle(); self.render()
        }
        number.widthAnchor.constraint(equalToConstant: 74).isActive = true
        let space = key(mode == .pinyin ? "空格 / 选字" : "space") { [weak self] in self?.space() }
        let enter = returnKey(); enter.widthAnchor.constraint(equalToConstant: 74).isActive = true
        content.addArrangedSubview(row([number, space, enter], equal: false)); updateCandidates()
    }
    private func returnKey() -> UIButton {
        let button = key("return") { [weak self] in
            guard let self = self else { return }
            if self.composition.isEmpty { self.textDocumentProxy.insertText("\n") } else { self.commitComposition() }
        }
        button.accessibilityIdentifier = "keyboard-return"; return button
    }
    private func input(_ text: String) {
        if mode == .pinyin && !symbols && text.count == 1 && text.allSatisfy({ $0 >= "a" && $0 <= "z" }) {
            guard composition.count < 64 else { return }; composition += text; updateCandidates()
        } else { commitComposition(); textDocumentProxy.insertText(text) }
    }
    private func space() {
        if composition.isEmpty { textDocumentProxy.insertText(" ") } else { commitComposition() }
    }
    private func deleteCharacter() {
        if composition.isEmpty { textDocumentProxy.deleteBackward() }
        else { composition.removeLast(); updateCandidates() }
    }
    private func choose(_ candidate: PinyinCandidate) {
        textDocumentProxy.insertText(candidate.text)
        composition = String(composition.dropFirst(candidate.consumed)); updateCandidates()
    }
    private func commitComposition() {
        guard !composition.isEmpty else { return }
        while !composition.isEmpty {
            if let first = pinyin.candidates(for: composition).first { choose(first) }
            else { textDocumentProxy.insertText(composition); composition = "" }
        }
        updateCandidates()
    }
    private func updateCandidates() {
        guard mode == .pinyin else { return }
        compositionLabel?.text = composition.isEmpty ? "输入拼音，点击候选字词 · v 代替 ü" : composition
        guard let row = candidateRow else { return }
        for view in row.arrangedSubviews { row.removeArrangedSubview(view); view.removeFromSuperview() }
        for candidate in pinyin.candidates(for: composition) {
            let button = Lab.button(candidate.text) { [weak self] in self?.choose(candidate) }
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9)
            button.accessibilityIdentifier = "candidate-" + candidate.text; row.addArrangedSubview(button)
        }
    }
    private func showBridge() {
        guard hasFullAccess else { feedback?.text = "电脑连接需在键盘设置开启“允许完全访问”"; return }
        if let panel = view.viewWithTag(700) { panel.removeFromSuperview(); return }
        previewedText = nil; bridgeRequestID = UUID()
        let panel = UIStackView(); panel.tag = 700; panel.axis = .vertical; panel.spacing = 10
        panel.backgroundColor = Lab.background; panel.isLayoutMarginsRelativeArrangement = true
        panel.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        panel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor), panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor), panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let result = Lab.label("在主 App 复制配对配置，再回这里粘贴。", size: 12, color: Lab.muted)
        let paste = Lab.button("粘贴配对配置", symbol: "doc.on.clipboard") { [weak result] in
            guard let raw = UIPasteboard.general.string, raw.hasPrefix("cwlab:v1:"),
                  let data = String(raw.dropFirst(9)).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let address = value["address"], let token = value["token"], !token.isEmpty else {
                result?.text = "请先在主 App 复制配对配置。"; return
            }
            UserDefaults.standard.set(address, forKey: "bridge.address")
            UserDefaults.standard.set(token, forKey: "bridge.token")
            result?.text = "配对配置已保存，只在点击测试时联网。"
        }
        let run = Lab.button("检查版本 / 纠正测试短句") { [weak self, weak result] in
            guard let self = self else { return }
            self.previewedText = nil; let requestID = UUID(); self.bridgeRequestID = requestID; result?.text = "连接中…"
            BridgeClient.request(address: UserDefaults.standard.string(forKey: "bridge.address") ?? "",
                                 token: UserDefaults.standard.string(forKey: "bridge.token") ?? "",
                                 text: "测试热词：卡普斯赖特") { [weak self, weak result] reply in
                guard self?.bridgeRequestID == requestID else { return }
                switch reply {
                case .success(let value):
                    self?.previewedText = value.text
                    result?.text = "\(value.mode ?? "") · \(value.version ?? "")\n\(value.text ?? "")"
                case .failure(let error): result?.text = error.localizedDescription
                }
            }
        }
        let insert = Lab.button("插入已预览的结果") { [weak self, weak panel] in
            guard let self = self, let text = self.previewedText else { return }
            self.textDocumentProxy.insertText(text); panel?.removeFromSuperview()
        }
        let close = Lab.button("返回键盘") { [weak self, weak panel] in
            self?.bridgeRequestID = UUID(); self?.previewedText = nil; panel?.removeFromSuperview()
        }
        panel.addArrangedSubview(paste); panel.addArrangedSubview(run); panel.addArrangedSubview(result)
        panel.addArrangedSubview(row([insert, close])); panel.addArrangedSubview(UIView())
    }
}
