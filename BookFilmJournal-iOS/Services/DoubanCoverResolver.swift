import Foundation

enum DoubanCoverResolver {
    struct Parsed {
        var subjectID: String
        var media: MediaType?
        var directImageURL: String?
    }

    static func parse(_ text: String) -> Parsed? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let value = raw.removingPercentEncoding ?? raw

        if let url = URL(string: value),
           let ext = url.pathExtension.lowercased().split(separator: "?").first.map(String.init),
           ["jpg", "jpeg", "png", "webp", "avif"].contains(ext) {
            return Parsed(subjectID: "", media: nil, directImageURL: value)
        }

        guard let range = value.range(of: #"/(?:subject|movie|book)/([0-9]{3,})"#, options: .regularExpression) else {
            if value.range(of: #"^[0-9]{3,}$"#, options: .regularExpression) != nil {
                return Parsed(subjectID: value, media: nil, directImageURL: nil)
            }
            return nil
        }
        let matched = String(value[range])
        guard let id = matched.split(separator: "/").last.map(String.init) else { return nil }
        let lower = value.lowercased()
        let media: MediaType?
        if lower.contains("book.douban") || lower.contains("/book/") || lower.contains("type=book") {
            media = .book
        } else if lower.contains("movie.douban") || lower.contains("/movie/") || lower.contains("type=movie") {
            media = .movie
        } else {
            media = nil
        }
        return Parsed(subjectID: id, media: media, directImageURL: nil)
    }

    static func coverURL(for text: String, fallbackMedia: MediaType, cookie: String?) async -> String? {
        guard let parsed = parse(text) else { return nil }
        if let direct = parsed.directImageURL { return direct }
        let media = parsed.media ?? fallbackMedia
        if let meta = await SubjectDetailService.fetch(subjectID: parsed.subjectID, media: media, typeHint: nil, cookie: cookie),
           let cover = meta.coverURL, !cover.isEmpty {
            return cover
        }
        return await htmlCoverURL(subjectID: parsed.subjectID, media: media, cookie: cookie)
    }

    private static func htmlCoverURL(subjectID: String, media: MediaType, cookie: String?) async -> String? {
        let host = media == .book ? "book.douban.com" : "movie.douban.com"
        guard let url = URL(string: "https://\(host)/subject/\(subjectID)/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if let cookie, !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let patterns = [
            #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)"#,
            #"<link[^>]+rel=["']image_src["'][^>]+href=["']([^"']+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return nil
    }
}
