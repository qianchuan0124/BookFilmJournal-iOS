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
        if let data = try? Data(contentsOf: storeURL),
           let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
           snapshot.version == 1 {
            records = snapshot.records
            doulists = snapshot.doulists
            doulistItems = snapshot.doulistItems
            planFolders = snapshot.planFolders
            planItems = snapshot.planItems
            reports = snapshot.reports
            ignoredSubjects = snapshot.ignoredSubjects ?? []
            purgedRecords = snapshot.purgedRecords ?? []
            if records.isEmpty {
                seed()
            }
        } else {
            seed()
        }
    }

    private func seed() {
        let snapshot = SampleData.snapshot()
        records = snapshot.records
        doulists = snapshot.doulists
        doulistItems = snapshot.doulistItems
        planFolders = snapshot.planFolders
        planItems = snapshot.planItems
        reports = snapshot.reports
        save()
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

enum SampleData {
    static func snapshot() -> LibrarySnapshot {
        let records = makeRecords()
        let doulists = makeDoulists()
        let doulistItems = makeDoulistItems(for: doulists)
        let planFolders = makePlanFolders()
        let planItems = makePlanItems(for: planFolders)
        let reports = makeReports()
        return LibrarySnapshot(
            records: records,
            doulists: doulists,
            doulistItems: doulistItems,
            planFolders: planFolders,
            planItems: planItems,
            reports: reports
        )
    }

    private static func makeRecords() -> [MediaRecord] {
        [
            MediaRecord(mediaType: .movie, status: .done, title: "大决战之辽沈战役", subjectID: "1298661", doubanURL: "https://movie.douban.com/subject/1298661/", art: .war, markedDate: .sample(2026, 10, 25), effectiveDate: .sample(2026, 10, 25), rating: 5, comment: "拍得真稳。辽沈战役从锦州攻坚到黑山阻击，几条线并行推进而不乱，宏观调度与战壕里的具体恐惧都照顾到了。\n\n最喜欢的是攻打配水池那一段：没有喊口号，只有雪、泥、冻僵的手和一张张年轻的脸。战争片最难的是让人记住「代价」，这部做到了。结尾的胜利没有配乐狂欢，反而安静得让人心里发沉。\n\n五星，是给这份克制。", durationMinutes: 209, year: "1991"),
            MediaRecord(mediaType: .movie, status: .done, title: "流浪地球 2", subjectID: "35267208", doubanURL: "https://movie.douban.com/subject/35267208/", art: .space, markedDate: .sample(2026, 10, 25), effectiveDate: .sample(2026, 10, 25), rating: 4, comment: "太空电梯那一段真是把想象力和工业能力一起摆到了银幕上。", durationMinutes: 173, year: "2023"),
            MediaRecord(mediaType: .movie, status: .done, title: "路边野餐", subjectID: "26337832", doubanURL: "https://movie.douban.com/subject/26337832/", art: .mountains, markedDate: .sample(2026, 10, 24), effectiveDate: .sample(2026, 10, 24), rating: 4, comment: "过去心不可得，现在心不可得，未来心不可得。", durationMinutes: 110, year: "2015"),
            MediaRecord(mediaType: .movie, status: .done, title: "疯狂的麦克斯 4：狂暴之路", subjectID: "3592854", doubanURL: "https://movie.douban.com/subject/3592854/", art: .road, markedDate: .sample(2026, 10, 12), effectiveDate: .sample(2026, 10, 12), rating: 5, comment: "两个小时几乎一直在跑，但每一帧都在讲故事。", durationMinutes: 120, year: "2015"),
            MediaRecord(mediaType: .movie, status: .done, title: "海上钢琴师", subjectID: "1292001", doubanURL: "https://movie.douban.com/subject/1292001/", art: .sea, markedDate: .sample(2026, 10, 12), effectiveDate: .sample(2026, 10, 12), rating: 5, comment: "他最后没有下船，因为城市没有尽头。", durationMinutes: 165, year: "1998"),
            MediaRecord(mediaType: .movie, status: .done, title: "白日梦想家", subjectID: "2131459", doubanURL: "https://movie.douban.com/subject/2131459/", art: .city, markedDate: .sample(2026, 10, 11), effectiveDate: .sample(2026, 10, 11), rating: 4, comment: "生活的目的就是生活本身。", durationMinutes: 114, year: "2013"),
            MediaRecord(mediaType: .movie, status: .done, title: "情书", subjectID: "1292220", doubanURL: "https://movie.douban.com/subject/1292220/", art: .bokeh, markedDate: .sample(2026, 9, 30), effectiveDate: .sample(2026, 9, 30), rating: 5, comment: "你好吗？我很好。", durationMinutes: 117, year: "1995", isLocalEdited: true),
            MediaRecord(mediaType: .movie, status: .done, title: "小森林 夏秋篇", subjectID: "25814705", doubanURL: "https://movie.douban.com/subject/25814705/", art: .forest, markedDate: .sample(2026, 9, 30), effectiveDate: .sample(2026, 9, 30), rating: 4, comment: "", durationMinutes: 111, year: "2014"),
            MediaRecord(mediaType: .movie, status: .done, title: "沙丘 2", subjectID: "30011158", doubanURL: "https://movie.douban.com/subject/30011158/", art: .dunes, markedDate: .sample(2026, 11, 20), effectiveDate: .sample(2026, 3, 8), rating: 4, comment: "在沙与火里看见权力的形状。", durationMinutes: 166, year: "2024", deletedAt: .sample(2026, 11, 20), deleteSource: .user),

            MediaRecord(mediaType: .book, status: .done, title: "百年孤独", subjectID: "6082808", doubanURL: "https://book.douban.com/subject/6082808/", art: .bookCream, markedDate: .sample(2026, 11, 8), effectiveDate: .sample(2026, 11, 8), rating: 5, comment: "多年以后，面对行刑队，奥雷里亚诺·布恩迪亚上校将会回想起父亲带他去见识冰块的那个遥远的下午。", pages: 360, wordCount: 262_000, year: "1967"),
            MediaRecord(mediaType: .book, status: .done, title: "献给阿尔吉侬的花束", subjectID: "1080232", doubanURL: "https://book.douban.com/subject/1080232/", art: .bookViolet, markedDate: .sample(2026, 11, 8), effectiveDate: .sample(2026, 11, 8), rating: 5, comment: "智慧如果只会让人更孤独，那它还是礼物吗？", pages: 320, wordCount: 224_000, year: "1959"),
            MediaRecord(mediaType: .book, status: .done, title: "杀死一只知更鸟", subjectID: "1075312", doubanURL: "https://book.douban.com/subject/1075312/", art: .bookSage, markedDate: .sample(2026, 11, 8), effectiveDate: .sample(2026, 11, 8), rating: 4, comment: "你永远不可能真正了解一个人，除非你穿上他的鞋子走来走去。", pages: 442, wordCount: 186_000, year: "1960"),
            MediaRecord(mediaType: .book, status: .done, title: "悉达多", subjectID: "25920230", doubanURL: "https://book.douban.com/subject/25920230/", art: .bookSand, markedDate: .sample(2026, 10, 30), effectiveDate: .sample(2026, 10, 30), rating: 4, comment: "知识可以传授，智慧不能。", pages: 208, wordCount: 128_000, year: "1922", isLocalEdited: true),
            MediaRecord(mediaType: .book, status: .done, title: "我与地坛", subjectID: "1025358", doubanURL: "https://book.douban.com/subject/1025358/", art: .bookIvory, markedDate: .sample(2026, 10, 30), effectiveDate: .sample(2026, 10, 30), rating: 5, comment: "一个人，出生了，这就不再是一个可以辩论的问题，而只是上帝交给他的一个事实。", pages: 256, wordCount: 112_000, year: "2002"),
            MediaRecord(mediaType: .book, status: .done, title: "人类简史", subjectID: "25985021", doubanURL: "https://book.douban.com/subject/25985021/", art: .bookCharcoal, markedDate: .sample(2026, 10, 29), effectiveDate: .sample(2026, 10, 29), rating: 4, comment: "想象的共同体，让陌生人可以大规模协作。", pages: 440, wordCount: 325_000, year: "2011"),

            MediaRecord(mediaType: .movie, status: .wish, title: "沙丘 3", subjectID: "36081091", doubanURL: "https://movie.douban.com/subject/36081091/", art: .dunes, markedDate: .sample(2026, 11, 18), effectiveDate: .sample(2026, 11, 18), rating: 0, comment: "", intro: "待映 12-20", year: "2026"),
            MediaRecord(mediaType: .movie, status: .wish, title: "完美的日子", subjectID: "36151663", doubanURL: "https://movie.douban.com/subject/36151663/", art: .city, markedDate: .sample(2026, 11, 10), effectiveDate: .sample(2026, 11, 10), rating: 0, comment: "", durationMinutes: 124, year: "2023"),
            MediaRecord(mediaType: .movie, status: .wish, title: "机器人之梦", subjectID: "35416147", doubanURL: "https://movie.douban.com/subject/35416147/", art: .anime, markedDate: .sample(2026, 10, 22), effectiveDate: .sample(2026, 10, 22), rating: 0, comment: "", durationMinutes: 102, year: "2023"),
            MediaRecord(mediaType: .movie, status: .wish, title: "椒麻堂会", subjectID: "35312014", doubanURL: "https://movie.douban.com/subject/35312014/", art: .stage, markedDate: .sample(2026, 10, 20), effectiveDate: .sample(2026, 10, 20), rating: 0, comment: "", durationMinutes: 179, year: "2021"),
            MediaRecord(mediaType: .movie, status: .wish, title: "火山挚恋", subjectID: "35871872", doubanURL: "https://movie.douban.com/subject/35871872/", art: .volcano, markedDate: .sample(2026, 10, 2), effectiveDate: .sample(2026, 10, 2), rating: 0, comment: "", durationMinutes: 98, year: "2022"),
            MediaRecord(mediaType: .movie, status: .wish, title: "可怜的东西", subjectID: "35315912", doubanURL: "https://movie.douban.com/subject/35315912/", art: .nebula, markedDate: .sample(2026, 9, 18), effectiveDate: .sample(2026, 9, 18), rating: 0, comment: "", durationMinutes: 141, year: "2023"),

            MediaRecord(mediaType: .book, status: .wish, title: "夜晚的潜水艇", subjectID: "35014432", doubanURL: "https://book.douban.com/subject/35014432/", art: .bookTeal, markedDate: .sample(2026, 11, 16), effectiveDate: .sample(2026, 11, 16), rating: 0, comment: "", pages: 224, wordCount: 98_000, year: "2020"),
            MediaRecord(mediaType: .book, status: .wish, title: "可能性的艺术", subjectID: "35616509", doubanURL: "https://book.douban.com/subject/35616509/", art: .bookCream, markedDate: .sample(2026, 11, 9), effectiveDate: .sample(2026, 11, 9), rating: 0, comment: "", pages: 352, wordCount: 210_000, year: "2022"),
            MediaRecord(mediaType: .book, status: .wish, title: "克拉拉与太阳", subjectID: "35316109", doubanURL: "https://book.douban.com/subject/35316109/", art: .bookIvory, markedDate: .sample(2026, 10, 18), effectiveDate: .sample(2026, 10, 18), rating: 0, comment: "", pages: 392, wordCount: 240_000, year: "2021")
        ]
    }

    private static func makeDoulists() -> [Doulist] {
        [
            Doulist(title: "黑色电影 · 私人豆列", mediaType: .movie, isFollowing: false, isPublic: true, itemCount: 8, readCount: 8, arts: [.war, .road, .sea, .city], updatedAt: .sample(2026, 11, 12)),
            Doulist(title: "想在大银幕重看一遍", mediaType: .movie, isFollowing: false, isPublic: false, itemCount: 18, readCount: 9, arts: [.space, .bokeh, .mountains, .forest], updatedAt: .sample(2026, 11, 3)),
            Doulist(title: "2026 待映 · 关注豆列", mediaType: .movie, isFollowing: true, isPublic: true, itemCount: 26, readCount: 4, arts: [.nebula, .dunes, .volcano, .anime], updatedAt: .sample(2026, 10, 28)),
            Doulist(title: "华语作者电影补完计划", mediaType: .movie, isFollowing: false, isPublic: true, itemCount: 41, readCount: 27, arts: [.stage, .mountains, .city, .sea], updatedAt: .sample(2026, 10, 22)),
            Doulist(title: "科幻 · 视觉奇观", mediaType: .movie, isFollowing: true, isPublic: true, itemCount: 24, readCount: 16, arts: [.space, .dunes, .nebula, .road], updatedAt: .sample(2026, 10, 18)),
            Doulist(title: "想读的非虚构", mediaType: .book, isFollowing: false, isPublic: true, itemCount: 22, readCount: 9, arts: [.bookCharcoal, .bookIvory, .bookCream, .bookSage], updatedAt: .sample(2026, 11, 6)),
            Doulist(title: "华语文学 · 重读", mediaType: .book, isFollowing: true, isPublic: true, itemCount: 16, readCount: 11, arts: [.bookTeal, .bookCream, .bookSand, .bookViolet], updatedAt: .sample(2026, 10, 26))
        ]
    }

    private static func makeDoulistItems(for doulists: [Doulist]) -> [DoulistItem] {
        guard let first = doulists.first, let books = doulists.first(where: { $0.mediaType == .book }) else { return [] }
        let movies: [(String, String, PosterArt, Int, Bool)] = [
            ("大决战之辽沈战役", "1298661", .war, 209, true),
            ("疯狂的麦克斯 4：狂暴之路", "3592854", .road, 120, true),
            ("海上钢琴师", "1292001", .sea, 165, true),
            ("白日梦想家", "2131459", .city, 114, true),
            ("情书", "1292220", .bokeh, 117, true),
            ("路边野餐", "26337832", .mountains, 110, true),
            ("流浪地球 2", "35267208", .space, 173, true),
            ("小森林 夏秋篇", "25814705", .forest, 111, true)
        ]
        var items = movies.enumerated().map { index, item in
            DoulistItem(doulistID: first.id, mediaType: .movie, title: item.0, subjectID: item.1, isRead: item.4, art: item.2, durationMinutes: item.3, year: ["1991", "2015", "1998", "2013", "1995", "2015", "2023", "2014"][index])
        }
        let bookItems: [(String, String, PosterArt, Int, Int, Bool)] = [
            ("百年孤独", "6082808", .bookCream, 262_000, 360, true),
            ("献给阿尔吉侬的花束", "1080232", .bookViolet, 224_000, 320, true),
            ("杀死一只知更鸟", "1075312", .bookSage, 186_000, 442, true),
            ("悉达多", "25920230", .bookSand, 128_000, 208, true),
            ("我与地坛", "1025358", .bookIvory, 112_000, 256, true),
            ("人类简史", "25985021", .bookCharcoal, 325_000, 440, true)
        ]
        items += bookItems.map { item in
            DoulistItem(doulistID: books.id, mediaType: .book, title: item.0, subjectID: item.1, isRead: item.5, art: item.2, pages: item.4, wordCount: item.3)
        }
        return items
    }

    private static func makePlanFolders() -> [PlanFolder] {
        [
            PlanFolder(title: "2026 年补完 · 战争片", mediaType: .movie, note: "按时间顺序补", arts: [.war, .stage], itemCount: 10, readCount: 7, createdAt: .sample(2026, 1, 6)),
            PlanFolder(title: "想在大银幕重看", mediaType: .movie, note: "", arts: [.space, .bokeh], itemCount: 18, readCount: 9, createdAt: .sample(2026, 2, 14)),
            PlanFolder(title: "科幻 · 视觉奇观", mediaType: .movie, note: "优先 IMAX", arts: [.dunes, .nebula], itemCount: 24, readCount: 11, createdAt: .sample(2026, 3, 2)),
            PlanFolder(title: "华语作者电影", mediaType: .movie, note: "", arts: [.mountains, .sea], itemCount: 14, readCount: 5, createdAt: .sample(2026, 4, 18)),
            PlanFolder(title: "2026 非虚构", mediaType: .book, note: "每月一本", arts: [.bookCharcoal, .bookIvory], itemCount: 10, readCount: 4, createdAt: .sample(2026, 1, 12)),
            PlanFolder(title: "重读计划", mediaType: .book, note: "", arts: [.bookCream, .bookTeal], itemCount: 6, readCount: 2, createdAt: .sample(2026, 5, 8))
        ]
    }

    private static func makePlanItems(for folders: [PlanFolder]) -> [PlanItem] {
        guard let folder = folders.first, let bookFolder = folders.first(where: { $0.mediaType == .book }) else { return [] }
        let movieData: [(String, String, PosterArt, Bool, String, String)] = [
            ("大决战之辽沈战役", "1298661", .war, true, "已看 · 3 小时 29 分 · 10-25", "1991"),
            ("大决战之淮海战役", "1303193", .war, false, "未看 · 3 小时 40 分", "1991"),
            ("大决战之平津战役", "1303194", .war, false, "未看 · 3 小时 6 分", "1991"),
            ("路边野餐", "26337832", .mountains, true, "已看 · 1 小时 50 分 · 10-24", "2015"),
            ("疯狂的麦克斯 4：狂暴之路", "3592854", .road, true, "已看 · 2 小时 · 10-12", "2015"),
            ("海上钢琴师", "1292001", .sea, true, "已看 · 2 小时 45 分 · 10-12", "1998"),
            ("白日梦想家", "2131459", .city, true, "已看 · 1 小时 54 分 · 10-11", "2013"),
            ("情书", "1292220", .bokeh, true, "已看 · 1 小时 57 分 · 09-30", "1995"),
            ("小森林 夏秋篇", "25814705", .forest, true, "已看 · 1 小时 51 分 · 09-30", "2014"),
            ("椒麻堂会", "35312014", .stage, false, "未看 · 2 小时 59 分", "2021")
        ]
        var items = movieData.enumerated().map { index, item in
            PlanItem(folderID: folder.id, mediaType: .movie, title: item.0, subjectID: item.1, isRead: item.3, art: item.2, statsText: item.4, position: index)
        }
        items += [
            PlanItem(folderID: bookFolder.id, mediaType: .book, title: "百年孤独", subjectID: "6082808", isRead: true, art: .bookCream, statsText: "26.2 万字 · 360 页", position: 0),
            PlanItem(folderID: bookFolder.id, mediaType: .book, title: "悉达多", subjectID: "25920230", isRead: true, art: .bookSand, statsText: "12.8 万字 · 208 页", position: 1),
            PlanItem(folderID: bookFolder.id, mediaType: .book, title: "人类简史", subjectID: "25985021", isRead: false, art: .bookCharcoal, statsText: "32.5 万字 · 440 页", position: 2)
        ]
        return items
    }

    private static func makeReports() -> [GeneratedReport] {
        [
            GeneratedReport(title: "2026 年 10 月 · 观影月报", mediaType: .movie, scope: .month, generatedAt: .sample(2026, 11, 1), count: 14, fileName: "movie_month_2026-10.html", hasPNG: true),
            GeneratedReport(title: "2026 年 09 月 · 观影月报", mediaType: .movie, scope: .month, generatedAt: .sample(2026, 10, 1), count: 9, fileName: "movie_month_2026-09.html", hasPNG: false),
            GeneratedReport(title: "2025 年 · 观影年报", mediaType: .movie, scope: .year, generatedAt: .sample(2026, 1, 6), count: 86, fileName: "movie_year_2025.html", hasPNG: true),
            GeneratedReport(title: "2026 年 · 读书年报", mediaType: .book, scope: .year, generatedAt: .sample(2026, 1, 6), count: 42, fileName: "book_year_2026.html", hasPNG: true),
            GeneratedReport(title: "2026 年 10 月 · 读书月报", mediaType: .book, scope: .month, generatedAt: .sample(2026, 11, 1), count: 3, fileName: "book_month_2026-10.html", hasPNG: true),
            GeneratedReport(title: "观影 · 自定义报告", mediaType: .movie, scope: .custom, generatedAt: .sample(2026, 9, 18), count: 28, fileName: "movie_range_2026-06-01_2026-09-01.html", hasPNG: false)
        ]
    }
}
