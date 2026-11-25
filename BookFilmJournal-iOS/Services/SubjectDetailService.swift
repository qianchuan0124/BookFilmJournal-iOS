import Foundation

struct SubjectDetailMeta {
    var coverURL: String?
    var durationMinutes: Int?
    var pages: Int?
    var wordCount: Int?
    var year: String?
    var releaseDate: String?
}

private final class SubjectSummaryBox: NSObject {
    let meta: SubjectDetailMeta
    init(_ meta: SubjectDetailMeta) { self.meta = meta }
}

enum SubjectDetailService {
    private static let summaryCache: NSCache<NSString, SubjectSummaryBox> = {
        let cache = NSCache<NSString, SubjectSummaryBox>()
        cache.countLimit = 2000
        return cache
    }()
    static func fetch(subjectID: String, media: MediaType, typeHint: String?, cookie: String?, debug: ((String) -> Void)? = nil) async -> SubjectDetailMeta? {
        let path: String
        if typeHint == "tv" {
            path = "tv"
        } else {
            path = media == .book ? "book" : "movie"
        }
        guard let url = URL(string: "https://m.douban.com/rexxar/api/v2/\(path)/\(subjectID)?ck=&for_mobile=1") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue(media == .book ? "https://book.douban.com/" : "https://movie.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        func perform(useCookie: Bool) async -> SubjectDetailMeta? {
            var request = request
            if useCookie, let cookie, !cookie.isEmpty {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                debug?("detail id=\(subjectID) type=\(path) cookie=\(useCookie) status=\(code) bytes=\(data.count)")
                guard (200..<300).contains(code),
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    if !(200..<300).contains(code) {
                        debug?("detail failed id=\(subjectID) body=\(String(decoding: data.prefix(160), as: UTF8.self))")
                    }
                    return nil
                }
                let pic = object["pic"] as? [String: Any]
                let cover = string(object["cover_url"]) ?? string(pic?["large"]) ?? string(pic?["normal"])
                let year = string(object["year"])
                let release = releaseDate(from: object)
                let duration = durationMinutes(from: object["durations"])
                let pageCount = pages(from: object["pages"])
                let wordCount = pages(from: object["word_count"])
                return SubjectDetailMeta(
                    coverURL: cover?.isEmpty == false ? cover : nil,
                    durationMinutes: duration,
                    pages: pageCount,
                    wordCount: wordCount,
                    year: year?.isEmpty == false ? year : nil,
                    releaseDate: release
                )
            } catch {
                debug?("detail error id=\(subjectID) \(error.localizedDescription)")
                return nil
            }
        }
        if let result = await perform(useCookie: cookie?.isEmpty == false) { return result }
        if cookie?.isEmpty == false, let result = await perform(useCookie: false) { return result }
        if media == .movie { return await fetchMovieAbstract(subjectID: subjectID, debug: debug) }
        return nil
    }

    static func fetchSummary(subjectID: String, media: MediaType, cookie: String?, debug: ((String) -> Void)? = nil) async -> SubjectDetailMeta? {
        let cacheKey = "\(media.rawValue)|\(subjectID)"
        if let cached = summaryCache.object(forKey: cacheKey as NSString) { return cached.meta }
        let result: SubjectDetailMeta?
        if media == .movie {
            result = await fetchMovieAbstract(subjectID: subjectID, debug: debug)
        } else {
            result = await fetch(subjectID: subjectID, media: media, typeHint: nil, cookie: cookie, debug: debug)
        }
        if let result { summaryCache.setObject(SubjectSummaryBox(result), forKey: cacheKey as NSString) }
        return result
    }

    private static func fetchMovieAbstract(subjectID: String, debug: ((String) -> Void)?) async -> SubjectDetailMeta? {
        guard let url = URL(string: "https://movie.douban.com/j/subject_abstract?subject_id=\(subjectID)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            debug?("abstract id=\(subjectID) status=\(code) bytes=\(data.count)")
            guard (200..<300).contains(code),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let subject = object["subject"] as? [String: Any] else { return nil }
            let duration = durationMinutes(from: subject["duration"])
            let year = string(subject["release_year"]) ?? string(subject["year"])
            guard duration != nil || year != nil else { return nil }
            return SubjectDetailMeta(durationMinutes: duration, pages: nil, wordCount: nil, year: year, releaseDate: year)
        } catch {
            debug?("abstract error id=\(subjectID) \(error.localizedDescription)")
            return nil
        }
    }

    private static func releaseDate(from object: [String: Any]) -> String? {
        if let values = object["pubdate"] as? [Any] {
            for value in values {
                if let date = extractDate(string(value)) { return date }
            }
        }
        if let release = string(object["release_date"]), let date = extractDate(release) { return date }
        return nil
    }

    private static func extractDate(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if let range = value.range(of: #"\d{4}-\d{1,2}-\d{1,2}"#, options: .regularExpression) {
            return String(value[range])
        }
        if let range = value.range(of: #"(19|20)\d{2}"#, options: .regularExpression) {
            return String(value[range])
        }
        return nil
    }

    private static func durationMinutes(from value: Any?) -> Int? {
        let text: String
        if let values = value as? [Any], let first = values.first {
            text = string(first) ?? ""
        } else {
            text = string(value) ?? ""
        }
        if let range = text.range(of: #"\d+\s*分钟"#, options: .regularExpression) {
            let digits = text[range].filter(\.isNumber)
            return Int(digits)
        }
        if let range = text.range(of: #"\d+(?:\.\d+)?\s*(?:小时|h)"#, options: [.regularExpression, .caseInsensitive]) {
            let number = Double(text[range].filter { $0.isNumber || $0 == "." }) ?? 0
            return Int((number * 60).rounded())
        }
        return nil
    }

    private static func pages(from value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue > 0 ? number.intValue : nil }
        if let values = value as? [Any] {
            for item in values {
                if let number = Int(string(item) ?? "") { return number > 0 ? number : nil }
            }
        }
        if let text = string(value), let number = Int(text.filter(\.isNumber)) { return number > 0 ? number : nil }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}
