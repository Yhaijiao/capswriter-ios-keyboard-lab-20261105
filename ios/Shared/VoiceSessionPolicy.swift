import Foundation

/// One automatic attempt per foreground visit. Permission sheets and layout
/// callbacks do not count as a new visit; an actual background transition does.
struct VoiceSessionAutoStartPolicy {
    private var attemptedThisVisit = false

    mutating func shouldStart(enabled: Bool, configured: Bool, foreground: Bool, busy: Bool) -> Bool {
        guard enabled, configured, foreground, !attemptedThisVisit else { return false }
        attemptedThisVisit = true
        return !busy
    }

    mutating func enteredBackground() { attemptedThisVisit = false }
    mutating func configurationChanged() { attemptedThisVisit = false }
    mutating func userStoppedOrStarted() { attemptedThisVisit = true }
}
