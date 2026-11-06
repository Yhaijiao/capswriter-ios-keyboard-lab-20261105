import AppIntents
import Foundation

// This special intent is declared in app/keyboard/widget targets. Only the
// containing app includes microphone code. Extension execution fails closed.
@available(iOS 18.0, *)
struct StartKeyboardRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "开启键盘语音会话（实验）"
    static var openAppWhenRun: Bool = false
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
#if CAPSWRITER_CONTAINING_APP
        try await VoiceIntentCoordinator.shared.armFromIntent()
        return .result()
#else
        throw RecordingIntentError.wrongProcess
#endif
    }
}

@available(iOS 18.0, *)
struct StopKeyboardRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "关闭键盘语音会话"
    static var openAppWhenRun: Bool = false
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
#if CAPSWRITER_CONTAINING_APP
        VoiceIntentCoordinator.shared.session.stop()
        return .result()
#else
        throw RecordingIntentError.wrongProcess
#endif
    }
}

enum RecordingIntentError: LocalizedError {
    case wrongProcess, microphonePermission, liveActivityDisabled, invalidPairing, startFailed
    var errorDescription: String? {
        switch self {
        case .wrongProcess: return "系统未把实验操作交给主 App，请先回 Lab 开启会话。"
        case .microphonePermission: return "请先在 Lab 允许麦克风，再重试实验。"
        case .liveActivityDisabled: return "请先允许 Lab 的实时活动，再重试实验。"
        case .invalidPairing: return "请先在 Lab 保存有效的识别服务配对。"
        case .startFailed: return "实验未能开启麦克风，请回 Lab 查看状态。"
        }
    }
}
