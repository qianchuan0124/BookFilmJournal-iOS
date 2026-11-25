import Foundation
import CryptoKit

struct ExcelImportResult {
    var insertedRecords = 0
    var updatedRecords = 0
    var doulists = 0
    var doulistItems = 0
    var planFolders = 0
    var planItems = 0
    var bookWords = 0
    var failures: [String] = []

    var summary: String {
        L10n.Data.importDone(String(describing: insertedRecords), String(describing: updatedRecords))
    }

    var detail: String {
        [
            "\(L10n.Tab.doulist) \(doulists)",
            "条目 \(doulistItems)",
            "\(L10n.Tab.plan) \(planFolders)/\(planItems)",
            "\(L10n.Data.words) \(bookWords)"
        ].joined(separator: " · ")
    }
}

enum ExcelImportService {
    @MainActor
    static func importWorkbook(_ data: Data, into store: LibraryStore) -> ExcelImportResult {
        var result = ExcelImportResult()
        let sheets: [String: [[String]]]
        do {
            sheets = try XLSXReader.sheets(from: data)
        } catch {
            result.failures = [error.localizedDescription]
            return result
        }

        importSuppression(from: sheets, into: store)

        if let table = ImportTable(rows: sheets["观影记录"] ?? [], required: ["标题"]) {
            importRecords(table, media: .movie, into: store, result: &result)
        }
        if let table = ImportTable(rows: sheets["读书记录"] ?? [], required: ["标题"]) {
            importRecords(table, media: .book, into: store, result: &result)
        }

        var doulistIDs: [String: UUID] = [:]
        if let table = ImportTable(rows: sheets["豆列"] ?? [], required: ["标题"]) {
            importDoulists(table, into: store, result: &result, ids: &doulistIDs)
        }
        if let table = ImportTable(rows: sheets["豆列条目"] ?? [], required: ["标题"]) {
            importDoulistItems(table, into: store, result: &result, ids: doulistIDs)
        }

        var folderIDs: [String: UUID] = [:]
        if let table = ImportTable(rows: sheets["计划文件夹"] ?? [], required: ["计划名称"]) {
            importPlanFolders(table, into: store, result: &result, ids: &folderIDs)
        }
        if let table = ImportTable(rows: sheets["计划"] ?? [], required: ["计划名称", "标题"]) {
            importPlanItems(table, into: store, result: &result, ids: folderIDs)
        }

        if let table = ImportTable(rows: sheets["回收站记录"] ?? [], required: ["标题"]) {
            importDeletedRecords(table, into: store, result: &result)
        }
        if let table = ImportTable(rows: sheets["回收站豆列"] ?? [], required: ["标题"]) {
            importDoulists(table, into: store, result: &result, ids: &doulistIDs, deleted: true)
        }
        if let table = ImportTable(rows: sheets["回收站豆列条目"] ?? [], required: ["标题"]) {
            importDoulistItems(table, into: store, result: &result, ids: doulistIDs)
        }
        if let table = ImportTable(rows: sheets["回收站计划文件夹"] ?? [], required: ["计划名称"]) {
            importPlanFolders(table, into: store, result: &result, ids: &folderIDs, deleted: true)
        }
        if let table = ImportTable(rows: sheets["回收站计划条目"] ?? [], required: ["计划名称", "标题"]) {
            importPlanItems(table, into: store, result: &result, ids: folderIDs, deleted: true)
        }

        if let table = ImportTable(rows: sheets["书籍字数"] ?? [], required: ["豆瓣ID"]) {
            importBookWords(table, into: store, result: &result)
        }

        store.deduplicateDoulists()
        rebuildDoulistCounts(store)
        rebuildPlanCounts(store)
        store.save()
        return result
    }

    private static func importSuppression(from sheets: [String: [[String]]], into store: LibraryStore) {
        if let table = ImportTable(rows: sheets["忽略条目"] ?? [], required: ["豆瓣ID"]) {
            for row in table.rows {
                let subjectID = table.value(row, ["豆瓣ID"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !subjectID.isEmpty else { continue }
                let media = parseMedia(table.value(row, ["类型"]))
                store.ignoreSubject(
                    media: media,
                    subjectID: subjectID,
                    at: parseDate(table.value(row, ["记录时间"])) ?? Date()
                )
            }
        }
        if let table = ImportTable(rows: sheets["彻底删除记录"] ?? [], required: ["豆瓣ID"]) {
            for row in table.rows {
                let subjectID = table.value(row, ["豆瓣ID"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !subjectID.isEmpty else { continue }
                store.addPurgedRecord(PurgedRecord(
                    mediaType: parseMedia(table.value(row, ["类型"])),
                    subjectID: subjectID,
                    status: parseStatus(table.value(row, ["状态"])),
                    title: table.value(row, ["标题"]),
                    purgedAt: parseDate(table.value(row, ["彻底删除时间"])) ?? Date()
                ))
            }
        }
    }

    private static func importRecords(
        _ table: ImportTable,
        media: MediaType,
        into store: LibraryStore,
        result: inout ExcelImportResult
    ) {
        var indexByKey: [String: Int] = [:]
        for (index, record) in store.records.enumerated() {
            indexByKey[recordKey(record)] = index
        }

        for (offset, row) in table.rows.enumerated() {
            let line = offset + 2
            let title = table.value(row, ["标题"])
            guard !title.isEmpty else {
                result.failures.append(L10n.Data.rowMissingTitle(String(describing: line)))
                continue
            }
            let status = parseStatus(table.value(row, ["状态"]))
            let url = table.value(row, ["链接"])
            let subjectID = table.value(row, ["豆瓣ID", "条目ID"]).ifEmpty(
                derivedSubjectID(media: media, status: status, title: title, url: url)
            )
            let marked = parseDate(table.value(row, ["标记日期", "豆瓣标记日期"])) ?? Date()
            let effective = parseDate(table.value(row, ["生效日期", "本地生效日期"])) ?? marked
            let edited = table.value(row, ["来源"]).lowercased() == "local"
                || isTrue(table.value(row, ["本地已调整"]))
            if store.isIgnored(media: media, subjectID: subjectID) { continue }
            if store.isPurged(media: media, subjectID: subjectID, status: status) { continue }
            let existingIndex = indexByKey[recordKey(media, subjectID, status)]
            let existing = existingIndex.map { store.records[$0] }

            var record = MediaRecord(
                mediaType: media,
                status: status,
                title: title,
                subjectID: subjectID,
                doubanURL: url.isEmpty ? nil : url,
                art: existing?.art ?? placeholderArt(media: media, subjectID: subjectID, title: title),
                markedDate: marked,
                effectiveDate: effective,
                rating: min(5, max(0, int(table.value(row, ["评分"])) ?? 0)),
                comment: table.value(row, ["短评"]),
                intro: table.value(row, ["简介"]),
                durationMinutes: int(table.value(row, ["时长"])),
                pages: int(table.value(row, ["页数"])),
                wordCount: int(table.value(row, ["字数"])),
                year: table.value(row, ["年份"]).nilIfEmpty,
                releaseDate: table.value(row, ["上映日期"]).nilIfEmpty,
                isLocalEdited: edited
            )
            if let existing {
                record.id = existing.id
                record.isHidden = existing.isHidden
                record.coverURL = existing.coverURL
                record.localCover = existing.localCover
                record.coverSource = existing.coverSource
                store.records[existingIndex!] = record
                result.updatedRecords += 1
            } else {
                store.records.append(record)
                indexByKey[recordKey(record)] = store.records.count - 1
                result.insertedRecords += 1
            }
        }
    }

    private static func importDeletedRecords(
        _ table: ImportTable,
        into store: LibraryStore,
        result: inout ExcelImportResult
    ) {
        for row in table.rows {
            let title = table.value(row, ["标题"])
            guard !title.isEmpty else { continue }
            let media = parseMedia(table.value(row, ["类型"]))
            let status = parseStatus(table.value(row, ["状态"]))
            let url = table.value(row, ["链接"])
            let subjectID = table.value(row, ["豆瓣ID", "条目ID"]).ifEmpty(
                derivedSubjectID(media: media, status: status, title: title, url: url)
            )
            if store.isPurged(media: media, subjectID: subjectID, status: status) { continue }
            let key = recordKey(media, subjectID, status)
            let existingIndex = store.records.firstIndex { recordKey($0) == key }
            let marked = parseDate(table.value(row, ["豆瓣标记日期", "标记日期"])) ?? Date()
            let effective = parseDate(table.value(row, ["本地生效日期", "生效日期"])) ?? marked
            let deletedAt = parseDate(table.value(row, ["删除时间"])) ?? Date()
            var record = MediaRecord(
                mediaType: media,
                status: status,
                title: title,
                subjectID: subjectID,
                doubanURL: url.isEmpty ? nil : url,
                art: existingIndex.map { store.records[$0].art } ?? placeholderArt(media: media, subjectID: subjectID, title: title),
                markedDate: marked,
                effectiveDate: effective,
                rating: min(5, max(0, int(table.value(row, ["评分"])) ?? 0)),
                comment: table.value(row, ["短评"]),
                intro: table.value(row, ["简介"]),
                durationMinutes: int(table.value(row, ["时长"])),
                pages: int(table.value(row, ["页数"])),
                wordCount: int(table.value(row, ["字数"])),
                year: table.value(row, ["年份"]).nilIfEmpty,
                releaseDate: table.value(row, ["上映日期"]).nilIfEmpty,
                isLocalEdited: table.value(row, ["来源"]).lowercased() == "local"
                    || isTrue(table.value(row, ["本地已调整"])),
                deletedAt: deletedAt,
                deleteSource: table.value(row, ["删除来源"]).contains("同步") ? .sync : .user
            )
            if let existingIndex {
                let old = store.records[existingIndex]
                record.id = old.id
                record.coverURL = table.value(row, ["封面URL"]).nilIfEmpty ?? old.coverURL
                record.localCover = old.localCover
                record.coverSource = old.coverSource
                store.records[existingIndex] = record
                result.updatedRecords += 1
            } else {
                record.coverURL = table.value(row, ["封面URL"]).nilIfEmpty
                store.records.append(record)
                result.insertedRecords += 1
            }
        }
    }

    private struct ParsedDoulistIdentifier {
        let id: UUID?
        let doubanID: String?
    }

    private static func parseDoulistIdentifier(_ raw: String) -> ParsedDoulistIdentifier {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return ParsedDoulistIdentifier(id: nil, doubanID: nil) }
        if value.hasPrefix("ios-local-"),
           let id = UUID(uuidString: String(value.dropFirst("ios-local-".count))) {
            return ParsedDoulistIdentifier(id: id, doubanID: nil)
        }
        if let id = UUID(uuidString: value) {
            return ParsedDoulistIdentifier(id: id, doubanID: nil)
        }
        return ParsedDoulistIdentifier(
            id: DoubanSyncService.stableID(forDoubanDoulistID: value),
            doubanID: value
        )
    }

    private static func importDoulists(
        _ table: ImportTable,
        into store: LibraryStore,
        result: inout ExcelImportResult,
        ids: inout [String: UUID],
        deleted: Bool = false
    ) {
        for row in table.rows {
            let title = table.value(row, ["标题"])
            guard !title.isEmpty else { continue }
            let media = parseMedia(table.value(row, ["类型"]))
            let rawID = table.value(row, ["豆列ID"])
            let parsed = parseDoulistIdentifier(rawID)
            let existing = store.doulists.first {
                (parsed.id != nil && $0.id == parsed.id)
                    || (parsed.doubanID != nil && $0.doubanID == parsed.doubanID)
                    || ($0.title == title && $0.mediaType == media)
            }
            let deletedAt = deleted ? (parseDate(table.value(row, ["删除时间"])) ?? Date()) : nil
            if var value = existing {
                value.title = title
                value.mediaType = media
                value.doubanID = parsed.doubanID ?? value.doubanID
                value.isFollowing = table.value(row, ["关系"]) == "followed"
                value.itemCount = int(table.value(row, ["条目数"])) ?? value.itemCount
                value.updatedAt = parseDate(table.value(row, ["同步时间"])) ?? value.updatedAt
                value.deletedAt = deletedAt
                if let index = store.doulists.firstIndex(where: { $0.id == value.id }) {
                    store.doulists[index] = value
                }
                ids[rawID] = value.id
                ids["\(media.rawValue)|\(title)"] = value.id
                result.doulists += 1
            } else {
                let value = Doulist(
                    id: parsed.id ?? UUID(),
                    title: title,
                    doubanID: parsed.doubanID,
                    mediaType: media,
                    isFollowing: table.value(row, ["关系"]) == "followed",
                    isPublic: true,
                    itemCount: int(table.value(row, ["条目数"])) ?? 0,
                    readCount: 0,
                    arts: [],
                    updatedAt: parseDate(table.value(row, ["同步时间"])) ?? Date(),
                    deletedAt: deletedAt
                )
                store.doulists.append(value)
                ids[rawID] = value.id
                ids["\(media.rawValue)|\(title)"] = value.id
                result.doulists += 1
            }
        }
    }

    private static func importDoulistItems(
        _ table: ImportTable,
        into store: LibraryStore,
        result: inout ExcelImportResult,
        ids: [String: UUID]
    ) {
        for row in table.rows {
            let title = table.value(row, ["标题"])
            guard !title.isEmpty else { continue }
            let media = parseMedia(table.value(row, ["类型"]))
            let exportListID = table.value(row, ["豆列ID"])
            let doulistID = ids[exportListID]
                ?? UUID(uuidString: exportListID)
                ?? store.doulists.first {
                    $0.doubanID == exportListID || "ios-local-\($0.id.uuidString)" == exportListID
                }?.id
            guard let doulistID else { continue }
            let subjectID = table.value(row, ["条目ID", "豆瓣ID"]).ifEmpty(
                derivedSubjectID(media: media, status: .wish, title: title, url: table.value(row, ["链接"]))
            )
            let existing = store.doulistItems.first {
                $0.doulistID == doulistID && $0.mediaType == media && $0.subjectID == subjectID
            }
            var value = DoulistItem(
                id: existing?.id ?? UUID(),
                doulistID: doulistID,
                mediaType: media,
                title: title,
                subjectID: subjectID,
                isRead: parseRead(table.value(row, ["状态"])),
                art: existing?.art ?? placeholderArt(media: media, subjectID: subjectID, title: title),
                durationMinutes: int(table.value(row, ["时长"])) ?? existing?.durationMinutes,
                pages: int(table.value(row, ["页数"])) ?? existing?.pages,
                wordCount: int(table.value(row, ["字数"])) ?? existing?.wordCount,
                year: table.value(row, ["年份"]).nilIfEmpty ?? existing?.year,
                releaseDate: table.value(row, ["上映日期"]).nilIfEmpty ?? existing?.releaseDate,
                coverURL: table.value(row, ["封面URL"]).nilIfEmpty ?? existing?.coverURL,
                rating: int(table.value(row, ["评分"])) ?? existing?.rating,
                comment: table.value(row, ["短评"]).nilIfEmpty ?? existing?.comment,
                intro: table.value(row, ["简介"]).nilIfEmpty ?? existing?.intro,
                createdAt: parseDate(table.value(row, ["创建时间"])) ?? existing?.createdAt
            )
            if let existing, let index = store.doulistItems.firstIndex(where: { $0.id == existing.id }) {
                value.id = existing.id
                store.doulistItems[index] = value
            } else {
                store.doulistItems.append(value)
            }
            result.doulistItems += 1
        }
    }

    private static func importPlanFolders(
        _ table: ImportTable,
        into store: LibraryStore,
        result: inout ExcelImportResult,
        ids: inout [String: UUID],
        deleted: Bool = false
    ) {
        for row in table.rows {
            let title = table.value(row, ["计划名称"])
            guard !title.isEmpty else { continue }
            let media = parseMedia(table.value(row, ["类型"]))
            let deletedAt = deleted ? (parseDate(table.value(row, ["删除时间"])) ?? Date()) : nil
            if var existing = store.planFolders.first(where: { $0.title == title && $0.mediaType == media }) {
                existing.note = table.value(row, ["备注"])
                existing.deletedAt = deletedAt
                if let index = store.planFolders.firstIndex(where: { $0.id == existing.id }) {
                    store.planFolders[index] = existing
                }
                ids["\(media.rawValue)|\(title)"] = existing.id
                result.planFolders += 1
            } else {
                let value = PlanFolder(
                    title: title,
                    mediaType: media,
                    note: table.value(row, ["备注"]),
                    arts: [],
                    itemCount: 0,
                    readCount: 0,
                    createdAt: Date(),
                    deletedAt: deletedAt
                )
                store.planFolders.append(value)
                ids["\(media.rawValue)|\(title)"] = value.id
                result.planFolders += 1
            }
        }
    }

    private static func importPlanItems(
        _ table: ImportTable,
        into store: LibraryStore,
        result: inout ExcelImportResult,
        ids: [String: UUID],
        deleted: Bool = false
    ) {
        for (offset, row) in table.rows.enumerated() {
            let title = table.value(row, ["标题"])
            let folderTitle = table.value(row, ["计划名称"])
            let media = parseMedia(table.value(row, ["类型"]))
            guard !title.isEmpty, let folderID = ids["\(media.rawValue)|\(folderTitle)"] ?? ids[folderTitle] else { continue }
            let subjectID = table.value(row, ["条目ID", "豆瓣ID"]).ifEmpty(
                derivedSubjectID(media: media, status: .wish, title: title, url: table.value(row, ["链接"]))
            )
            let existing = store.planItems.first { $0.folderID == folderID && $0.mediaType == media && $0.subjectID == subjectID }
            let record = store.records.first { $0.mediaType == media && $0.subjectID == subjectID && !$0.isDeleted }
            let value = PlanItem(
                id: existing?.id ?? UUID(),
                folderID: folderID,
                mediaType: media,
                title: title,
                subjectID: subjectID,
                isRead: parseRead(table.value(row, ["状态"])),
                art: existing?.art ?? placeholderArt(media: media, subjectID: subjectID, title: title),
                statsText: record?.statsText ?? existing?.statsText ?? "",
                position: int(table.value(row, ["顺序"])) ?? offset,
                coverURL: table.value(row, ["封面URL"]).nilIfEmpty ?? existing?.coverURL,
                releaseDate: table.value(row, ["上映日期"]).nilIfEmpty ?? record?.releaseDate ?? existing?.releaseDate,
                deletedAt: deleted ? parseDate(table.value(row, ["删除时间"])) : nil,
                source: table.value(row, ["来源"]).nilIfEmpty ?? existing?.source,
                sourceID: table.value(row, ["来源ID"]).nilIfEmpty ?? existing?.sourceID,
                note: table.value(row, ["备注"]).nilIfEmpty ?? existing?.note ?? ""
            )
            if let existing, let index = store.planItems.firstIndex(where: { $0.id == existing.id }) {
                store.planItems[index] = value
            } else {
                store.planItems.append(value)
            }
            result.planItems += 1
        }
    }

    private static func importBookWords(_ table: ImportTable, into store: LibraryStore, result: inout ExcelImportResult) {
        for row in table.rows {
            let subjectID = table.value(row, ["豆瓣ID", "条目ID"])
            guard !subjectID.isEmpty else { continue }
            if let words = int(table.value(row, ["字数"])) {
                for index in store.records.indices where store.records[index].subjectID == subjectID && store.records[index].mediaType == .book {
                    store.records[index].wordCount = words
                }
                for index in store.doulistItems.indices where store.doulistItems[index].subjectID == subjectID && store.doulistItems[index].mediaType == .book {
                    store.doulistItems[index].wordCount = words
                }
                result.bookWords += 1
            }
        }
    }

    private static func rebuildDoulistCounts(_ store: LibraryStore) {
        for index in store.doulists.indices {
            let items = store.doulistItems.filter { $0.doulistID == store.doulists[index].id }
            store.doulists[index].itemCount = items.count
            store.doulists[index].readCount = items.filter(\.isRead).count
            store.doulists[index].arts = Array(items.prefix(4).map(\.art))
        }
    }

    private static func rebuildPlanCounts(_ store: LibraryStore) {
        for index in store.planFolders.indices {
            let folder = store.planFolders[index]
            let items = store.planItems.filter {
                $0.folderID == folder.id && ($0.deletedAt == nil || folder.deletedAt != nil)
            }
            store.planFolders[index].itemCount = items.count
            store.planFolders[index].readCount = items.filter(\.isRead).count
        }
    }

    private static func recordKey(_ record: MediaRecord) -> String {
        recordKey(record.mediaType, record.subjectID, record.status)
    }

    private static func recordKey(_ media: MediaType, _ subjectID: String, _ status: RecordStatus) -> String {
        "\(media.rawValue)|\(subjectID)|\(status.rawValue)"
    }

    private static func parseMedia(_ value: String) -> MediaType {
        let text = value.lowercased()
        if text.contains("book") || text.contains("书") || text.contains("读") { return .book }
        return .movie
    }

    private static func parseStatus(_ value: String) -> RecordStatus {
        let text = value.lowercased()
        if text.contains("想") || text.contains("wish") { return .wish }
        return .done
    }

    private static func parseRead(_ value: String) -> Bool {
        let text = value.lowercased()
        guard !text.isEmpty else { return false }
        return !text.contains("未") && !text.contains("wish") && !text.contains("false") && !text.contains("0")
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatters = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/M/d", "yyyy/MM/dd"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func int(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isTrue(_ value: String) -> Bool {
        ["是", "true", "1", "yes", "local"].contains(value.lowercased())
    }

    private static func derivedSubjectID(media: MediaType, status: RecordStatus, title: String, url: String) -> String {
        if let range = url.range(of: #"/subject/(\d+)"#, options: .regularExpression) {
            return String(url[range].split(separator: "/").last ?? "")
        }
        let seed = "\(media.rawValue)|\(status.rawValue)|\(title)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return "local-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func placeholderArt(media: MediaType, subjectID: String, title: String) -> PosterArt {
        let seed = subjectID.isEmpty ? title : subjectID
        let hash = seed.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value }
        let options: [PosterArt] = media == .movie
            ? [.war, .space, .road, .dunes, .mountains, .sea, .bokeh, .forest, .city, .nebula, .anime, .volcano, .stage]
            : [.bookCream, .bookViolet, .bookSand, .bookIvory, .bookCharcoal, .bookSage, .bookTeal]
        return options[Int(hash % UInt32(options.count))]
    }
}

private struct ImportTable {
    let header: [String]
    let rows: [[String]]

    init?(rows: [[String]], required: [String]) {
        guard let first = rows.first else { return nil }
        let header = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard required.allSatisfy({ header.contains($0) }) else { return nil }
        self.header = header
        self.rows = rows.dropFirst().filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    func value(_ row: [String], _ keys: [String]) -> String {
        for key in keys {
            guard let index = header.firstIndex(of: key), row.indices.contains(index) else { continue }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return ""
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
