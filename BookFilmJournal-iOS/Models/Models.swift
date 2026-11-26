import Foundation

enum MediaType: String, Codable, CaseIterable, Identifiable {
    case movie
    case book

    var id: String { rawValue }
    var label: String { self == .movie ? L10n.Media.movieActivity : L10n.Media.bookActivity }
    var noun: String { self == .movie ? L10n.Media.movieNoun : L10n.Media.bookNoun }
    var recordTitle: String { self == .movie ? L10n.Media.movieRecord : L10n.Media.bookRecord }
    var icon: String { self == .movie ? "film" : "book.closed" }
    var doneLabel: String { self == .movie ? L10n.Media.movieDone : L10n.Media.bookDone }
    var undoneLabel: String { self == .movie ? L10n.Media.movieUndone : L10n.Media.bookUndone }
    var wishLabel: String { self == .movie ? L10n.Media.movieWish : L10n.Media.bookWish }
}

enum RecordStatus: String, Codable, CaseIterable, Identifiable {
    case done
    case wish

    var id: String { rawValue }
    func label(for media: MediaType) -> String {
        self == .done ? media.doneLabel : media.wishLabel
    }
}

enum DeleteSource: String, Codable, Hashable {
    case user
    case sync

    var label: String { self == .user ? L10n.Media.manualDelete : L10n.Media.syncDelete }
}

enum PosterArt: String, Codable, CaseIterable, Hashable {
    case war
    case stage
    case space
    case road
    case dunes
    case mountains
    case sea
    case bokeh
    case forest
    case city
    case nebula
    case anime
    case volcano
    case bookCream
    case bookViolet
    case bookSand
    case bookIvory
    case bookCharcoal
    case bookSage
    case bookTeal

    var isBook: Bool {
        switch self {
        case .bookCream, .bookViolet, .bookSand, .bookIvory, .bookCharcoal, .bookSage, .bookTeal:
            true
        default:
            false
        }
    }

    var usesDarkTitle: Bool { isBook }
}

enum CoverSource: String, Codable, Hashable {
    case douban
    case builtin
    case link
}

struct MediaRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var mediaType: MediaType
    var status: RecordStatus
    var title: String
    var subjectID: String
    var doubanURL: String?
    var coverURL: String? = nil
    var localCover: Bool? = nil
    var coverSource: CoverSource? = nil
    var art: PosterArt
    var markedDate: Date
    var effectiveDate: Date
    var rating: Int = 0
    var comment: String = ""
    var intro: String = ""
    var durationMinutes: Int?
    var pages: Int?
    var wordCount: Int?
    var year: String?
    var releaseDate: String? = nil
    var isLocalEdited: Bool = false
    var deletedAt: Date?
    var deleteSource: DeleteSource?
    var isHidden: Bool? = nil

    var isDeleted: Bool { deletedAt != nil }
    var isCustomCover: Bool {
        coverSource == .builtin || coverSource == .link || (coverSource == nil && localCover == true)
    }
    var usesBuiltinCover: Bool {
        coverSource == .builtin || (coverSource == nil && localCover == true)
    }
    var linkCoverKey: String { "\(subjectID)-link" }
    var coverRemoteURL: String? { isCustomCover ? nil : coverURL }
    var coverLocalKey: String? {
        if usesBuiltinCover { return nil }
        return coverSource == .link ? linkCoverKey : subjectID
    }
    var coverTag: String? {
        if coverSource == .link { return L10n.Media.linkCover }
        if usesBuiltinCover { return L10n.Media.builtinCover }
        return nil
    }
    var statusLabel: String { status.label(for: mediaType) }
    var displayDate: String { DateFormatter.recordDate.string(from: effectiveDate) }
    var displayMarkedDate: String { DateFormatter.recordDate.string(from: markedDate) }

    var durationText: String? {
        guard let minutes = durationMinutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 {
            return L10n.Stats.hoursMinutes(String(describing: hours), String(describing: rest))
        }
        if hours > 0 { return L10n.Stats.hours(String(describing: hours)) }
        return L10n.Stats.minutes(String(describing: rest))
    }

    var wordsText: String? {
        guard let wordCount, wordCount > 0 else { return nil }
        if wordCount >= 10_000 {
            return L10n.Stats.tenThousandFormat(Double(wordCount) / 10_000)
        }
        return L10n.Stats.words(String(describing: wordCount))
    }

    var statsText: String {
        if mediaType == .movie {
            return durationText ?? L10n.Stats.durationUnset
        }
        var parts: [String] = []
        if let pages, pages > 0 { parts.append(L10n.Stats.pages(String(describing: pages))) }
        if let wordsText { parts.append(wordsText) }
        return parts.isEmpty ? L10n.Stats.pagesWordsUnset : parts.joined(separator: " · ")
    }

    var searchText: String {
        [title, comment, intro].joined(separator: " ").lowercased()
    }

    var ratingText: String {
        rating == 0 ? L10n.Stats.notRated : String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
    }

    var isWish: Bool { status == .wish }
}


struct IgnoredSubject: Codable, Hashable {
    var mediaType: MediaType
    var subjectID: String
    var createdAt: Date
}

struct PurgedRecord: Codable, Hashable {
    var mediaType: MediaType
    var subjectID: String
    var status: RecordStatus
    var title: String
    var purgedAt: Date
}

struct Doulist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var doubanID: String? = nil
    var mediaType: MediaType
    var isFollowing: Bool
    var isPublic: Bool
    var itemCount: Int
    var readCount: Int
    var arts: [PosterArt]
    var updatedAt: Date
    var deletedAt: Date? = nil

    var metaText: String { "\(itemCount) \(mediaType.noun) · \(mediaType.doneLabel) \(readCount) \(mediaType.noun)" }
    var progress: Double { itemCount == 0 ? 0 : Double(readCount) / Double(itemCount) }
}

struct DoulistItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var doulistID: UUID
    var mediaType: MediaType
    var title: String
    var subjectID: String
    var isRead: Bool
    var art: PosterArt
    var durationMinutes: Int?
    var pages: Int?
    var wordCount: Int?
    var year: String?
    var releaseDate: String? = nil
    var coverURL: String? = nil
    var rating: Int? = nil
    var comment: String? = nil
    var intro: String? = nil
    var createdAt: Date? = nil

    var readStatusLabel: String { isRead ? mediaType.doneLabel : mediaType.undoneLabel }

    var statsText: String {
        if mediaType == .movie {
            guard let durationMinutes, durationMinutes > 0 else { return L10n.Stats.durationUnset }
            let hours = durationMinutes / 60
            let minutes = durationMinutes % 60
            if hours > 0 && minutes > 0 {
                return L10n.Stats.hoursMinutes(String(describing: hours), String(describing: minutes))
            }
            if hours > 0 { return L10n.Stats.hours(String(describing: hours)) }
            return L10n.Stats.minutes(String(describing: minutes))
        }
        var parts: [String] = []
        if let pages, pages > 0 { parts.append(L10n.Stats.pages(String(describing: pages))) }
        if let wordCount, wordCount > 0 {
            parts.append(L10n.Stats.tenThousandFormat(Double(wordCount) / 10_000))
        }
        return parts.isEmpty ? L10n.Stats.pagesWordsUnset : parts.joined(separator: " · ")
    }
}

struct PlanFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var mediaType: MediaType
    var note: String
    var arts: [PosterArt]
    var itemCount: Int
    var readCount: Int
    var createdAt: Date
    var deletedAt: Date? = nil

    var progress: Double { itemCount == 0 ? 0 : Double(readCount) / Double(itemCount) }
    var percentText: String { "\(Int((progress * 100).rounded()))%" }
}

struct PlanItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var folderID: UUID
    var mediaType: MediaType
    var title: String
    var subjectID: String
    var isRead: Bool
    var art: PosterArt
    var statsText: String
    var position: Int
    var coverURL: String? = nil
    var releaseDate: String? = nil
    var deletedAt: Date? = nil
    var source: String? = nil
    var sourceID: String? = nil
    var note: String = ""

    var readStatusLabel: String { isRead ? mediaType.doneLabel : mediaType.undoneLabel }
    var toggleReadLabel: String {
        isRead ? L10n.Plan.markUnread(mediaType.undoneLabel) : L10n.Plan.markRead(mediaType.doneLabel)
    }
}

enum ReportScope: String, CaseIterable, Identifiable, Codable, Hashable {
    case month
    case year
    case custom
    case all

    var id: String { rawValue }
    var label: String {
        switch self {
        case .month: L10n.Stats.monthReport
        case .year: L10n.Stats.yearReport
        case .custom: L10n.Stats.customReport
        case .all: L10n.Stats.all
        }
    }
}

struct ReportQuery: Hashable {
    var mediaType: MediaType
    var scope: ReportScope
    var year: Int
    var month: Int
    var startDate: Date
    var endDate: Date
    var darkTheme: Bool = true

    var title: String {
        switch scope {
        case .month: L10n.Report.monthTitle(String(describing: year), String(describing: month), mediaType.label)
        case .year: L10n.Report.yearTitle(String(describing: year), mediaType.label)
        case .custom: L10n.Report.customTitle(mediaType.label)
        case .all: L10n.Report.allTitle(mediaType.label)
        }
    }

    var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        switch scope {
        case .month:
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? Date()
            return start...end.addingTimeInterval(-1)
        case .year:
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? Date()
            return start...end.addingTimeInterval(-1)
        case .custom:
            return startDate...endDate
        case .all:
            return Date.distantPast...Date.distantFuture
        }
    }
}

struct GeneratedReport: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var mediaType: MediaType
    var scope: ReportScope
    var generatedAt: Date
    var count: Int
    var fileName: String
    var hasPNG: Bool
}

extension DateFormatter {
    static let deletedDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 HH:mm"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter
    }()

    static let recordDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let reportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 HH:mm"
        return formatter
    }()
}


enum StatsInputFormat {
    static func wordsHint(_ raw: String) -> String? {
        guard let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        if value >= 10_000 {
            let amount = Double(value) / 10_000
            return amount == amount.rounded()
                ? L10n.Stats.numberTenThousand(String(describing: Int(amount)))
                : L10n.Stats.tenThousandFormat(amount)
        }
        if value >= 1_000 {
            let amount = Double(value) / 1_000
            return amount == amount.rounded()
                ? L10n.Stats.numberTenThousand(String(describing: Int(amount)))
                : L10n.Stats.thousandFormat(String(format: "%.1f", amount))
        }
        return L10n.Stats.words(String(describing: value))
    }

    static func durationHint(_ raw: String) -> String? {
        guard let minutes = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), minutes > 0 else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 {
            return L10n.Stats.hoursMinutesLong(String(describing: hours), String(describing: remainder))
        }
        if hours > 0 { return L10n.Stats.hoursLong(String(describing: hours)) }
        return L10n.Stats.minutesLong(String(describing: minutes))
    }
}
