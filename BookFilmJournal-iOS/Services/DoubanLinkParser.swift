import Foundation

struct ParsedDoubanSubject {
    var mediaType: MediaType
    var subjectID: String
    var title: String
    var url: String
    var year: String?
    var intro: String
    var durationMinutes: Int?
    var pages: Int?
}

enum DoubanLinkError: LocalizedError {
    case invalidURL
    case wrongMedia
    case notFound
    case parse

    var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.Error.invalidLink
        case .wrongMedia: L10n.Error.wrongMedia
        case .notFound: L10n.Error.notFound
        case .parse: L10n.Error.parseDouban
        }
    }
}

@MainActor
enum DoubanLinkParser {
    private struct SubjectResponse: Codable {
        var id: String
        var title: String
        var url: String?
        var year: String?
        var intro: String?
        var durations: [String]?
        var pages: [String]?
        var pubdate: [String]?
    }

    static func parse(_ raw: String, expected: MediaType) async throws -> ParsedDoubanSubject {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let subjectID = firstMatch(in: text, pattern: #"/subject/(\d+)"#) else {
            throw DoubanLinkError.invalidURL
        }
        let media: MediaType
        if text.contains("book.douban.com") { media = .book }
        else if text.contains("movie.douban.com") { media = .movie }
        else { media = expected }
        guard media == expected else { throw DoubanLinkError.wrongMedia }

        let type = media == .movie ? "movie" : "book"
        guard let url = URL(string: "https://m.douban.com/rexxar/api/v2/\(type)/\(subjectID)") else {
            throw DoubanLinkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DoubanLinkError.parse }
        if http.statusCode == 404 { throw DoubanLinkError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw DoubanLinkError.parse }
        guard let subject = try? JSONDecoder().decode(SubjectResponse.self, from: data) else {
            throw DoubanLinkError.parse
        }

        let year = subject.year
            ?? subject.pubdate?.first.flatMap { firstMatch(in: $0, pattern: #"((?:19|20)\d{2})"#) }
        let duration = subject.durations?.first.flatMap { firstMatch(in: $0, pattern: #"(\d+)\s*分钟"#) }.flatMap(Int.init)
        let pages = subject.pages?.first.flatMap { firstMatch(in: $0, pattern: #"(\d+)"#) }.flatMap(Int.init)
        let canonical = subject.url ?? "https://\(media == .movie ? "movie" : "book").douban.com/subject/\(subjectID)/"
        return ParsedDoubanSubject(
            mediaType: media,
            subjectID: subject.id.isEmpty ? subjectID : subject.id,
            title: subject.title,
            url: canonical,
            year: year,
            intro: subject.intro ?? "",
            durationMinutes: duration,
            pages: pages
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }
}
