import UIKit

/// Sends the user back to the app they were typing in after the keyboard
/// opened Lab to restart the voice session.
///
/// iOS has no public API for this. Two undocumented routes are used, each
/// checked at runtime so a missing piece fails quietly:
/// - up to iOS 26.3 the keyboard reads `_hostBundleID` and passes it along;
/// - on iOS 26.4+ Lab watches the system keyboard state
///   (`_UIRemoteKeyboards.currentState.sourceBundleIdentifier`).
/// The host is then opened by its URL scheme, so only apps in the catalog
/// below can be returned to; others get the "◀" hint.
final class HostAppReturn: NSObject {
    static let shared = HostAppReturn()
    private var observed: NSObject?
    private var lastHost: (bundleID: String, at: Date)?

    /// Bundle ID → URL that opens the app's main screen.
    static let schemes: [String: String] = [
        "com.tencent.xin": "weixin://",
        "com.tencent.mqq": "mqq://",
        "com.tencent.WeWork": "wxwork://",
        "com.apple.MobileSMS": "messages://",
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.mobilemail": "message://",
        "com.apple.reminders": "x-apple-reminderkit://",
        "com.apple.mobilesafari": "x-web-search://",
        "com.anthropic.claude": "claude://",
        "com.openai.chat": "chatgpt://",
        "com.google.Gmail": "googlegmail://",
        "com.google.chrome.ios": "googlechrome://",
        "net.whatsapp.WhatsApp": "whatsapp://",
        "ph.telegra.Telegraph": "tg://",
        "com.facebook.Messenger": "fb-messenger://",
        "com.burbn.instagram": "instagram://",
        "com.atebits.Tweetie2": "twitter://",
        "com.tinyspeck.chatlyio": "slack://",
        "notion.id": "notion://",
        "com.xingin.discover": "xhsdiscover://",
        "com.ss.iphone.ugc.Aweme": "snssdk1128://",
        "com.sina.weibo": "sinaweibo://",
        "com.alipay.iphoneclient": "alipay://",
        "com.microsoft.Office.Outlook": "ms-outlook://",
        "com.linkedin.LinkedIn": "linkedin://",
        "com.hammerandchisel.discord": "discord://",
        "com.larksuite.suite": "lark://",
        "com.ss.iphone.lark": "feishu://",
        "com.laiwang.DingTalk": "dingtalk://"
    ]

    static func isOwn(_ bundleID: String) -> Bool { bundleID.hasPrefix("org.capswriterlab") }

    /// Start watching the system keyboard state. Call once at launch.
    func start() {
        guard observed == nil, let type = NSClassFromString("_UIRemoteKeyboards") else { return }
        let shared = NSSelectorFromString("sharedRemoteKeyboards")
        let typeObject = type as AnyObject
        guard typeObject.responds(to: shared),
              let keyboards = typeObject.perform(shared)?.takeUnretainedValue() as? NSObject,
              keyboards.responds(to: NSSelectorFromString("currentState")) else { return }
        observed = keyboards
        keyboards.addObserver(self, forKeyPath: "currentState", options: [.new, .initial], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "currentState", let state = change?[.newKey] as? NSObject else { return }
        let key = NSSelectorFromString("sourceBundleIdentifier")
        guard state.responds(to: key), let id = state.value(forKey: "sourceBundleIdentifier") as? String,
              !id.isEmpty, !Self.isOwn(id) else { return }
        DispatchQueue.main.async { self.lastHost = (id, Date()) }
    }

    /// The host to return to: the keyboard's report, else one seen recently.
    func host(reported: String?) -> String? {
        if let reported, !Self.isOwn(reported) { return reported }
        guard let last = lastHost, Date().timeIntervalSince(last.at) < 8 else { return nil }
        return last.bundleID
    }

    /// Opens the host app. Returns false when it isn't in the catalog.
    @discardableResult
    func open(_ bundleID: String) -> Bool {
        guard let raw = Self.schemes[bundleID], let url = URL(string: raw) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
