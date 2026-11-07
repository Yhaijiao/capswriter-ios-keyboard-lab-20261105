import AppIntents
import SwiftUI

@available(iOS 18.0, *)
struct KeyboardVoiceIntentControl: View {
    var isEnabled = true
    var onRequested: () -> Void
    var body: some View {
        Button(intent: StartKeyboardRecordingIntent()) {
            Image(systemName: "mic.fill")
                .font(.system(size: 35))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.94), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("开始语音输入（后台启动实验）")
        .accessibilityIdentifier("keyboard-voice-button")
        .simultaneousGesture(TapGesture().onEnded { if isEnabled { onRequested() } })
    }
}
