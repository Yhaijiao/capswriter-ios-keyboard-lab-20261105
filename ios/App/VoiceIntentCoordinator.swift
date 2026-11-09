import ActivityKit
import AVFoundation
import UIKit

/// One containing-app owner, independent of whether Lab's view controller exists.
@MainActor
final class VoiceIntentCoordinator {
    static let shared = VoiceIntentCoordinator()
    let session = VoiceSession()
    private var activity: Activity<RecordingActivityAttributes>?
    private var arming = false
    private var activityWatcher: Task<Void, Never>?

    var hasActiveActivity: Bool { activity?.activityState == .active }

    private init() {
        session.onStopped = { [weak self] in self?.endActivity() }
    }

    func armFromIntent() async throws {
        guard !arming else { throw RecordingIntentError.startFailed }
        arming = true; defer { arming = false }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw RecordingIntentError.microphonePermission
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw RecordingIntentError.liveActivityDisabled
        }
        guard let pairing = BridgePairingStore.activePairing(), !pairing.isExpired() else { throw RecordingIntentError.invalidPairing }
        if !hasActiveActivity {
            // A force-quit may leave a visible activity without this new process's
            // microphone owner. End only our own stale activities before retrying.
            for old in Activity<RecordingActivityAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }
            let deadline = Date().addingTimeInterval(600)
            let state = RecordingActivityAttributes.ContentState(expiresAt: deadline, message: "语音会话开启期间麦克风持续工作")
            let next = try Activity.request(attributes: RecordingActivityAttributes(sessionID: UUID().uuidString),
                                            content: ActivityContent(state: state, staleDate: deadline), pushType: nil)
            activity = next
            activityWatcher?.cancel()
            activityWatcher = Task { [weak self] in
                for await state in next.activityStateUpdates {
                    guard !Task.isCancelled else { return }
                    if state == .dismissed || state == .ended {
                        self?.session.stop(message: "实时活动已关闭，麦克风已停止。")
                        return
                    }
                }
            }
        }
        guard BridgePairingStore.activePairing() == pairing else {
            endActivity()
            throw RecordingIntentError.invalidPairing
        }
        if session.active { return }
        // Only this explicit, system-dispatched intent can request background arm.
        let saved = UserDefaults.standard.integer(forKey: "voice.sessionMinutes")
        session.start(pairing: pairing, sessionMinutes: [10, 30, 60].contains(saved) ? saved : 60, intentActivityID: activity?.id)
        do {
            for _ in 0..<200 {
                if session.active { return }
                if !session.starting { throw RecordingIntentError.startFailed }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw RecordingIntentError.startFailed
        } catch {
            session.stop(message: "实验开启未完成，麦克风已关闭。")
            throw error
        }
    }

    private func endActivity() {
        activityWatcher?.cancel(); activityWatcher = nil
        let current = activity; activity = nil
        if let current = current {
            Task { await current.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
