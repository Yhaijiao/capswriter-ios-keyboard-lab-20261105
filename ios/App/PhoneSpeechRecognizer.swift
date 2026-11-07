import Foundation
import AVFoundation
import Speech
import CoreMedia

// Experimental: source saved for continuation; Apple SDK/device validation pending.
@available(iOS 26.0, *)
final class PhoneSpeechRecognizer: @unchecked Sendable {
    enum Failure: LocalizedError {
        case unavailable, unsupportedLocale, unavailableFormat, conversion, overflow, cancelled, alreadyFinished
        var errorDescription: String? {
            switch self {
            case .unavailable: return "此设备暂不支持手机本地识别。"
            case .unsupportedLocale: return "此语言暂不支持手机本地识别。"
            case .unavailableFormat: return "手机本地识别音频格式不可用。"
            case .conversion: return "本地识别音频转换失败，请重新录音。"
            case .overflow: return "本地识别未能及时处理音频，请重新录音。"
            case .cancelled: return "本地识别已取消。"
            case .alreadyFinished: return "本地识别已经结束。"
            }
        }
    }
    private struct Piece { let range: CMTimeRange; let text: String }
    private let lock = NSLock()
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var accepting = true
    private var stopped = false
    private var failure: Error?
    private var pieces: [Piece] = []
    private var startup: Task<Void, Error>?
    private var results: Task<Void, Error>?
    private var finishing: Task<Void, Never>?
    private var waiter: CheckedContinuation<String, Error>?

    static func prepareLocale(_ identifier: String) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else { throw Failure.unsupportedLocale }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        return locale
    }

    init(locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Failure.unavailableFormat }
        let pair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(128))
        transcriber = module; format = audioFormat; continuation = pair.continuation
        analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: audioFormat)
        let engine = analyzer
        results = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self else { return }
                    if result.isFinal { self.accept(range: result.range, text: String(result.text.characters)) }
                }
            } catch { self?.fail(error); throw error }
        }
        startup = Task { [weak self] in
            do { try await engine.start(inputSequence: pair.stream) }
            catch { self?.fail(error); throw error }
        }
    }

    func append(_ pcm16k: AVAudioPCMBuffer) {
        var appendError: Error?
        lock.lock()
        defer { lock.unlock(); if let appendError { fail(appendError) } }
        guard accepting, !stopped, failure == nil, pcm16k.frameLength > 0 else { return }
        do {
            guard pcm16k.format.sampleRate == 16000, pcm16k.format.channelCount == 1,
                  pcm16k.format.commonFormat == .pcmFormatFloat32 else { throw Failure.conversion }
            let owned: AVAudioPCMBuffer
            if pcm16k.format.isEqual(format) {
                guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: pcm16k.frameLength) else { throw Failure.conversion }
                copy.frameLength = pcm16k.frameLength
                let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: pcm16k.audioBufferList))
                let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                for i in 0..<min(src.count, dst.count) {
                    guard let a = src[i].mData, let b = dst[i].mData else { throw Failure.conversion }
                    memcpy(b, a, min(Int(src[i].mDataByteSize), Int(dst[i].mDataByteSize)))
                }
                owned = copy
            } else {
                if converter == nil || sourceFormat?.isEqual(pcm16k.format) != true {
                    guard let newConverter = AVAudioConverter(from: pcm16k.format, to: format) else { throw Failure.conversion }
                    newConverter.primeMethod = .none; converter = newConverter; sourceFormat = pcm16k.format
                }
                let capacity = AVAudioFrameCount(ceil(Double(pcm16k.frameLength) * format.sampleRate / pcm16k.format.sampleRate) + 64)
                guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity), let converter else { throw Failure.conversion }
                var supplied = false
                var conversionError: NSError?
                let status = converter.convert(to: converted, error: &conversionError) { _, flag in
                    if supplied { flag.pointee = .noDataNow; return nil }
                    supplied = true; flag.pointee = .haveData; return pcm16k
                }
                if status == .error { throw conversionError ?? (Failure.conversion as NSError) }
                owned = converted
            }
            if owned.frameLength > 0 { try enqueueLocked(owned) }
        } catch { failure = error; accepting = false; continuation.finish(); appendError = error }
    }

    private func enqueueLocked(_ buffer: AVAudioPCMBuffer) throws {
        switch continuation.yield(AnalyzerInput(buffer: buffer)) {
        case .enqueued: break
        case .dropped: throw Failure.overflow
        case .terminated: throw failure ?? Failure.cancelled
        @unknown default: throw Failure.conversion
        }
    }
    private func accept(range: CMTimeRange, text: String) {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, failure == nil else { return }
        pieces.removeAll { piece in
            CMTimeCompare(piece.range.start, range.start) == 0 ||
            CMTimeGetSeconds(CMTimeRangeGetIntersection(piece.range, otherRange: range).duration) > 0
        }
        pieces.append(Piece(range: range, text: text))
        pieces.sort { CMTimeCompare($0.range.start, $1.range.start) < 0 }
    }
    func finish() async throws -> String {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (pending: CheckedContinuation<String, Error>) in
                lock.lock()
                if let failure { lock.unlock(); pending.resume(throwing: failure); fail(failure); return }
                guard !stopped, waiter == nil else {
                    lock.unlock(); pending.resume(throwing: Failure.alreadyFinished); return
                }
                accepting = false
                do {
                    if let converter {
                        for attempt in 0..<8 {
                            guard let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { throw Failure.conversion }
                            var error: NSError?
                            let status = converter.convert(to: tail, error: &error) { _, flag in
                                flag.pointee = .endOfStream; return nil
                            }
                            if status == .error { throw error ?? (Failure.conversion as NSError) }
                            if tail.frameLength > 0 { try enqueueLocked(tail) }
                            if status == .endOfStream || tail.frameLength == 0 { break }
                            if attempt == 7 { throw Failure.conversion }
                        }
                    }
                } catch {
                    failure = error; continuation.finish(); lock.unlock()
                    pending.resume(throwing: error); fail(error); return
                }
                waiter = pending; continuation.finish()
                let begin = startup, collected = results, engine = analyzer
                finishing = Task { [weak self] in
                    do {
                        try await begin?.value
                        try Task.checkCancellation()
                        try await engine.finalizeAndFinishThroughEndOfInput()
                        try await collected?.value
                        self?.complete()
                    } catch { self?.fail(error) }
                }
                lock.unlock()
            }
        }, onCancel: { self.cancel() })
    }
    private func complete() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let pending = waiter; waiter = nil
        let text = pieces.map(\.text).joined(), error = failure
        pieces.removeAll(); lock.unlock()
        if let error { pending?.resume(throwing: error) }
        else { pending?.resume(returning: text) }
    }
    private func fail(_ error: Error) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true; accepting = false; failure = error; continuation.finish()
        let pending = waiter; waiter = nil
        pieces.removeAll()
        let begin = startup, collected = results, end = finishing, engine = analyzer
        lock.unlock()
        pending?.resume(throwing: error)
        begin?.cancel(); collected?.cancel(); end?.cancel()
        Task { await engine.cancelAndFinishNow() }
    }
    func cancel() { fail(Failure.cancelled) }
}
