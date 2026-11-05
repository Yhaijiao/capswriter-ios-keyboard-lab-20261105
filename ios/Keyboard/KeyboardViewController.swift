import UIKit

final class KeyboardViewController: UIInputViewController {
    private let hint = Lab.label("Tap to test · 点击测试输入", size: 17, color: Lab.muted)
    private let feedback = Lab.label("实验版 · 不录音 · 不自动发送消息", size: 11, color: Lab.muted)
    private let content = UIStackView()
    private var english = false
    private var previewedText: String?
    private var heightConstraint: NSLayoutConstraint?
    private weak var globe: UIButton?
    private var micContainer: UIView?
    private var letterContainer: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Lab.background
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 318)
        heightConstraint?.priority = .defaultHigh; heightConstraint?.isActive = true
        content.axis = .vertical; content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18)
        ])
        let brand = Lab.label("◖ CapsWriter", size: 21)
        brand.font = .boldSystemFont(ofSize: 21)
        let mode = UISegmentedControl(items: ["波形", "EN", "中"])
        mode.selectedSegmentIndex = 0
        mode.accessibilityLabel = "测试文字语言，不是拼音输入法"
        mode.addAction(UIAction { [weak self, weak mode] _ in
            self?.english = mode?.selectedSegmentIndex == 1
            self?.hint.text = self?.english == true ? "English · basic keys" : "Tap to test · 点击测试输入"
            self?.micContainer?.isHidden = self?.english == true
            self?.letterContainer?.isHidden = self?.english != true
            self?.heightConstraint?.constant = self?.english == true ? 386 : 318
        }, for: .valueChanged)
        let header = UIStackView(arrangedSubviews: [brand, UIView(), mode])
        header.alignment = .center
        mode.widthAnchor.constraint(equalToConstant: 140).isActive = true
        content.addArrangedSubview(header)
        hint.textAlignment = .center
        content.addArrangedSubview(hint)
        let mic = Lab.button("", symbol: "mic.fill") { [weak self] in self?.insertSample() }
        mic.configuration?.baseBackgroundColor = UIColor(white: 0.94, alpha: 1)
        mic.configuration?.baseForegroundColor = .black
        mic.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 35)
        mic.accessibilityLabel = "插入测试文字。本版本不录音"
        mic.accessibilityIdentifier = "keyboard-test-button"
        let micRow = UIStackView(arrangedSubviews: [UIView(), mic, UIView()])
        micRow.distribution = .equalCentering
        mic.widthAnchor.constraint(equalToConstant: 152).isActive = true
        mic.heightAnchor.constraint(equalToConstant: 65).isActive = true
        content.addArrangedSubview(micRow)
        micContainer = micRow
        let letters = UIStackView(); letters.axis = .vertical; letters.spacing = 6
        for rowText in ["qwertyuiop", "asdfghjkl", "zxcvbnm.,"] {
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 4; row.distribution = .fillEqually
            for letter in rowText {
                let key = Lab.button(String(letter)) { [weak self] in self?.textDocumentProxy.insertText(String(letter)) }
                key.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 1, bottom: 4, trailing: 1)
                key.heightAnchor.constraint(equalToConstant: 32).isActive = true
                row.addArrangedSubview(key)
            }
            letters.addArrangedSubview(row)
        }
        letters.isHidden = true
        content.addArrangedSubview(letters)
        letterContainer = letters
        let bridge = Lab.button("电脑", symbol: "network") { [weak self] in self?.showBridge() }
        bridge.accessibilityLabel = "电脑热词连接设置"
        let enter = Lab.button("return") { [weak self] in self?.textDocumentProxy.insertText("\n") }
        enter.accessibilityIdentifier = "keyboard-return"
        let delete = Lab.button("", symbol: "delete.left") { [weak self] in self?.textDocumentProxy.deleteBackward() }
        delete.accessibilityLabel = "删除一个字符"
        let actions = UIStackView(arrangedSubviews: [bridge, enter, delete])
        actions.spacing = 12; actions.distribution = .fill
        bridge.widthAnchor.constraint(equalToConstant: 96).isActive = true
        delete.widthAnchor.constraint(equalToConstant: 54).isActive = true
        content.addArrangedSubview(actions)
        let globe = Lab.button("", symbol: "globe") {}
        globe.accessibilityLabel = "切换键盘，按住选择输入法"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        self.globe = globe
        let space = Lab.button("space") { [weak self] in self?.textDocumentProxy.insertText(" ") }
        let at = Lab.button("@") { [weak self] in self?.textDocumentProxy.insertText("@") }
        let bottom = UIStackView(arrangedSubviews: [globe, space, at])
        bottom.spacing = 12
        globe.widthAnchor.constraint(equalToConstant: 54).isActive = true
        at.widthAnchor.constraint(equalToConstant: 54).isActive = true
        content.addArrangedSubview(bottom)
        feedback.textAlignment = .center
        content.addArrangedSubview(feedback)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globe?.isHidden = !needsInputModeSwitchKey
    }
    private func insertSample() {
        let text = english ? Lab.englishSample : Lab.chineseSample
        textDocumentProxy.insertText(text)
        feedback.text = "已插入测试文字 · Return 换行 · 不发送消息"
    }

    private func showBridge() {
        guard hasFullAccess else {
            feedback.text = "电脑连接需在系统键盘设置中开启“允许完全访问”"
            return
        }
        // A keyboard cannot present a host-app alert. Use an in-keyboard settings panel.
        if let panel = view.viewWithTag(700) { panel.removeFromSuperview(); return }
        let panel = UIStackView(); panel.tag = 700
        panel.axis = .vertical; panel.spacing = 10
        panel.backgroundColor = Lab.background
        panel.isLayoutMarginsRelativeArrangement = true
        panel.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor), panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor), panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let result = Lab.label("先在主 App 填写地址与配对码，点击复制配对配置，再回这里粘贴。", size: 12, color: Lab.muted)
        let paste = Lab.button("粘贴配对配置", symbol: "doc.on.clipboard") { [weak result] in
            guard let raw = UIPasteboard.general.string, raw.hasPrefix("cwlab:v1:"),
                  let data = String(raw.dropFirst(9)).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let address = value["address"], let token = value["token"], !token.isEmpty else {
                result?.text = "没有找到有效配对配置，请先在主 App 复制。"; return
            }
            UserDefaults.standard.set(address, forKey: "bridge.address")
            UserDefaults.standard.set(token, forKey: "bridge.token")
            result?.text = "配对配置已保存，只在点击测试时联网。"
        }
        let run = Lab.button("检查版本 / 纠正测试短句") { [weak self, weak result] in
            guard let self = self else { return }
            self.previewedText = nil
            let a = UserDefaults.standard.string(forKey: "bridge.address") ?? ""
            let t = UserDefaults.standard.string(forKey: "bridge.token") ?? ""
            result?.text = "连接中…"
            // Sends a fixed demo phrase, never reads the user's surrounding document.
            BridgeClient.request(address: a, token: t, text: "测试热词：卡普斯赖特") { [weak self, weak result] reply in
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
            self.textDocumentProxy.insertText(text)
            panel?.removeFromSuperview()
        }
        let close = Lab.button("返回键盘") { [weak panel] in panel?.removeFromSuperview() }
        panel.addArrangedSubview(paste)
        panel.addArrangedSubview(run); panel.addArrangedSubview(result)
        let bottom = UIStackView(arrangedSubviews: [insert, close]); bottom.spacing = 8
        panel.addArrangedSubview(bottom)
        panel.addArrangedSubview(UIView())
    }
}
