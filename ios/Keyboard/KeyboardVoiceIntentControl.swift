import SwiftUI

@available(iOS 18.0, *)
struct KeyboardVoiceIntentControl: View {
    var onRequested: () -> Void
    var body: some View {
        Button(intent: StartKeyboardRecordingIntent()) {
            Label("实验开启语音", systemImage: "mic.badge.plus")
                .font(.system(size: 13)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(.orange)
        .accessibilityIdentifier("keyboard-experimental-voice-intent")
        .simultaneousGesture(TapGesture().onEnded { onRequested() })
    }
}
