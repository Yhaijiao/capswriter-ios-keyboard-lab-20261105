import AVFoundation
import ActivityKit
import UIKit

// The containing app owns the microphone. No App Groups or private URL APIs.
// A foreground app action or enabled auto-start preference arms a timed session.
// Idle audio is discarded; only a keyboard-requested segment is held in memory.
final class VoiceSession {
    var onStatus: ((String) -> Void)?
    var onStopped: (() -> Void)?
    private(set) var active = false
    private(set) var starting = false
    private let audio = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var tapInstalled = false
    private var segmentID: String?
    private var samples = Data()
    private var timer: Timer?
    private var agentID = UUID().uuidString
    private var pairing: BridgePairing?
    private var expires = Date.distantPast
    private var lastSuccess = Date.distantPast
    private var polling = false
    private var uploading = false
    private var completingID: String?
    private var generation = UUID()
    private var lastFrames = Date.distantPast
    private var sessionMinutes = 10
    private var recognitionMode = "cloud"
    private var phoneLocale: Locale?
    private var phoneRecognizer: AnyObject?
    private var preparingID: String?
    private var preparationTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var finishTimeout: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    func start(pairing: BridgePairing, sessionMinutes: Int = 10, intentActivityID: String? = nil) {
        guard !active, !starting else { return }
        starting = true
        let selected = UserDefaults.standard.string(forKey: "voice.recognitionMode") ?? "cloud"
        recognitionMode = ["phone-zh", "phone-en"].contains(selected) ? selected : "cloud"
        let request = UUID(); generation = request
        onStatus?("正在检查识别服务连接…")
        BridgeClient.request(pairing: pairing) { [weak self] response in
            guard let self = self, self.generation == request else { return }
            switch response {
            case .failure(let error):
                self.starting = false; self.onStatus?(error.localizedDescription)
            case .success(let reply):
                if self.recognitionMode != "cloud" && reply.phone_asr_v1 != true {
                    self.starting = false; self.onStatus?("请先升级配对服务，或切回服务端识别。"); return
                }
                guard reply.voice_enabled == true, reply.asr_ready == true else {
                    self.starting = false
                    self.onStatus?("请启动配对的 CapsWriter 识别服务后重试。")
                    return
                }
                guard (reply.max_seconds ?? 60) >= Lab.maxRecordingSeconds else {
                    self.starting = false
                    self.onStatus?("配对服务版本过旧，请更新后再录制长语音。")
                    return
                }
                if AVAudioApplication.shared.recordPermission == .granted {
                    self.prepareAndArm(pairing: pairing, sessionMinutes: sessionMinutes, intentActivityID: intentActivityID, request: request)
                    return
                }
                if AVAudioApplication.shared.recordPermission == .denied {
                    self.starting = false
                    self.onStatus?("请在 App 设置中允许麦克风后重试。")
                    return
                }
                AVAudioApplication.requestRecordPermission { [weak self] allowed in
                    DispatchQueue.main.async {
                        guard let self = self, self.generation == request else { return }
                        guard allowed else {
                            self.starting = false
                            self.onStatus?("请在 App 设置中允许麦克风后重试。"); return
                        }
                        self.prepareAndArm(pairing: pairing, sessionMinutes: sessionMinutes, intentActivityID: intentActivityID, request: request)
                    }
                }
            }
        }
    }

    private func prepareAndArm(pairing: BridgePairing, sessionMinutes: Int, intentActivityID: String?, request: UUID) {
        guard recognitionMode != "cloud" else {
            arm(pairing: pairing, sessionMinutes: sessionMinutes, intentActivityID: intentActivityID); return
        }
        guard #available(iOS 26.0, *) else {
            starting = false; onStatus?("手机识别需要 iOS 26，可随时切回 AWS 云端。"); return
        }
        let identifier = recognitionMode == "phone-en" ? "en-US" : "zh-CN"
        onStatus?("正在准备手机识别；首次使用可能需要下载系统语言模型…")
        preparationTask = Task { @MainActor [weak self] in
            do {
                let locale = try await PhoneSpeechRecognizer.prepareLocale(identifier)
                guard let self = self, !Task.isCancelled, self.generation == request else { return }
                self.phoneLocale = locale
                self.arm(pairing: pairing, sessionMinutes: sessionMinutes, intentActivityID: intentActivityID)
            } catch {
                guard let self = self, self.generation == request else { return }
                self.starting = false; self.onStatus?("手机识别未能准备：\(error.localizedDescription)\n可切回 AWS 云端。")
            }
        }
    }

    private func arm(pairing: BridgePairing, sessionMinutes: Int, intentActivityID: String?) {
        // Connection or permission callbacks can arrive after the user leaves
        // Lab. Complete a fresh microphone start while the app is visible.
        let validIntentActivity = intentActivityID.map { identifier in
            Activity<RecordingActivityAttributes>.activities.contains { $0.id == identifier && $0.activityState == .active }
        } ?? false
        guard UIApplication.shared.applicationState != .background || validIntentActivity else {
            starting = false
            onStatus?("请回到 Lab 完成开启语音会话。")
            return
        }
        self.pairing = pairing
        self.sessionMinutes = [10, 30, 60].contains(sessionMinutes) ? sessionMinutes : 10
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setPreferredSampleRate(16000)
            try session.setActive(true)
            let node = audio.inputNode
            let input = node.outputFormat(forBus: 0)
            guard input.sampleRate > 0, input.channelCount > 0,
                  let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                             channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: input, to: output) else {
                throw BridgeError.message("当前麦克风格式不可用。")
            }
            self.converter = converter
            node.installTap(onBus: 0, bufferSize: 2048, format: input) { [weak self] buffer, _ in
                self?.capture(buffer, output: output, converter: converter)
            }
            tapInstalled = true
            audio.prepare(); try audio.start()
            active = true; starting = false; agentID = UUID().uuidString
            expires = Date().addingTimeInterval(TimeInterval(self.sessionMinutes * 60)); lastSuccess = Date()
            lock.lock(); lastFrames = Date(); lock.unlock()
            let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.poll() }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            onStatus?("语音会话已开启 · 麦克风持续工作，\(self.sessionMinutes) 分钟后自动关闭。\n回到输入框，在键盘点击麦克风开始，再次点击停止。")
            poll()
        } catch {
            stop(message: "麦克风启动失败：\(error.localizedDescription)")
        }
    }

    private func capture(_ buffer: AVAudioPCMBuffer, output: AVAudioFormat, converter: AVAudioConverter) {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate) + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        var used = false; var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if used { status.pointee = .noDataNow; return nil }
            used = true; status.pointee = .haveData; return buffer
        }
        guard error == nil, let pointer = converted.floatChannelData?[0] else { return }
        lock.lock()
        lastFrames = Date()
        guard segmentID != nil else { lock.unlock(); return }
        let bytes = min(Int(converted.frameLength) * 4, 16000 * Lab.maxRecordingSeconds * 4 - samples.count)
        if bytes > 0 { samples.append(UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: bytes)) }
        let phone = phoneRecognizer
        if #available(iOS 26.0, *), let phone = phone as? PhoneSpeechRecognizer, bytes > 0 {
            converted.frameLength = AVAudioFrameCount(bytes / 4)
            phone.append(converted)
        }
        lock.unlock()
    }

    private func poll() {
        guard active else { return }
        if Date() > expires { stop(message: "\(sessionMinutes) 分钟语音会话已结束，麦克风已关闭。"); return }
        lock.lock(); let framesAge = Date().timeIntervalSince(lastFrames); lock.unlock()
        if !audio.isRunning || framesAge > 5 { stop(message: "麦克风已中断，请重新开启语音会话。"); return }
        if Date().timeIntervalSince(lastSuccess) > 8 { stop(message: "识别服务连接已断开，麦克风已关闭。"); return }
        guard !polling else { return }
        polling = true; let current = generation
        BridgeClient.call(pairing: pairing, path: "/v1/voice/agent",
                          value: ["agent_id": agentID], timeout: 4) { [weak self] result in
            guard let self = self, self.generation == current, self.active else { return }
            self.polling = false
            switch result {
            case .failure(let error):
                self.onStatus?("识别服务连接中断，正在重试：\(error.localizedDescription)")
            case .success(let reply):
                self.lastSuccess = Date(); self.handle(reply)
            }
        }
    }

    private func handle(_ reply: BridgeReply) {
        guard !uploading else { return }
        if reply.state == "pending", let id = reply.id, completingID != id {
            if recognitionMode == "cloud" { beginSegment(id) }
            else {
                guard preparingID != id else { return }
                lock.lock(); let alreadyStarted = segmentID == id; lock.unlock()
                guard !alreadyStarted, #available(iOS 26.0, *), let locale = phoneLocale else { return }
                preparationTask?.cancel()
                preparingID = id; let current = generation
                preparationTask = Task { @MainActor [weak self] in
                    do {
                        let phone = try await PhoneSpeechRecognizer(locale: locale)
                        guard let self = self, !Task.isCancelled, self.active,
                              self.generation == current, self.preparingID == id else { phone.cancel(); return }
                        self.lock.lock(); self.phoneRecognizer = phone; self.lock.unlock()
                        self.preparingID = nil; self.beginSegment(id)
                    } catch {
                        guard let self = self, self.generation == current, self.preparingID == id else { return }
                        self.stop(message: "手机识别启动失败：\(error.localizedDescription)\n可切回 AWS 云端。")
                    }
                }
            }
        } else if reply.state == "stopping", let id = reply.id {
            finish(id)
        } else if reply.state == "recording", let id = reply.id {
            lock.lock(); let full = samples.count >= 16000 * Lab.maxRecordingSeconds * 4; lock.unlock()
            if full { finish(id) }
        } else if ["cancelled", "error", "idle", "done", "consumed"].contains(reply.state ?? "") {
            preparationTask?.cancel(); preparationTask = nil
            preparingID = nil
            lock.lock(); segmentID = nil; samples = Data(); let phone = phoneRecognizer; phoneRecognizer = nil; lock.unlock()
            if #available(iOS 26.0, *), let phone = phone as? PhoneSpeechRecognizer { phone.cancel() }
        }
    }

    private func beginSegment(_ id: String) {
        lock.lock()
        if segmentID != id { segmentID = id; samples = Data() }
        lock.unlock()
        BridgeClient.call(pairing: pairing, path: "/v1/voice/ack",
                          value: ["id": id, "agent_id": agentID]) { _ in }
        onStatus?(recognitionMode == "cloud" ? "正在录音 · 单段最长 5 分钟，可在键盘停止。" : "手机正在识别 · 单段最长 5 分钟，可在键盘停止。")
    }

    private func finish(_ id: String) {
        guard completingID != id else { return }
        lock.lock()
        guard segmentID == id else { lock.unlock(); return }
        let pcm = samples; samples = Data(); segmentID = nil
        let recognizer = phoneRecognizer; phoneRecognizer = nil
        lock.unlock()
        completingID = id; uploading = true; let current = generation
        if #available(iOS 26.0, *), let phone = recognizer as? PhoneSpeechRecognizer {
            onStatus?("正在收尾手机识别并应用共享热词…")
            finishTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self = self, self.generation == current,
                      self.uploading, self.completingID == id else { return }
                phone.cancel()
                self.stop(message: "手机识别收尾超时，可重新录音或切回 AWS 云端。")
            }
            finalizationTask = Task { @MainActor [weak self] in
                do {
                    let text = try await phone.finish()
                    guard let self = self, !Task.isCancelled, self.generation == current else { return }
                    self.submitSegment(id, path: "/v1/voice/text", content: ["text": text], generation: current)
                } catch {
                    guard let self = self, self.generation == current else { return }
                    self.stop(message: "手机识别未完成：\(error.localizedDescription)\n可重新录音或切回 AWS 云端。")
                }
            }
            return
        }
        guard recognitionMode == "cloud" else {
            stop(message: "手机识别会话已失效，请重新录音或切回 AWS 云端。"); return
        }
        onStatus?("正在将录音提交给配对的识别服务…")
        submitSegment(id, path: "/v1/voice/audio", content: ["encoding": "f32le", "sample_rate": 16000, "audio": pcm.base64EncodedString()], generation: current)
    }

    private func submitSegment(_ id: String, path: String, content: [String: Any], generation current: UUID) {
        var value = content; value["id"] = id; value["agent_id"] = agentID
        BridgeClient.call(pairing: pairing, path: path,
                          value: value,
                          timeout: 190) { [weak self] result in
            guard let self = self, self.generation == current else { return }
            self.finishTimeout?.cancel(); self.finishTimeout = nil
            self.uploading = false
            switch result {
            case .success(let reply):
                self.onStatus?(reply.state == "done" ? "识别完成，键盘会自动输入文字。\n语音会话仍开启，可继续录下一段。" : (reply.error ?? "录音已结束。"))
            case .failure(let error): self.stop(message: "提交失败：\(error.localizedDescription)")
            }
        }
    }

    func stop(message: String = "语音会话已关闭，麦克风已停止。") {
        generation = UUID(); timer?.invalidate(); timer = nil
        preparationTask?.cancel(); preparationTask = nil; preparingID = nil
        finalizationTask?.cancel(); finalizationTask = nil
        finishTimeout?.cancel(); finishTimeout = nil
        let wasActive = active; active = false; starting = false; polling = false; uploading = false
        audio.stop()
        if tapInstalled { audio.inputNode.removeTap(onBus: 0); tapInstalled = false }
        converter = nil
        lock.lock(); segmentID = nil; samples = Data(); let phone = phoneRecognizer; phoneRecognizer = nil; lock.unlock()
        if #available(iOS 26.0, *), let phone = phone as? PhoneSpeechRecognizer { phone.cancel() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if wasActive {
            BridgeClient.call(pairing: pairing, path: "/v1/voice/agent",
                              value: ["agent_id": agentID, "active": false]) { _ in }
        }
        pairing = nil
        onStatus?(message)
        onStopped?()
    }

    @objc private func interrupted(_ notification: Notification) {
        if active { stop(message: "通话或系统音频中断，麦克风已停止。请回主 App 重新开启。") }
    }
    @objc private func routeChanged(_ notification: Notification) {
        guard active, let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              raw != AVAudioSession.RouteChangeReason.categoryChange.rawValue else { return }
        stop(message: "麦克风设备已变化，请重新开启语音会话。")
    }
}
