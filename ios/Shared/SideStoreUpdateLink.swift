import Foundation

enum SideStoreUpdateLink {
    private static let download = "https://github.com/Yhaijiao/saykey-ios-keyboard/releases/download/lab-phone-asr/CapsWriterLab-sideload.ipa"

    static func make() -> URL? {
        var link = URLComponents()
        link.scheme = "sidestore"
        link.host = "install"
        link.queryItems = [URLQueryItem(name: "url", value: download)]
        return link.url
    }
}
