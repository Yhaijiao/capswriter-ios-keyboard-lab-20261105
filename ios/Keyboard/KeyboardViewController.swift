import UIKit

private final class KeyboardPagingScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

final class KeyboardViewController: UIInputViewController, UIScrollViewDelegate {
    private enum Mode: Int { case voice, english, pinyin }
    private var mode: Mode = .voice
    private var shifted = false
    private var symbols = false
    private var composition = ""
    private lazy var pinyin = PinyinEngine()
    private let content = UIStackView()
    private let pager = KeyboardPagingScrollView()
    private let pageStrip = UIStackView()
    private weak var modeSelector: UISegmentedControl?
    private weak var normalHeader: UIStackView?
    private weak var pinyinHeader: UIStackView?
    private var pageWidth: CGFloat = 0
    private var centeringPages = false
    private var changingPage = false
    private var heightConstraint: NSLayoutConstraint?
    private weak var globe: UIButton?
    private weak var feedback: UILabel?
    private weak var candidateRow: UIStackView?
    private weak var candidateScroll: UIScrollView?
    private weak var compositionLabel: UILabel?
    private var previewedText: String?
    private var bridgeRequestID = UUID()
    private var voiceID: String?
    private var voiceState = "idle"
    private var voiceText = ""
    private var voiceMessage = "Tap to speak"
    private var voiceTimer: Timer?
    private var voiceBusy = false
    private var voicePolling = false
    private var voiceRevision = UUID()
    private weak var voiceHint: UILabel?
    private weak var voiceButton: UIButton?
    private var voiceStarted = Date.distantPast
    private var appeared = false
    private var deleteTimer: Timer?
    private var deleteStarted = Date.distantPast
    private weak var deleteGesture: UILongPressGestureRecognizer?

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appeared = false
        stopDeleting()
        voiceTimer?.invalidate(); voiceTimer = nil
        if voiceID == nil { voiceRevision = UUID(); voiceBusy = false }
        if ["pending", "recording"].contains(voiceState) { cancelVoice() }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true; globe?.isHidden = !needsInputModeSwitchKey
        if voiceID != nil && ["stopping", "processing"].contains(voiceState) { scheduleVoicePoll() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Lab.background
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 324)
        heightConstraint?.priority = .defaultHigh; heightConstraint?.isActive = true
        content.axis = .vertical; content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
        render()
    }
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if appeared { globe?.isHidden = !needsInputModeSwitchKey }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = pager.bounds.width
        if width > 0 && abs(width - pageWidth) > 0.5 {
            pageWidth = width
            centeringPages = true; pager.setContentOffset(CGPoint(x: width, y: 0), animated: false); centeringPages = false
        }
    }
    private func changeMode(_ next: Mode) {
        guard next != mode, !changingPage, !pager.isDragging, !pager.isDecelerating else {
            modeSelector?.selectedSegmentIndex = mode.rawValue; return
        }
        animatePage((next.rawValue - mode.rawValue + 3) % 3 == 1 ? 2 : 0)
    }
    private func animatePage(_ index: Int) {
        guard pageWidth > 0 else { return }
        let destination = CGFloat(index) * pageWidth
        if abs(pager.contentOffset.x - destination) < 0.5 {
            finishPage(); return
        }
        changingPage = true
        if UIAccessibility.isReduceMotionEnabled {
            pager.setContentOffset(CGPoint(x: destination, y: 0), animated: false)
            finishPage()
        } else { pager.setContentOffset(CGPoint(x: destination, y: 0), animated: true) }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishPage() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishPage() }
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { finishPage() }
    private func finishPage() {
        guard !centeringPages, pageWidth > 0 else { return }
        changingPage = false
        let index = max(0, min(2, Int((pager.contentOffset.x / pageWidth).rounded())))
        guard index != 1 else { modeSelector?.selectedSegmentIndex = mode.rawValue; return }
        let next = Mode(rawValue: (mode.rawValue + (index == 2 ? 1 : 2)) % 3) ?? .voice
        if mode == .pinyin && next != .pinyin { commitComposition() }
        if mode == .voice && next != .voice && ["pending", "recording"].contains(voiceState) { cancelVoice() }
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
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true; return button
    }
    private func render() {
        stopDeleting()
        if content.arrangedSubviews.isEmpty { buildChrome() }
        centeringPages = true
        for item in pageStrip.arrangedSubviews { pageStrip.removeArrangedSubview(item); item.removeFromSuperview() }
        for (index, delta) in [2, 0, 1].enumerated() {
            let pageMode = Mode(rawValue: (mode.rawValue + delta) % 3) ?? .voice
            let page = UIStackView(); page.axis = .vertical; page.spacing = 8
            page.isUserInteractionEnabled = index == 1; page.accessibilityElementsHidden = index != 1
            page.addArrangedSubview(UIView())
            if pageMode == .voice { renderVoice(content: page) } else { renderLetters(mode: pageMode, content: page) }
            pageStrip.addArrangedSubview(page)
            page.widthAnchor.constraint(equalTo: pager.frameLayoutGuide.widthAnchor).isActive = true
        }
        modeSelector?.selectedSegmentIndex = mode.rawValue
        view.layoutIfNeeded(); pageWidth = pager.bounds.width
        pager.setContentOffset(CGPoint(x: pageWidth, y: 0), animated: false)
        centeringPages = false; updateCandidates(); updateVoice()
    }
    private func buildChrome() {
        let brand = Lab.label("◖ CapsWriter", size: 19); brand.font = .boldSystemFont(ofSize: 19)
        let selector = UISegmentedControl(items: ["", "EN", "拼"])
        selector.setImage(UIImage(systemName: "waveform"), forSegmentAt: 0)
        selector.selectedSegmentIndex = mode.rawValue
        modeSelector = selector
        selector.accessibilityIdentifier = "keyboard-mode-selector"
        selector.addAction(UIAction { [weak self, weak selector] _ in
            self?.changeMode(Mode(rawValue: selector?.selectedSegmentIndex ?? 0) ?? .voice)
        }, for: .valueChanged)
        selector.widthAnchor.constraint(equalToConstant: 142).isActive = true
        let header = row([brand, UIView(), selector], equal: false); header.alignment = .center
        let headerHeight = header.heightAnchor.constraint(equalToConstant: 32)
        headerHeight.priority = .defaultHigh; headerHeight.isActive = true
        normalHeader = header
        content.addArrangedSubview(header)
        let composition = Lab.label("", size: 13, color: Lab.muted)
        composition.accessibilityIdentifier = "pinyin-composition"
        composition.lineBreakMode = .byTruncatingMiddle
        composition.widthAnchor.constraint(lessThanOrEqualToConstant: 70).isActive = true
        compositionLabel = composition
        let candidatesScroll = UIScrollView(); candidatesScroll.showsHorizontalScrollIndicator = false
        candidatesScroll.accessibilityIdentifier = "pinyin-candidates"; candidateScroll = candidatesScroll
        let candidates = UIStackView(); candidates.axis = .horizontal; candidates.spacing = 6
        candidates.translatesAutoresizingMaskIntoConstraints = false; candidatesScroll.addSubview(candidates)
        NSLayoutConstraint.activate([
            candidates.topAnchor.constraint(equalTo: candidatesScroll.contentLayoutGuide.topAnchor),
            candidates.bottomAnchor.constraint(equalTo: candidatesScroll.contentLayoutGuide.bottomAnchor),
            candidates.leadingAnchor.constraint(equalTo: candidatesScroll.contentLayoutGuide.leadingAnchor),
            candidates.trailingAnchor.constraint(equalTo: candidatesScroll.contentLayoutGuide.trailingAnchor),
            candidates.heightAnchor.constraint(equalTo: candidatesScroll.frameLayoutGuide.heightAnchor)
        ])
        candidateRow = candidates
        let candidateHeader = row([composition, candidatesScroll], equal: false)
        let candidateHeight = candidateHeader.heightAnchor.constraint(equalToConstant: 32)
        candidateHeight.priority = .defaultHigh; candidateHeight.isActive = true
        candidateHeader.isHidden = true; pinyinHeader = candidateHeader
        content.addArrangedSubview(candidateHeader)
        pager.delegate = self; pager.isPagingEnabled = true; pager.bounces = false
        pager.showsHorizontalScrollIndicator = false; pager.isDirectionalLockEnabled = true
        pager.delaysContentTouches = false; pager.canCancelContentTouches = true
        pager.contentInsetAdjustmentBehavior = .never; pager.clipsToBounds = true
        pager.accessibilityIdentifier = "keyboard-pages"
        pageStrip.axis = .horizontal; pageStrip.spacing = 0
        pageStrip.translatesAutoresizingMaskIntoConstraints = false; pager.addSubview(pageStrip)
        NSLayoutConstraint.activate([
            pageStrip.topAnchor.constraint(equalTo: pager.contentLayoutGuide.topAnchor),
            pageStrip.bottomAnchor.constraint(equalTo: pager.contentLayoutGuide.bottomAnchor),
            pageStrip.leadingAnchor.constraint(equalTo: pager.contentLayoutGuide.leadingAnchor),
            pageStrip.trailingAnchor.constraint(equalTo: pager.contentLayoutGuide.trailingAnchor),
            pageStrip.heightAnchor.constraint(equalTo: pager.frameLayoutGuide.heightAnchor)
        ])
        content.addArrangedSubview(pager)
        let globe = key("", symbol: "globe") {}
        globe.accessibilityLabel = "切换键盘，按住选择输入法"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.widthAnchor.constraint(equalToConstant: 45).isActive = true; self.globe = globe
        let note = Lab.label("", size: 10, color: Lab.muted)
        note.textAlignment = .center; self.feedback = note
        let bridge = key("", symbol: "network") { [weak self] in self?.showBridge() }
        bridge.accessibilityLabel = "电脑热词连接设置"
        bridge.widthAnchor.constraint(equalToConstant: 45).isActive = true
        content.addArrangedSubview(row([globe, note, bridge], equal: false))
    }
    private func renderVoice(content: UIStackView) {
        let hint = Lab.label(voiceMessage, size: 14, color: Lab.muted)
        hint.numberOfLines = 2
        hint.lineBreakMode = .byTruncatingTail
        hint.textAlignment = .center; content.addArrangedSubview(hint)
        voiceHint = hint
        let mic = Lab.button("", symbol: "mic.fill") { [weak self] in self?.tapVoice() }
        mic.configuration?.baseBackgroundColor = UIColor(white: 0.94, alpha: 1)
        mic.configuration?.baseForegroundColor = .black
        mic.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 35)
        mic.accessibilityIdentifier = "keyboard-voice-button"
        mic.widthAnchor.constraint(equalToConstant: 152).isActive = true
        mic.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        mic.heightAnchor.constraint(equalToConstant: 56).isActive = true
        voiceButton = mic; updateVoice()
        let micRow = row([UIView(), mic, UIView()], equal: false); micRow.distribution = .equalCentering
        content.addArrangedSubview(micRow)
        content.addArrangedSubview(row([
            key("space") { [weak self] in self?.space() },
            key("@") { [weak self] in self?.input("@") }, deleteKey()
        ]))
        let enter = returnKey(); enter.widthAnchor.constraint(equalToConstant: 152).isActive = true
        let enterRow = row([UIView(), enter, UIView()], equal: false); enterRow.distribution = .equalCentering
        content.addArrangedSubview(enterRow)
    }

    private func voiceCall(_ path: String, value: [String: Any]? = nil, jobID: String? = nil,
                           completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        BridgeClient.call(address: UserDefaults.standard.string(forKey: "bridge.address") ?? "",
                          token: UserDefaults.standard.string(forKey: "bridge.token") ?? "",
                          path: path, value: value, jobID: jobID, completion: completion)
    }
    private func tapVoice() {
        guard hasFullAccess else { voiceMessage = "先在键盘设置允许完全访问，再在主 App 开启语音会话。"; updateVoice(); return }
        guard !voiceBusy else { return }
        if voiceState == "done" {
            guard !voiceText.isEmpty else { resetVoice("没有识别到文字，请重试。"); return }
            textDocumentProxy.insertText(voiceText)
            if let id = voiceID { voiceCall("/v1/voice/consume", value: ["id": id]) { _ in } }
            resetVoice("已插入 · 点击麦克风录下一段"); return
        }
        if voiceState == "recording", let id = voiceID {
            voiceRevision = UUID(); let revision = voiceRevision; voicePolling = false
            voiceBusy = true; voiceMessage = "正在结束录音…"; updateVoice()
            voiceCall("/v1/voice/stop", value: ["id": id]) { [weak self] result in
                guard let self = self, self.voiceID == id, self.voiceRevision == revision else { return }
                self.voiceBusy = false; self.handleVoice(result)
            }
            return
        }
        guard !["pending", "stopping", "processing"].contains(voiceState) else { return }
        voiceRevision = UUID(); let revision = voiceRevision
        voiceBusy = true; voiceMessage = "正在连接语音会话…"; updateVoice()
        voiceCall("/v1/voice/start", value: [:]) { [weak self] result in
            guard let self = self else { return }
            guard self.voiceRevision == revision else {
                if case .success(let reply) = result, let id = reply.id {
                    self.voiceCall("/v1/voice/cancel", value: ["id": id]) { _ in }
                }
                return
            }
            self.voiceBusy = false
            if case .success(let reply) = result {
                self.voiceID = reply.id; self.voiceStarted = Date(); self.scheduleVoicePoll()
            }
            self.handleVoice(result)
        }
    }
    private func scheduleVoicePoll() {
        voiceTimer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in self?.pollVoice() }
        voiceTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func pollVoice() {
        guard !voiceBusy, !voicePolling, let id = voiceID else { return }
        if Date().timeIntervalSince(voiceStarted) > Double(Lab.maxRecordingSeconds + 200) { cancelVoice(); resetVoice("语音任务超时，请重试。"); return }
        voicePolling = true; let revision = voiceRevision
        voiceCall("/v1/voice/result", jobID: id) { [weak self] result in
            guard let self = self, self.voiceID == id, self.voiceRevision == revision else { return }
            self.voicePolling = false; self.handleVoice(result)
        }
    }
    private func handleVoice(_ result: Result<BridgeReply, Error>) {
        switch result {
        case .failure(let error):
            cancelVoice(); resetVoice(error.localizedDescription)
        case .success(let reply):
            voiceState = reply.state ?? "idle"
            switch voiceState {
            case "pending": voiceMessage = "正在启动手机录音，请稍候…"
            case "recording": voiceMessage = "正在录音 · 说完点击停止（最长 5 分钟）"
            case "stopping", "processing": voiceMessage = "正在电脑识别并应用当前热词…"
            case "done":
                voiceTimer?.invalidate(); voiceTimer = nil
                voiceText = reply.text ?? ""
                voiceMessage = voiceText.isEmpty ? "没有识别到文字，点击重试。" : voiceText
                if voiceText.isEmpty { resetVoice(voiceMessage) }
            case "error", "cancelled", "consumed": resetVoice(reply.error ?? "请重新开始录音。")
            default: break
            }
            updateVoice()
        }
    }
    private func updateVoice() {
        voiceHint?.text = voiceMessage
        let recording = voiceState == "recording"
        voiceButton?.configuration?.title = recording ? "停止" : (voiceState == "done" ? "插入文字" : "")
        voiceButton?.configuration?.image = UIImage(systemName: recording ? "stop.fill" : (voiceState == "done" ? "text.badge.plus" : "mic.fill"))
        voiceButton?.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: recording || voiceState == "done" ? 22 : 35)
        voiceButton?.accessibilityLabel = recording ? "停止录音" : (voiceState == "done" ? "插入识别文字" : "开始真实语音输入")
        // Polling requests don't disable the stop button, so a tap is never silently lost.
        voiceButton?.isEnabled = !voiceBusy && !["pending", "stopping", "processing"].contains(voiceState)
    }
    private func resetVoice(_ message: String) {
        voiceTimer?.invalidate(); voiceTimer = nil
        voiceID = nil; voiceText = ""; voiceState = "idle"; voiceBusy = false
        voiceRevision = UUID(); voicePolling = false
        voiceMessage = message; updateVoice()
    }
    private func cancelVoice() {
        if let id = voiceID { voiceCall("/v1/voice/cancel", value: ["id": id]) { _ in } }
        resetVoice("录音已取消 · 点击重新开始")
    }
    private func renderLetters(mode: Mode, content: UIStackView) {
        let layouts = symbols ? ["1234567890", "-/:;()$&@\"", ".,?!'%+="] : ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        var letterWidth: NSLayoutDimension?
        for (index, line) in layouts.enumerated() {
            var buttons: [UIView] = []
            var shiftButton: UIButton?
            if index == 2 && !symbols {
                let shift = key("", symbol: shifted ? "shift.fill" : "shift") { [weak self] in
                    guard let self = self else { return }
                    if self.mode == .pinyin { self.changeMode(.english) }
                    else { self.shifted.toggle(); self.render() }
                }
                shift.accessibilityLabel = mode == .pinyin ? "切换到英文" : "大小写切换"
                shiftButton = shift
                buttons.append(shift)
            }
            for letter in line {
                let title = !symbols && mode == .english && shifted ? String(letter).uppercased() : String(letter)
                let button = key(title) { [weak self] in self?.input(title) }
                if index == 0 && letterWidth == nil { letterWidth = button.widthAnchor }
                if !symbols && index > 0, let width = letterWidth { button.widthAnchor.constraint(equalTo: width).isActive = true }
                button.accessibilityIdentifier = "key-" + title; buttons.append(button)
            }
            if index == 2 {
                let delete = deleteKey()
                if let shift = shiftButton { delete.widthAnchor.constraint(equalTo: shift.widthAnchor).isActive = true }
                buttons.append(delete)
            }
            if !symbols && index == 1 {
                let left = UIView(), right = UIView()
                left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
                content.addArrangedSubview(row([left] + buttons + [right], equal: false))
            } else { content.addArrangedSubview(row(buttons, equal: symbols || index == 0)) }
        }
        let number = key(symbols ? "ABC" : "123") { [weak self] in
            guard let self = self else { return }; self.commitComposition(); self.symbols.toggle(); self.render()
        }
        number.widthAnchor.constraint(equalToConstant: 74).isActive = true
        let space = key(mode == .pinyin ? "拼" : "EN") { [weak self] in self?.space() }
        space.accessibilityLabel = "空格 / 选字"
        space.contentHorizontalAlignment = .trailing
        let enter = returnKey(); enter.widthAnchor.constraint(equalToConstant: 74).isActive = true
        enter.configuration?.title = ""; enter.configuration?.image = UIImage(systemName: "return")
        enter.configuration?.baseBackgroundColor = UIColor(white: 0.94, alpha: 1)
        enter.configuration?.baseForegroundColor = .black
        content.addArrangedSubview(row([number, space, enter], equal: false))
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
    private func deleteKey() -> UIButton {
        let button = key("", symbol: "delete.left") { [weak self] in self?.deleteCharacter() }
        button.accessibilityIdentifier = "keyboard-delete"
        button.accessibilityLabel = "删除"
        button.accessibilityHint = "短按删除一个字符，长按加速连续删除"
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(deleteHeld(_:)))
        gesture.minimumPressDuration = 0.4
        button.addGestureRecognizer(gesture)
        return button
    }
    @objc private func deleteHeld(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            stopDeleting(); deleteGesture = gesture; deleteStarted = Date()
            deleteCharacter(); scheduleDeletion()
        case .changed:
            if let button = gesture.view, !button.bounds.insetBy(dx: -10, dy: -10).contains(gesture.location(in: button)) { stopDeleting() }
        case .ended, .cancelled, .failed: stopDeleting()
        default: break
        }
    }
    private func scheduleDeletion() {
        let elapsed = Date().timeIntervalSince(deleteStarted)
        let interval = elapsed > 2 ? 0.04 : (elapsed > 0.9 ? 0.075 : 0.12)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, let gesture = self.deleteGesture,
                  gesture.view?.window != nil, [.began, .changed].contains(gesture.state) else { return }
            self.deleteCharacter(); self.scheduleDeletion()
        }
        deleteTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func stopDeleting() { deleteTimer?.invalidate(); deleteTimer = nil; deleteGesture = nil }
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
        let composing = mode == .pinyin && !composition.isEmpty
        normalHeader?.isHidden = composing; pinyinHeader?.isHidden = !composing
        guard mode == .pinyin else { return }
        compositionLabel?.text = composition
        guard let row = candidateRow else { return }
        for view in row.arrangedSubviews { row.removeArrangedSubview(view); view.removeFromSuperview() }
        for candidate in pinyin.candidates(for: composition) {
            let button = Lab.button(candidate.text) { [weak self] in self?.choose(candidate) }
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9)
            button.accessibilityIdentifier = "candidate-" + candidate.text; row.addArrangedSubview(button)
        }
        candidateScroll?.setContentOffset(.zero, animated: false)
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
