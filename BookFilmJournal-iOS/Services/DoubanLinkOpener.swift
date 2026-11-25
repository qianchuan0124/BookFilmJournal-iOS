import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DoubanLinkOpener {
    static func open(
        webURLString: String?,
        subjectID: String?,
        media: MediaType?,
        fallback: @escaping (URL) -> Void
    ) {
        guard let webURLString,
              let webURL = URL(string: webURLString) else { return }
        #if canImport(UIKit)
        if let subjectID, !subjectID.isEmpty,
           let appURL = appURL(subjectID: subjectID, media: media) {
            UIApplication.shared.open(appURL, options: [:]) { opened in
                if !opened {
                    DispatchQueue.main.async { fallback(webURL) }
                }
            }
            return
        }
        #endif
        fallback(webURL)
    }

    private static func appURL(subjectID: String, media: MediaType?) -> URL? {
        let kind = media == .book ? "book" : "movie"
        return URL(string: "douban://douban.com/\(kind)/\(subjectID)")
    }
}
