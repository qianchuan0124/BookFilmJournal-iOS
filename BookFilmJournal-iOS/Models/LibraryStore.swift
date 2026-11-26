import Foundation
import Observation
import SwiftUI

struct LibrarySnapshot: Codable {
    var version: Int = 1
    var records: [MediaRecord]
    var doulists: [Doulist]
    var doulistItems: [DoulistItem]
    var planFolders: [PlanFolder]
    var planItems: [PlanItem]
    var reports: [GeneratedReport]
    var ignoredSubjects: [IgnoredSubject]? = nil
    var purgedRecords: [PurgedRecord]? = nil
}

@Observable
final class LibraryStore {
    var records: [MediaRecord] = []
    var doulists: [Doulist] = []
    var doulistItems: [DoulistItem] = []
    var planFolders: [PlanFolder] = []
    var planItems: [PlanItem] = []
    var reports: [GeneratedReport] = []
    var ignoredSubjects: [IgnoredSubject] = []
    var purgedRecords: [PurgedRecord] = []

    private let storeURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("BookFilmJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("library.json")
        load()
        recoverCoverMetadata()
        deduplicateDoulists()
        normalizeDoulistMediaTypes()
        ensureShadowRecords()
        syncPlanItemStatsFromSources()
    }

    private func recoverCoverMetadata() {
        var changed = false
        for index in records.indices where records[index].coverSource == nil && records[index].localCover == nil {
            let linkKey = CoverStore.linkKey(for: records[index].subjectID)
            guard CoverStore.hasCover(for: linkKey) else { continue }
            records[index].coverSource = .link
            records[index].localCover = true
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Queries

    func activeRecords(media: MediaType? = nil, status: RecordStatus? = nil) -> [MediaRecord] {
        records.filter { record in
            guard !record.isDeleted, record.isHidden != true else { return false }
            if let media, record.mediaType != media { return false }
            if let status, record.status != status { return false }
            return true
        }
    }

    func filteredRecords(media: MediaType, status: RecordStatus, year: Int?, query: String) -> [MediaRecord] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return activeRecords(media: media, status: status)
            .filter { record in
                if let year {
                    let recordYear = Calendar.current.component(.year, from: record.effectiveDate)
                    if recordYear != year { return false }
                }
                if keyword.isEmpty { return true }
                return record.searchText.contains(keyword)
            }
            .sorted { $0.effectiveDate > $1.effectiveDate }
    }

    var activeDoulists: [Doulist] { doulists.filter { $0.deletedAt == nil } }
    var deletedDoulists: [Doulist] { doulists.filter { $0.deletedAt != nil } }
    var activePlanFolders: [PlanFolder] { planFolders.filter { $0.deletedAt == nil } }
    var deletedPlanFolders: [PlanFolder] { planFolders.filter { $0.deletedAt != nil } }
    var deletedPlanItems: [PlanItem] { planItems.filter { $0.deletedAt != nil } }

    func years(media: MediaType) -> [Int] {
        let values = activeRecords(media: media).map {
            Calendar.current.component(.year, from: $0.effectiveDate)
        }
        return Array(Set(values)).sorted(by: >)
    }

    func grouped(_ records: [MediaRecord]) -> [(date: Date, title: String, items: [MediaRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.effectiveDate) }
        return grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? []).sorted { $0.effectiveDate > $1.effectiveDate }
            return (day, Self.dayTitle(day), items)
        }
    }

    func ensureShadowRecords() {
        var existing: [String: Int] = [:]
        for (index, record) in records.enumerated() where !record.isDeleted {
            existing[key(record.mediaType, record.subjectID)] = index
        }
        var changed = false

        func apply(_ media: MediaType, _ subjectID: String, _ title: String, _ isRead: Bool,
                   _ art: PosterArt, _ coverURL: String?, _ duration: Int?, _ pages: Int?,
                   _ words: Int?, _ year: String?, _ release: String?) {
            guard !subjectID.isEmpty else { return }
            if isIgnored(media: media, subjectID: subjectID) { return }
            let shadowStatus: RecordStatus = isRead ? .done : .wish
            if isPurged(media: media, subjectID: subjectID, status: shadowStatus) { return }
            let key = key(media, subjectID)
            if let index = existing[key] {
                guard records[index].isHidden == true else { return }
                var value = records[index]
                if value.coverURL == nil { value.coverURL = coverURL }
                if value.durationMinutes == nil { value.durationMinutes = duration }
                if value.pages == nil { value.pages = pages }
                if value.wordCount == nil { value.wordCount = words }
                if value.year == nil { value.year = year }
                if value.releaseDate == nil { value.releaseDate = release }
                if value.art != art { value.art = art }
                let newStatus: RecordStatus = isRead ? .done : .wish
                if value.status != newStatus { value.status = newStatus }
                records[index] = value
                changed = true
                return
            }
            let record = MediaRecord(
                mediaType: media,
                status: isRead ? .done : .wish,
                title: title,
                subjectID: subjectID,
                doubanURL: "https://\(media == .movie ? "movie" : "book").douban.com/subject/\(subjectID)/",
                coverURL: coverURL,
                art: art,
                markedDate: Date(),
                effectiveDate: Date(),
                durationMinutes: duration,
                pages: pages,
                wordCount: words,
                year: year,
                releaseDate: release,
                isHidden: true
            )
            records.append(record)
            existing[key] = records.count - 1
            changed = true
        }

        let activeListIDs = Set(doulists.filter { $0.deletedAt == nil }.map(\.id))
        let activeFolderIDs = Set(planFolders.filter { $0.deletedAt == nil }.map(\.id))
        for item in doulistItems where activeListIDs.contains(item.doulistID) {
            apply(item.mediaType, item.subjectID, item.title, item.isRead, item.art,
                  item.coverURL, item.durationMinutes, item.pages, item.wordCount,
                  item.year, item.releaseDate)
        }
        for item in planItems where item.deletedAt == nil && activeFolderIDs.contains(item.folderID) {
            apply(item.mediaType, item.subjectID, item.title, item.isRead, item.art,
                  item.coverURL, nil, nil, nil, nil, item.releaseDate)
        }
        if changed { save() }
    }

    private func key(_ media: MediaType, _ subjectID: String) -> String {
        "\(media.rawValue)|\(subjectID)"
    }

    func normalizeDoulistMediaTypes() {
        var changed = false
        for index in doulists.indices {
            let list = doulists[index]
            let items = doulistItems.filter { $0.doulistID == list.id }
            if !items.isEmpty {
                let books = items.filter { $0.mediaType == .book }.count
                let movies = items.count - books
                if books > movies, list.mediaType != .book {
                    doulists[index].mediaType = .book
                    changed = true
                } else if movies > books, list.mediaType != .movie {
                    doulists[index].mediaType = .movie
                    changed = true
                }
            } else if list.mediaType == .movie,
                      ["书", "读", "阅读"].contains(where: { list.title.contains($0) }) {
                doulists[index].mediaType = .book
                changed = true
            }
        }
        if changed { save() }
    }

    func coverRemoteURL(for subjectID: String, media: MediaType? = nil, fallback: String? = nil) -> String? {
        guard let record = records.first(where: {
            !$0.isDeleted && $0.subjectID == subjectID && (media == nil || $0.mediaType == media)
        }) else { return fallback }
        return record.coverRemoteURL
    }

    func coverLocalKey(for subjectID: String, media: MediaType? = nil) -> String? {
        guard let record = records.first(where: {
            !$0.isDeleted && $0.subjectID == subjectID && (media == nil || $0.mediaType == media)
        }) else { return subjectID }
        return record.coverLocalKey
    }

    func coverURL(for subjectID: String, media: MediaType? = nil) -> String? {
        records.first {
            !$0.isDeleted &&
            $0.localCover != true &&
            $0.subjectID == subjectID &&
            (media == nil || $0.mediaType == media) &&
            ($0.coverURL?.isEmpty == false)
        }?.coverURL
    }

    func record(subjectID: String, mediaType: MediaType) -> MediaRecord? {
        records.first { !$0.isDeleted && $0.subjectID == subjectID && $0.mediaType == mediaType }
    }

    func record(id: UUID) -> MediaRecord? {
        records.first { $0.id == id }
    }

    func doulist(id: UUID) -> Doulist? {
        doulists.first { $0.id == id }
    }

    func doulistItems(for doulistID: UUID) -> [DoulistItem] {
        doulistItems.filter { $0.doulistID == doulistID }
    }

    func planFolder(id: UUID) -> PlanFolder? {
        planFolders.first { $0.id == id }
    }

    func planItems(for folderID: UUID) -> [PlanItem] {
        planItems.filter { $0.folderID == folderID && $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    var deletedRecords: [MediaRecord] {
        records.filter(\.isDeleted).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var activeWishRecords: [MediaRecord] {
        activeRecords(status: .wish).sorted { $0.effectiveDate > $1.effectiveDate }
    }

    func doneRecords(media: MediaType) -> [MediaRecord] {
        activeRecords(media: media, status: .done).sorted { $0.effectiveDate > $1.effectiveDate }
    }

    func wordTotal(media: MediaType) -> Int {
        activeRecords(media: media, status: .done).reduce(0) { $0 + ($1.wordCount ?? 0) }
    }

    func wordCountSummary() -> (count: Int, total: Int, all: Int) {
        var keys: [String] = []
        var words: [String: Int] = [:]
        var seen = Set<String>()

        func add(title: String, subjectID: String, wordCount: Int?) {
            let id = subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = id.isEmpty
                ? "title:\(title.lowercased().filter { $0.isLetter || $0.isNumber })"
                : "id:\(id)"
            guard !key.isEmpty else { return }
            if seen.insert(key).inserted { keys.append(key) }
            if let wordCount, wordCount > 0 {
                words[key] = max(words[key] ?? 0, wordCount)
            }
        }

        for record in records where !record.isDeleted && record.mediaType == .book {
            add(title: record.title, subjectID: record.subjectID, wordCount: record.wordCount)
        }
        let activeListIDs = Set(doulists.filter { $0.deletedAt == nil }.map(\.id))
        for item in doulistItems where item.mediaType == .book && activeListIDs.contains(item.doulistID) {
            add(title: item.title, subjectID: item.subjectID, wordCount: item.wordCount)
        }

        let counted = keys.compactMap { words[$0] }
        return (counted.count, counted.reduce(0, +), keys.count)
    }

    func reportRecords(query: ReportQuery) -> [MediaRecord] {
        let range = query.dateRange
        return activeRecords(media: query.mediaType, status: .done)
            .filter { range.contains($0.effectiveDate) }
            .sorted { $0.effectiveDate > $1.effectiveDate }
    }

    // MARK: - Mutations

    func isIgnored(media: MediaType, subjectID: String) -> Bool {
        ignoredSubjects.contains { $0.mediaType == media && $0.subjectID == subjectID }
    }

    func isPurged(media: MediaType, subjectID: String, status: RecordStatus) -> Bool {
        purgedRecords.contains {
            $0.mediaType == media && $0.subjectID == subjectID && $0.status == status
        }
    }

    func ignoreSubject(media: MediaType, subjectID: String, at date: Date = Date()) {
        guard !subjectID.isEmpty, !isIgnored(media: media, subjectID: subjectID) else { return }
        ignoredSubjects.append(IgnoredSubject(mediaType: media, subjectID: subjectID, createdAt: date))
        save()
    }

    func unignoreSubject(media: MediaType, subjectID: String) {
        let count = ignoredSubjects.count
        ignoredSubjects.removeAll { $0.mediaType == media && $0.subjectID == subjectID }
        if ignoredSubjects.count != count { save() }
    }

    func addPurgedRecord(_ value: PurgedRecord) {
        guard !value.subjectID.isEmpty else { return }
        purgedRecords.removeAll {
            $0.mediaType == value.mediaType && $0.subjectID == value.subjectID && $0.status == value.status
        }
        purgedRecords.append(value)
        save()
    }

    func addRecord(_ record: MediaRecord) {
        unignoreSubject(media: record.mediaType, subjectID: record.subjectID)
        let oldCount = purgedRecords.count
        purgedRecords.removeAll {
            $0.mediaType == record.mediaType && $0.subjectID == record.subjectID && $0.status == record.status
        }
        if purgedRecords.count != oldCount { save() }
        records.insert(record, at: 0)
        save()
    }

    func updateRecord(_ record: MediaRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let old = records[index]
        records[index] = record
        if old.subjectID != record.subjectID, !old.subjectID.isEmpty {
            ignoreSubject(media: old.mediaType, subjectID: old.subjectID)
            unignoreSubject(media: record.mediaType, subjectID: record.subjectID)
        }
        refreshPlanItemStats(subjectID: record.subjectID, mediaType: record.mediaType, statsText: record.statsText)
        save()
    }

    func deleteRecord(id: UUID, source: DeleteSource = .user) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].deletedAt = Date()
        records[index].deleteSource = source
        save()
    }

    func restoreRecord(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].deletedAt = nil
        records[index].deleteSource = nil
        save()
    }

    func purgeRecord(id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        addPurgedMarker(for: record)
        records.removeAll { $0.id == id }
        save()
    }

    func purgeAllDeleted() {
        for record in records where record.isDeleted {
            addPurgedMarker(for: record)
        }
        records.removeAll(where: \.isDeleted)
        let deletedListIDs = Set(doulists.filter { $0.deletedAt != nil }.map(\.id))
        doulists.removeAll { $0.deletedAt != nil }
        doulistItems.removeAll { deletedListIDs.contains($0.doulistID) }
        let deletedFolderIDs = Set(planFolders.filter { $0.deletedAt != nil }.map(\.id))
        planFolders.removeAll { $0.deletedAt != nil }
        planItems.removeAll { $0.deletedAt != nil || deletedFolderIDs.contains($0.folderID) }
        save()
    }

    private func addPurgedMarker(for record: MediaRecord) {
        guard !record.subjectID.isEmpty else { return }
        purgedRecords.removeAll {
            $0.mediaType == record.mediaType && $0.subjectID == record.subjectID && $0.status == record.status
        }
        purgedRecords.append(PurgedRecord(
            mediaType: record.mediaType,
            subjectID: record.subjectID,
            status: record.status,
            title: record.title,
            purgedAt: Date()
        ))
    }

    func addPlanItem(_ item: PlanItem) {
        planItems.append(item)
        updatePlanCounts(folderID: item.folderID)
        ensureShadowRecords()
        save()
    }

    private func syncPlanItemStatsFromSources() {
        var changed = false
        for index in planItems.indices where planItems[index].deletedAt == nil {
            let item = planItems[index]
            let doulist = doulistItems.first {
                $0.subjectID == item.subjectID && $0.mediaType == item.mediaType
            }
            let record = records.first {
                !$0.isDeleted && $0.subjectID == item.subjectID && $0.mediaType == item.mediaType
            }
            guard let source = doulist?.statsText ?? record?.statsText else { continue }
            if planItems[index].statsText != source {
                planItems[index].statsText = source
                changed = true
            }
        }
        if changed { save() }
    }

    func refreshPlanItemStats(subjectID: String, mediaType: MediaType, statsText: String? = nil) {
        let value: String
        if let statsText {
            value = statsText
        } else {
            guard let record = records.first(where: {
                !$0.isDeleted && $0.subjectID == subjectID && $0.mediaType == mediaType
            }) else { return }
            value = record.statsText
        }
        var changed = false
        for index in planItems.indices where planItems[index].deletedAt == nil && planItems[index].subjectID == subjectID && planItems[index].mediaType == mediaType {
            if planItems[index].statsText != value {
                planItems[index].statsText = value
                changed = true
            }
        }
        if changed { save() }
    }

    func togglePlanItem(id: UUID) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        planItems[index].isRead.toggle()
        updatePlanCounts(folderID: planItems[index].folderID)
        ensureShadowRecords()
        save()
    }

    func deletePlanItem(id: UUID) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        planItems[index].deletedAt = Date()
        updatePlanCounts(folderID: planItems[index].folderID)
        save()
    }

    func restorePlanItem(id: UUID) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        planItems[index].deletedAt = nil
        updatePlanCounts(folderID: planItems[index].folderID)
        save()
    }

    func purgePlanItem(id: UUID) {
        guard let item = planItems.first(where: { $0.id == id }) else { return }
        planItems.removeAll { $0.id == id }
        updatePlanCounts(folderID: item.folderID)
        save()
    }

    func addPlanFolder(_ folder: PlanFolder) {
        planFolders.insert(folder, at: 0)
        save()
    }

    func updatePlanFolder(_ folder: PlanFolder) {
        guard let index = planFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        var value = folder
        let items = planItems.filter { $0.folderID == folder.id && $0.deletedAt == nil }
        value.itemCount = items.count
        value.readCount = items.filter(\.isRead).count
        planFolders[index] = value
        save()
    }

    func movePlanItem(id: UUID, toPosition: Int) {
        guard let source = planItems.first(where: { $0.id == id }) else { return }
        let folderID = source.folderID
        var list = planItems.filter { $0.folderID == folderID && $0.deletedAt == nil }.sorted { $0.position < $1.position }
        guard let from = list.firstIndex(where: { $0.id == id }) else { return }
        let item = list.remove(at: from)
        let target = min(max(0, toPosition), list.count)
        guard target != from else {
            list.insert(item, at: from)
            return
        }
        list.insert(item, at: target)
        for (index, value) in list.enumerated() {
            if let storeIndex = planItems.firstIndex(where: { $0.id == value.id }) {
                planItems[storeIndex].position = index
            }
        }
        save()
    }

    func movePlanItems(folderID: UUID, from source: IndexSet, to destination: Int) {
        var list = planItems.filter { $0.folderID == folderID && $0.deletedAt == nil }.sorted { $0.position < $1.position }
        list.move(fromOffsets: source, toOffset: destination)
        for (index, value) in list.enumerated() {
            if let storeIndex = planItems.firstIndex(where: { $0.id == value.id }) {
                planItems[storeIndex].position = index
            }
        }
        save()
    }

    func deletePlanFolder(id: UUID) {
        guard let index = planFolders.firstIndex(where: { $0.id == id }) else { return }
        planFolders[index].deletedAt = Date()
        save()
    }

    func restorePlanFolder(id: UUID) {
        guard let index = planFolders.firstIndex(where: { $0.id == id }) else { return }
        planFolders[index].deletedAt = nil
        save()
    }

    func purgePlanFolder(id: UUID) {
        planFolders.removeAll { $0.id == id }
        planItems.removeAll { $0.folderID == id }
        save()
    }

    func addReport(_ report: GeneratedReport) {
        reports.insert(report, at: 0)
        save()
    }

    private func updatePlanCounts(folderID: UUID) {
        guard let index = planFolders.firstIndex(where: { $0.id == folderID }) else { return }
        let items = planItems.filter { $0.folderID == folderID && $0.deletedAt == nil }
        planFolders[index].itemCount = items.count
        planFolders[index].readCount = items.filter(\.isRead).count
    }

    func deduplicateDoulists() {
        guard doulists.count > 1 else { return }
        var kept: [Doulist] = []
        var alias: [UUID: UUID] = [:]

        func normalizedTitle(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
        }

        for list in doulists {
            let existingIndex = kept.firstIndex { candidate in
                guard (candidate.deletedAt == nil) == (list.deletedAt == nil) else { return false }
                if let left = candidate.doubanID, !left.isEmpty,
                   let right = list.doubanID, !right.isEmpty {
                    return left == right
                }
                guard normalizedTitle(candidate.title) == normalizedTitle(list.title),
                      candidate.mediaType == list.mediaType else { return false }
                return true
            }

            guard let existingIndex else {
                kept.append(list)
                continue
            }

            var canonical = kept[existingIndex]
            if canonical.doubanID?.isEmpty != false,
               let remoteID = list.doubanID, !remoteID.isEmpty {
                canonical.doubanID = remoteID
                canonical.title = list.title
            }
            canonical.isFollowing = canonical.isFollowing && list.isFollowing
            canonical.isPublic = canonical.isPublic || list.isPublic
            canonical.updatedAt = max(canonical.updatedAt, list.updatedAt)
            kept[existingIndex] = canonical
            alias[list.id] = canonical.id
        }

        guard !alias.isEmpty else { return }
        for index in doulistItems.indices {
            if let canonical = alias[doulistItems[index].doulistID] {
                doulistItems[index].doulistID = canonical
            }
        }

        var mergedItems: [DoulistItem] = []
        var indexByKey: [String: Int] = [:]
        for item in doulistItems {
            let key = "\(item.doulistID.uuidString)|\(item.mediaType.rawValue)|\(item.subjectID)"
            if let index = indexByKey[key] {
                var existing = mergedItems[index]
                existing.isRead = existing.isRead || item.isRead
                existing.durationMinutes = existing.durationMinutes ?? item.durationMinutes
                existing.pages = existing.pages ?? item.pages
                existing.wordCount = existing.wordCount ?? item.wordCount
                existing.year = existing.year ?? item.year
                existing.releaseDate = existing.releaseDate ?? item.releaseDate
                existing.coverURL = existing.coverURL ?? item.coverURL
                mergedItems[index] = existing
            } else {
                indexByKey[key] = mergedItems.count
                mergedItems.append(item)
            }
        }

        doulists = kept
        doulistItems = mergedItems
        for index in doulists.indices {
            let items = doulistItems.filter { $0.doulistID == doulists[index].id }
            doulists[index].itemCount = items.count
            doulists[index].readCount = items.filter(\.isRead).count
            doulists[index].arts = Array(items.prefix(4).map(\.art))
        }
        save()
    }

    func refreshDoulistStats() {
        for index in doulists.indices {
            let items = doulistItems.filter { $0.doulistID == doulists[index].id }
            doulists[index].itemCount = items.count
            doulists[index].readCount = items.filter(\.isRead).count
            doulists[index].arts = Array(items.prefix(4).map(\.art))
        }
        normalizeDoulistMediaTypes()
        ensureShadowRecords()
        save()
    }

    func updateDoulist(_ doulist: Doulist) {
        guard let index = doulists.firstIndex(where: { $0.id == doulist.id }) else { return }
        var value = doulist
        let items = doulistItems.filter { $0.doulistID == doulist.id }
        value.itemCount = items.count
        value.readCount = items.filter(\.isRead).count
        doulists[index] = value
        save()
    }

    func deleteDoulist(id: UUID) {
        guard let index = doulists.firstIndex(where: { $0.id == id }) else { return }
        doulists[index].deletedAt = Date()
        save()
    }

    func restoreDoulist(id: UUID) {
        guard let index = doulists.firstIndex(where: { $0.id == id }) else { return }
        doulists[index].deletedAt = nil
        save()
    }

    func purgeDoulist(id: UUID) {
        doulists.removeAll { $0.id == id }
        doulistItems.removeAll { $0.doulistID == id }
        save()
    }

    func reorderDoulists(_ ids: [UUID]) {
        let ordered = ids.compactMap { id in doulists.first(where: { $0.id == id }) }
        let selected = Set(ordered.map(\.id))
        guard selected.count > 1 else { return }
        var iterator = ordered.makeIterator()
        doulists = doulists.map { selected.contains($0.id) ? (iterator.next() ?? $0) : $0 }
        save()
    }

    func reorderDoulistItems(_ ids: [UUID]) {
        let ordered = ids.compactMap { id in doulistItems.first(where: { $0.id == id }) }
        let selected = Set(ordered.map(\.id))
        guard selected.count > 1 else { return }
        var iterator = ordered.makeIterator()
        doulistItems = doulistItems.map { selected.contains($0.id) ? (iterator.next() ?? $0) : $0 }
        save()
    }

    func moveDoulist(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = doulists.firstIndex(where: { $0.id == id }) else { return }
        let value = doulists.remove(at: from)
        if let to = doulists.firstIndex(where: { $0.id == targetID }) {
            doulists.insert(value, at: to)
        } else {
            doulists.append(value)
        }
        save()
    }

    func moveDoulistItem(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = doulistItems.firstIndex(where: { $0.id == id }) else { return }
        let value = doulistItems.remove(at: from)
        if let to = doulistItems.firstIndex(where: { $0.id == targetID }) {
            doulistItems.insert(value, at: to)
        } else {
            doulistItems.append(value)
        }
        save()
    }

    func updateDoulistItem(_ item: DoulistItem) {
        guard let index = doulistItems.firstIndex(where: { $0.id == item.id }) else { return }
        doulistItems[index] = item
        ensureShadowRecords()
        refreshPlanItemStats(subjectID: item.subjectID, mediaType: item.mediaType, statsText: item.statsText)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        guard let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              snapshot.version == 1 else {
            preserveUnreadableLibrary(data)
            return
        }
        records = snapshot.records
        doulists = snapshot.doulists
        doulistItems = snapshot.doulistItems
        planFolders = snapshot.planFolders
        planItems = snapshot.planItems
        reports = snapshot.reports
        ignoredSubjects = snapshot.ignoredSubjects ?? []
        purgedRecords = snapshot.purgedRecords ?? []
    }

    private func preserveUnreadableLibrary(_ data: Data) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backup = storeURL.deletingLastPathComponent()
            .appendingPathComponent("library-unreadable-\(formatter.string(from: Date())).json")
        try? data.write(to: backup, options: .atomic)
    }

    var currentSnapshot: LibrarySnapshot {
        LibrarySnapshot(
            records: records,
            doulists: doulists,
            doulistItems: doulistItems,
            planFolders: planFolders,
            planItems: planItems,
            reports: reports,
            ignoredSubjects: ignoredSubjects,
            purgedRecords: purgedRecords
        )
    }

    func clearAllData() {
        records = []
        doulists = []
        doulistItems = []
        planFolders = []
        planItems = []
        reports = []
        ignoredSubjects = []
        purgedRecords = []
        save()
        CoverStore.removeAllCovers()
    }

    func replace(with snapshot: LibrarySnapshot) {
        records = snapshot.records
        doulists = snapshot.doulists
        doulistItems = snapshot.doulistItems
        planFolders = snapshot.planFolders
        planItems = snapshot.planItems
        if let ignored = snapshot.ignoredSubjects {
            ignoredSubjects = ignored
        }
        if let purged = snapshot.purgedRecords {
            purgedRecords = purged
        }
        if !snapshot.reports.isEmpty {
            reports = snapshot.reports
        }
        deduplicateDoulists()
        save()
        ensureShadowRecords()
        syncPlanItemStatsFromSources()
    }

    func save() {
        let snapshot = LibrarySnapshot(
            records: records,
            doulists: doulists,
            doulistItems: doulistItems,
            planFolders: planFolders,
            planItems: planItems,
            reports: reports,
            ignoredSubjects: ignoredSubjects,
            purgedRecords: purgedRecords
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    static func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return formatter.string(from: date) + " · " + weekdays[max(0, min(6, weekday))]
    }
}
