import Foundation
import UniformTypeIdentifiers

struct WordCountMatch: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let words: Int
    let fileName: String
}

struct WordCountAttempt: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let title: String?
    let words: Int?
    let failure: String?

    var isSuccess: Bool { failure == nil }
}

enum WordCountBookState {
    case existing
    case success
    case failed
    case missing
}

struct WordCountBookResult: Identifiable {
    let id = UUID()
    let title: String
    var subjectID: String? = nil
    let state: WordCountBookState
    let words: Int?
    let fileName: String?
    let reason: String?
}

struct WordCountImportResult {
    var updated: [WordCountMatch] = []
    var failures: [String] = []
    var attempts: [WordCountAttempt] = []
    var books: [WordCountBookResult] = []
}

private struct WordCountBook {
    var title: String
    var recordIDs: [UUID]
    var doulistItemIDs: [UUID]
}

enum WordCountService {
    static let supportedExtensions: Set<String> = ["txt", "text", "md", "epub", "docx"]

    static var supportedTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        return types
    }

    private static func importFile(
        _ url: URL,
        matcher: (String) -> WordCountBook?,
        nearTitles: (String) -> String,
        into store: LibraryStore,
        result: inout WordCountImportResult
    ) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let name = baseName(for: url)
        log("file=\(url.lastPathComponent) base=\(name) normalized=\(normalize(name))")
        guard let book = matcher(name) else {
            let reason = L10n.Error.noFileMatch(name)
            let target = normalize(name)
            let near = nearTitles(target)
            log("no-match file=\(url.lastPathComponent) target=\(target) near=\(near)")
            result.failures.append("\(url.lastPathComponent)：\(reason)")
            result.attempts.append(WordCountAttempt(fileName: url.lastPathComponent, title: nil, words: nil, failure: reason))
            return
        }
        log("matched file=\(url.lastPathComponent) title=\(book.title) records=\(book.recordIDs.count) doulists=\(book.doulistItemIDs.count)")
        do {
            let text = try plainText(from: url)
            let words = countWords(text)
            guard words > 0 else {
                let reason = L10n.Error.noBody
                result.failures.append("\(url.lastPathComponent)：\(reason)")
                result.attempts.append(WordCountAttempt(fileName: url.lastPathComponent, title: book.title, words: nil, failure: reason))
                return
            }
            for id in book.recordIDs {
                guard var record = store.record(id: id) else { continue }
                record.wordCount = words
                store.updateRecord(record)
                store.refreshPlanItemStats(subjectID: record.subjectID, mediaType: record.mediaType)
            }
            for id in book.doulistItemIDs {
                guard var item = store.doulistItems.first(where: { $0.id == id }) else { continue }
                item.wordCount = words
                store.updateDoulistItem(item)
                store.refreshPlanItemStats(subjectID: item.subjectID, mediaType: item.mediaType, statsText: item.statsText)
            }
            result.updated.append(WordCountMatch(title: book.title, words: words, fileName: url.lastPathComponent))
            result.attempts.append(WordCountAttempt(fileName: url.lastPathComponent, title: book.title, words: words, failure: nil))
            log("counted file=\(url.lastPathComponent) title=\(book.title) words=\(words)")
        } catch {
            let reason = error.localizedDescription
            log("read-failed file=\(url.lastPathComponent) error=\(reason)")
            result.failures.append("\(url.lastPathComponent)：\(reason)")
            result.attempts.append(WordCountAttempt(fileName: url.lastPathComponent, title: book.title, words: nil, failure: reason))
        }
    }

    static func matchableFileCount(in root: URL) -> Int {
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        while let file = enumerator.nextObject() as? URL {
            if supportedExtensions.contains(file.pathExtension.lowercased()) { count += 1 }
        }
        return count
    }

    static func importFolders(_ urls: [URL], into store: LibraryStore) -> WordCountImportResult {
        var result = WordCountImportResult()
        let allBooks = store.activeRecords(media: .book)
        let books = wordCountCandidates(in: store)
        let allowed = supportedExtensions
        log("scan start folders=\(urls.count) allBooks=\(allBooks.count) doulistBooks=\(store.doulistItems.filter { $0.mediaType == .book }.count) candidates=\(books.count)")
        log("candidate sample=\(books.prefix(8).map { "\($0.title)|\(normalize($0.title))" }.joined(separator: " || "))")

        var unsupported: [(name: String, ext: String)] = []
        for root in urls {
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                result.failures.append("\(root.lastPathComponent)：\(L10n.Error.folderUnreadable)")
                continue
            }
            var files: [URL] = []
            var allNames: [String] = []
            while let file = enumerator.nextObject() as? URL {
                allNames.append(file.lastPathComponent)
                let ext = file.pathExtension.lowercased()
                guard allowed.contains(ext) else {
                    unsupported.append((file.lastPathComponent, ext))
                    continue
                }
                files.append(file)
            }
            log("folder=\(root.lastPathComponent) files=\(files.count) all=\(allNames.count) unsupported=\(unsupported.count) access=\(access)")
            log("folder-all=\(root.lastPathComponent) names=\(allNames.joined(separator: " | "))")
            let candidates = books
            let matcher: (String) -> WordCountBook? = { matchBook(name: $0, books: candidates) }
            let nearTitles: (String) -> String = { target in
                candidates.filter {
                    let title = normalize($0.title)
                    return !title.isEmpty && (title.contains(target) || target.contains(title))
                }.prefix(3).map { "\($0.title)|\(normalize($0.title))" }.joined(separator: " || ")
            }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                importFile(file, matcher: matcher, nearTitles: nearTitles, into: store, result: &result)
            }
        }
        let unsupportedResults = unsupported.map { item in
            WordCountBookResult(
                title: item.name,
                state: .failed,
                words: nil,
                fileName: nil,
                reason: item.ext.isEmpty ? L10n.Error.noExtension : L10n.Error.unsupportedExtension(item.ext)
            )
        }
        result.books = makeBookResults(store: store, attempts: result.attempts) + unsupportedResults
        log("scan done matched=\(result.updated.count) failures=\(result.failures.count) unsupported=\(unsupportedResults.count) books=\(result.books.count)")
        return result
    }

    static func clearWordCounts(in store: LibraryStore) {
        for record in store.records where record.mediaType == .book && record.wordCount != nil {
            var value = record
            value.wordCount = nil
            store.updateRecord(value)
        }
        for item in store.doulistItems where item.mediaType == .book && item.wordCount != nil {
            var value = item
            value.wordCount = nil
            store.updateDoulistItem(value)
        }
    }

    private static func makeBookResults(store: LibraryStore, attempts: [WordCountAttempt]) -> [WordCountBookResult] {
        struct Group {
            var title: String
            var subjectID: String
            var existingWords: Int?
        }
        var groups: [String: Group] = [:]
        var order: [String] = []

        func add(title: String, subjectID: String, words: Int?) {
            let key = bookKey(title: title, subjectID: subjectID)
            guard !key.isEmpty else { return }
            let cleanID = subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
            if var group = groups[key] {
                if group.subjectID.isEmpty, !cleanID.isEmpty { group.subjectID = cleanID }
                if group.existingWords == nil, let words, words > 0 { group.existingWords = words }
                groups[key] = group
            } else {
                groups[key] = Group(
                    title: title,
                    subjectID: cleanID,
                    existingWords: (words ?? 0) > 0 ? words : nil
                )
                order.append(key)
            }
        }

        for record in store.activeRecords(media: .book) {
            add(title: record.title, subjectID: record.subjectID, words: record.wordCount)
        }
        for item in store.doulistItems where item.mediaType == .book {
            add(title: item.title, subjectID: item.subjectID, words: item.wordCount)
        }

        var attemptByKey: [String: WordCountAttempt] = [:]
        for attempt in attempts {
            guard let title = attempt.title else { continue }
            let key = normalize(title)
            if attemptByKey[key]?.isSuccess == true { continue }
            attemptByKey[key] = attempt
        }

        let results = order.compactMap { key -> WordCountBookResult? in
            guard let group = groups[key] else { return nil }
            let attempt = attemptByKey[normalize(group.title)]
            if let attempt, attempt.isSuccess {
                return WordCountBookResult(title: group.title, subjectID: group.subjectID.isEmpty ? nil : group.subjectID, state: .success, words: attempt.words, fileName: attempt.fileName, reason: nil)
            }
            if let attempt, let reason = attempt.failure {
                return WordCountBookResult(title: group.title, subjectID: group.subjectID.isEmpty ? nil : group.subjectID, state: .failed, words: nil, fileName: attempt.fileName, reason: reason)
            }
            if let words = group.existingWords {
                return WordCountBookResult(title: group.title, subjectID: group.subjectID.isEmpty ? nil : group.subjectID, state: .existing, words: words, fileName: nil, reason: nil)
            }
            return WordCountBookResult(title: group.title, subjectID: group.subjectID.isEmpty ? nil : group.subjectID, state: .missing, words: nil, fileName: nil, reason: L10n.Error.noMatchingFile)
        }
        return results.sorted {
            let lhs = stateOrder($0.state), rhs = stateOrder($1.state)
            return lhs == rhs ? $0.title.localizedCompare($1.title) == .orderedAscending : lhs < rhs
        }
    }

    private static func stateOrder(_ state: WordCountBookState) -> Int {
        switch state {
        case .success: 0
        case .failed: 1
        case .missing: 2
        case .existing: 3
        }
    }

    private static func wordCountCandidates(in store: LibraryStore) -> [WordCountBook] {
        var books: [WordCountBook] = []
        var indexByKey: [String: Int] = [:]

        func append(title: String, subjectID: String, recordID: UUID? = nil, doulistItemID: UUID? = nil) {
            let key = bookKey(title: title, subjectID: subjectID)
            guard !key.isEmpty else { return }
            if let index = indexByKey[key] {
                if let recordID { books[index].recordIDs.append(recordID) }
                if let doulistItemID { books[index].doulistItemIDs.append(doulistItemID) }
            } else {
                indexByKey[key] = books.count
                books.append(WordCountBook(
                    title: title,
                    recordIDs: recordID.map { [$0] } ?? [],
                    doulistItemIDs: doulistItemID.map { [$0] } ?? []
                ))
            }
        }

        for record in store.records where record.mediaType == .book && !record.isDeleted && (record.wordCount ?? 0) == 0 {
            append(title: record.title, subjectID: record.subjectID, recordID: record.id)
        }
        for item in store.doulistItems where item.mediaType == .book && (item.wordCount ?? 0) == 0 {
            append(title: item.title, subjectID: item.subjectID, doulistItemID: item.id)
        }
        return books
    }

    private static func bookKey(title: String, subjectID: String) -> String {
        let id = subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "title:\(normalize(title))" : "subject:\(id)"
    }

    private static func matchBook(name: String, books: [WordCountBook]) -> WordCountBook? {
        let target = normalize(name)
        if let exact = books.first(where: { normalize($0.title) == target }) { return exact }
        if let raw = books.first(where: {
            let title = $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return !title.isEmpty && (name.contains(title) || title.contains(name))
        }) { return raw }
        if let contains = books.first(where: {
            let title = normalize($0.title)
            return !title.isEmpty && (target.contains(title) || title.contains(target))
        }) { return contains }
        let base = name.components(separatedBy: CharacterSet(charactersIn: "-—_()（）【】[]")).first ?? name
        let baseNormalized = normalize(base)
        return books.first { normalize($0.title) == baseNormalized }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || isCJK($0) }
            .map(String.init)
            .joined()
    }

    private static func plainText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "txt", "md", "text":
            return try decodeText(Data(contentsOf: url))
        case "epub":
            return try epubText(url)
        case "docx":
            return try docxText(url)
        default:
            throw WordCountError.unsupported
        }
    }

    private static func decodeText(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gb18030) { return text }
        throw WordCountError.encoding
    }

    private static func baseName(for url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        let inner = (name as NSString).pathExtension.lowercased()
        if supportedExtensions.contains(inner) {
            name = (name as NSString).deletingPathExtension
        }
        return name
    }

    private static func docxText(_ url: URL) throws -> String {
        let entries = try MiniZip.entries(at: url, suffixes: ["word/document.xml"])
        guard let document = entries.first else { throw WordCountError.missingContent }
        return stripMarkup(String(decoding: document.data, as: UTF8.self))
    }

    private static func epubText(_ url: URL) throws -> String {
        let all = try MiniZip.entries(at: url, suffixes: [".xhtml", ".html", ".htm", ".opf", ".xml"])
        let htmlEntries = all.filter {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm")
        }
        guard !htmlEntries.isEmpty else { throw WordCountError.missingContent }

        let spine = try epubSpine(all: all)
        let selected = spine.isEmpty
            ? htmlEntries
            : htmlEntries.filter { entry in spine.contains { matches(path: $0, entry: entry.name) } }
        let content = selected.isEmpty ? htmlEntries : selected
        return content.map { stripMarkup(String(decoding: $0.data, as: UTF8.self)) }.joined(separator: "\n")
    }

    private static func epubSpine(all: [MiniZipEntry]) throws -> [String] {
        guard let container = all.first(where: { $0.name == "META-INF/container.xml" }),
              let containerXML = String(data: container.data, encoding: .utf8),
              let rootPath = firstMatch(in: containerXML, pattern: #"full-path="([^"]+)""#) else {
            return []
        }
        guard let opf = all.first(where: { $0.name == rootPath }),
              let opfXML = String(data: opf.data, encoding: .utf8) else {
            return []
        }
        let base = (rootPath as NSString).deletingLastPathComponent
        let items = matches(in: opfXML, pattern: #"<item\b([^>]*)/?>"#)
        var manifest: [String: String] = [:]
        for item in items {
            guard let id = firstMatch(in: item, pattern: #"id="([^"]+)""#),
                  let href = firstMatch(in: item, pattern: #"href="([^"]+)""#) else { continue }
            manifest[id] = href
        }
        let refs = matches(in: opfXML, pattern: #"<itemref\b([^>]*)/?>"#)
        return refs.compactMap { ref in
            guard let idref = firstMatch(in: ref, pattern: #"idref="([^"]+)""#),
                  let href = manifest[idref] else { return nil }
            return base.isEmpty ? href : "\(base)/\(href)"
        }
    }

    private static func matches(path: String, entry: String) -> Bool {
        if path == entry { return true }
        if path.contains("%") {
            let decoded = path.removingPercentEncoding ?? path
            if decoded == entry { return true }
        }
        return path.hasSuffix(entry) || entry.hasSuffix(path)
    }

    private static func stripMarkup(_ input: String) -> String {
        var value = input
        value = value.replacingOccurrences(of: #"<script\b[^>]*>[\s\S]*?</script>"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"<style\b[^>]*>[\s\S]*?</style>"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")
        ]
        for (source, target) in entities {
            value = value.replacingOccurrences(of: source, with: target)
        }
        value = value.replacingOccurrences(of: #"&#(\d+);"#, with: " ", options: .regularExpression)
        return value
    }

    static func countWords(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                count += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord {
                    count += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return count
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return String(text[valueRange])
        }
    }
}

private extension WordCountService {
    static func log(_ message: String) {
        NSLog("[WordCount] %@", message)
    }
}

private enum WordCountError: LocalizedError {
    case unsupported
    case encoding
    case missingContent

    var errorDescription: String? {
        switch self {
        case .unsupported: L10n.Error.unsupportedFile
        case .encoding: L10n.Error.encoding
        case .missingContent: L10n.Error.missingContent
        }
    }
}
