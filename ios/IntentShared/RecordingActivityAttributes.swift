import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var expiresAt: Date
        var message: String
    }
    var sessionID: String
}
