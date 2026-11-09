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
    private var sessionMinutes = 60
    /// A renewal that arrived while the session was still starting.
    private var pendingMinutes = 0
    private var recognitionMode = "cloud"
    private var phoneLocale: Locale?
    private var phoneRecognizer: AnyObject?
    private var preparingID: String?
    private var preparationTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var finishTimeout: Task<Void, Never>?
    private var binaryAudio = false
    /// Send audio in small pieces while recording, so the service can show a
    /// live draft and needs no big upload at the end.
    private var streamAudio = false
    /// Bytes of int16 audio the service has confirmed for the current segment.
    private var streamedBytes = 0
    private var chunkInFlight = false
    /// Largest live chunk the service accepts (bridge MAX_CHUNK_S16, 10 s).
    private static let maxChunkBytes = 16000 * 2 * 10
    /// Server reply when streamed audio has a gap (bridge finish_stream).
    private static let incompleteStream = "流式录音不完整"
    /// The service keeps a job this long without a heartbeat (bridge HEARTBEAT_GRACE).
    private static let heartbeatGrace: TimeInterval = 20

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    /// Remaining session time, or nil while the microphone is off.
    var remaining: TimeInterval? { active ? max(0, expires.timeIntervalSinceNow) : nil }

    /// Opened from the keyboard: keep a live session going for `minutes`
    /// without restarting the microphone, or start one if it has lapsed.
    func renew(pairing: BridgePairing, minutes: Int) {
        if active {
            extend(minutes: minutes)
            onStatus?("语音会话已续到 \(minutes) 分钟 · 麦克风持续工作。\n点左上角「◀」回到刚才的 App，键盘会自动开始录音。")
            return
        }
        if starting { pendingMinutes = max(pendingMinutes, minutes); return }
        start(pairing: pairing, sessionMinutes: minutes)
    }

    private func extend(minutes: Int) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        if until > expires { expires = until }
    }

    func start(pairing: BridgePairing, sessionMinutes: Int = 60, intentActivityID: String? = nil) {
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
                    self.onStatus?("请启动配对的语音识别服务后重试。")
                    return
                }
                self.binaryAudio = reply.audio_s16_v1 == true
                self.streamAudio = reply.audio_stream_v1 == true && self.recognitionMode == "cloud"
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
        self.sessionMinutes = max([10, 30, 60].contains(sessionMinutes) ? sessionMinutes : 60, pendingMinutes)
        pendingMinutes = 0
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
        lock.lock(); let framesAge = Date().timeIntervalSince(lastFrames); let recording = segmentID != nil; lock.unlock()
        // The session timer counts from when Lab switched voice on. Never let it
        // cut a segment that is still recording, preparing or uploading.
        let segmentInFlight = recording || uploading || preparingID != nil
        if Date() > expires && !segmentInFlight { stop(message: "\(sessionMinutes) 分钟语音会话已结束，麦克风已关闭。"); return }
        if !audio.isRunning || framesAge > 5 { stop(message: "麦克风已中断，请重新开启语音会话。"); return }
        // A whole-segment upload can hold up heartbeats on cellular; the upload
        // request itself reports success or failure.
        if !uploading && Date().timeIntervalSince(lastSuccess) > Self.heartbeatGrace {
            stop(message: "识别服务连接已断开，麦克风已关闭。"); return
        }
        sendLiveChunk()
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
            // After the session timer runs out, finish the current segment only.
            guard Date() <= expires else { return }
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
        // Every recording renews the session, so a session in use never runs
        // out and the keyboard only needs Lab once it has actually lapsed.
        extend(minutes: sessionMinutes)
        lock.lock()
        if segmentID != id { segmentID = id; samples = Data(); streamedBytes = 0 }
        lock.unlock()
        chunkInFlight = false
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
        if streamAudio {
            finishStream(id, pcm: pcm, generation: current)
        } else if binaryAudio {
            submitAudio(id, pcm: Self.int16PCM(pcm), generation: current)
        } else {
            submitSegment(id, path: "/v1/voice/audio", content: ["encoding": "f32le", "sample_rate": 16000, "audio": pcm.base64EncodedString()], generation: current)
        }
    }

    /// While recording, send whatever audio the service has not confirmed yet.
    /// One request at a time; a failed or gapped chunk is simply resent from
    /// the service's `received` position on the next tick.
    private func sendLiveChunk() {
        guard streamAudio, !chunkInFlight, !uploading else { return }
        lock.lock()
        guard let id = segmentID else { lock.unlock(); return }
        let start = streamedBytes * 2
        let end = min(samples.count, start + Self.maxChunkBytes * 2)
        // About 0.3 s at a time keeps requests few without lagging the draft.
        guard end - start >= 16000 * 4 * 3 / 10 else { lock.unlock(); return }
        let offset = streamedBytes
        let chunk = Self.int16PCM(samples.subdata(in: start..<end))
        lock.unlock()
        chunkInFlight = true; let current = generation
        let query = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "agent_id", value: agentID),
                     URLQueryItem(name: "offset", value: String(offset))]
        BridgeClient.upload(pairing: pairing, path: "/v1/voice/chunk", query: query, body: chunk, timeout: 10) { [weak self] result in
            guard let self = self, self.generation == current else { return }
            self.chunkInFlight = false
            guard case .success(let reply) = result else { return }
            self.lastSuccess = Date()
            self.lock.lock()
            if self.segmentID == id, let received = reply.received, received >= 0 {
                self.streamedBytes = min(received, self.samples.count / 2)
            }
            self.lock.unlock()
        }
    }

    /// Send the last unconfirmed audio, then ask the service to recognize what
    /// it already has. Any gap falls back to the usual whole-segment upload.
    private func finishStream(_ id: String, pcm: Data, generation current: UUID) {
        let total = pcm.count / 2
        let offset = min(streamedBytes, total)
        let fallback: () -> Void = { [weak self] in
            self?.submitAudio(id, pcm: Self.int16PCM(pcm), generation: current)
        }
        guard total - offset <= Self.maxChunkBytes else { fallback(); return }
        let finishCall = { [weak self] in
            guard let self = self, self.generation == current else { return }
            self.submitStreamFinish(id, total: total, generation: current, fallback: fallback)
        }
        guard total > offset else { finishCall(); return }
        let query = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "agent_id", value: agentID),
                     URLQueryItem(name: "offset", value: String(offset))]
        let tail = Self.int16PCM(pcm.subdata(in: offset * 2..<pcm.count))
        BridgeClient.upload(pairing: pairing, path: "/v1/voice/chunk", query: query, body: tail, timeout: 20) { [weak self] result in
            guard let self = self, self.generation == current else { return }
            if case .success(let reply) = result, reply.received == total { finishCall() } else { fallback() }
        }
    }

    private func submitStreamFinish(_ id: String, total: Int, generation current: UUID,
                                    fallback: @escaping () -> Void, attempt: Int = 1) {
        BridgeClient.call(pairing: pairing, path: "/v1/voice/finish",
                          value: ["id": id, "agent_id": agentID, "total": total], timeout: 190) { [weak self] result in
            guard let self = self, self.generation == current else { return }
            if case .failure(let error) = result, let bridge = error as? BridgeError,
               case .message(let text) = bridge, text.contains(Self.incompleteStream) {
                fallback(); return
            }
            self.submitted(id, result: result, generation: current, attempt: attempt) {
                self.submitStreamFinish(id, total: total, generation: current, fallback: fallback, attempt: attempt + 1)
            }
        }
    }

    /// 16-bit little-endian PCM: half the size of float32, and sent as a raw
    /// body instead of base64 (5 minutes ≈ 9.6 MB instead of 25.6 MB).
    static func int16PCM(_ float32: Data) -> Data {
        let count = float32.count / 4
        var output = Data(count: count * 2)
        float32.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                for index in 0..<count {
                    let sample = source.loadUnaligned(fromByteOffset: index * 4, as: Float.self)
                    let clamped = sample.isFinite ? max(-1, min(1, sample)) : 0
                    target.storeBytes(of: Int16(clamped * 32767).littleEndian, toByteOffset: index * 2, as: Int16.self)
                }
            }
        }
        return output
    }

    private func submitAudio(_ id: String, pcm: Data, generation current: UUID, attempt: Int = 1) {
        let query = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "agent_id", value: agentID),
                     URLQueryItem(name: "encoding", value: "s16le"), URLQueryItem(name: "sample_rate", value: "16000")]
        BridgeClient.upload(pairing: pairing, path: "/v1/voice/audio", query: query, body: pcm) { [weak self] result in
            self?.submitted(id, result: result, generation: current, attempt: attempt) {
                self?.submitAudio(id, pcm: pcm, generation: current, attempt: attempt + 1)
            }
        }
    }

    private func submitSegment(_ id: String, path: String, content: [String: Any], generation current: UUID, attempt: Int = 1) {
        var value = content; value["id"] = id; value["agent_id"] = agentID
        BridgeClient.call(pairing: pairing, path: path,
                          value: value,
                          timeout: 190) { [weak self] result in
            self?.submitted(id, result: result, generation: current, attempt: attempt) {
                self?.submitSegment(id, path: path, content: content, generation: current, attempt: attempt + 1)
            }
        }
    }

    private func submitted(_ id: String, result: Result<BridgeReply, Error>, generation current: UUID,
                           attempt: Int, retry: @escaping () -> Void) {
        guard generation == current else { return }
        if case .failure(let error) = result, BridgeError.isTransient(error), attempt < 3 {
            // A cellular drop mid-upload: the service puts the job back to
            // stopping, so the same segment can be sent again.
            onStatus?("网络不稳，正在重新提交录音（第 \(attempt + 1) 次）…")
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 2) { [weak self] in
                guard let self = self, self.generation == current, self.active else { return }
                retry()
            }
            return
        }
        finishTimeout?.cancel(); finishTimeout = nil
        uploading = false
        switch result {
        case .success(let reply):
            lastSuccess = Date()
            onStatus?(reply.state == "done" ? "识别完成，键盘会自动输入文字。\n语音会话仍开启，可继续录下一段。" : (reply.error ?? "录音已结束。"))
        case .failure(let error):
            // Keep the session; only this segment is lost. Release the job so
            // the keyboard shows the failure instead of waiting for a result.
            if BridgeError.isTransient(error) {
                BridgeClient.call(pairing: pairing, path: "/v1/voice/cancel", value: ["id": id]) { _ in }
            }
            lastSuccess = Date()
            onStatus?("这段录音提交失败：\(error.localizedDescription)\n语音会话仍开启，可重新录音。")
        }
    }

    func stop(message: String = "语音会话已关闭，麦克风已停止。") {
        generation = UUID(); timer?.invalidate(); timer = nil
        preparationTask?.cancel(); preparationTask = nil; preparingID = nil
        finalizationTask?.cancel(); finalizationTask = nil
        finishTimeout?.cancel(); finishTimeout = nil
        let wasActive = active; active = false; starting = false; polling = false; uploading = false
        chunkInFlight = false
        pendingMinutes = 0
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
