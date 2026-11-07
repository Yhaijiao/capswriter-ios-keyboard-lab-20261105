import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RecordingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack {
                Image(systemName: "mic.fill").foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text("CapsWriter 语音会话").bold()
                    Text(context.state.message).font(.caption)
                    Text(context.state.expiresAt, style: .timer).monospacedDigit()
                }
                Spacer()
                if #available(iOS 18.0, *) {
                    Button(intent: StopKeyboardRecordingIntent()) { Image(systemName: "stop.fill") }
                        .accessibilityLabel("关闭语音会话")
                }
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "mic.fill").foregroundStyle(.red) }
                DynamicIslandExpandedRegion(.center) { Text("CapsWriter 语音会话") }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.expiresAt, style: .timer).monospacedDigit()
                        Spacer()
                        if #available(iOS 18.0, *) {
                            Button(intent: StopKeyboardRecordingIntent()) { Label("关闭", systemImage: "stop.fill") }
                        }
                    }
                }
            } compactLeading: { Image(systemName: "mic.fill").foregroundStyle(.red) } compactTrailing: { Text(context.state.expiresAt, style: .timer).monospacedDigit() } minimal: { Image(systemName: "mic.fill").foregroundStyle(.red) }
        }
    }
}
