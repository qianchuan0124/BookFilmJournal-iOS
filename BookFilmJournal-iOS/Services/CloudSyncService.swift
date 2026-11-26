import Foundation
import CryptoKit
import SQLite3
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Darwin)
import Darwin
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SyncKind: String, Codable, CaseIterable {
    case auto
    case manual

    var label: String { self == .auto ? L10n.Cloud.kindAuto : L10n.Cloud.kindManual }
}

struct SyncCounts: Hashable {
    var records = 0
    var movies = 0
    var books = 0
    var doulists = 0
    var doulistItems = 0
    var planFolders = 0
    var planItems = 0
    var bookWords = 0
    var bookMeta = 0
    var movieMeta = 0
    var ignoredSubjects = 0
    var purgedRecords = 0

    init() {}

    init(_ values: [String: Int]) {
        records = values["records"] ?? 0
        movies = values["records_movie"] ?? 0
        books = values["records_book"] ?? 0
        doulists = values["doulists"] ?? 0
        doulistItems = values["doulist_items"] ?? 0
        planFolders = values["plan_folders"] ?? 0
        planItems = values["plan_items"] ?? 0
        bookWords = values["book_words"] ?? 0
        bookMeta = values["book_meta"] ?? 0
        movieMeta = values["movie_meta"] ?? 0
        ignoredSubjects = values["ignored_subjects"] ?? 0
        purgedRecords = values["purged_records"] ?? 0
    }

    var dictionary: [String: Int] {
        [
            "records": records,
            "records_movie": movies,
            "records_book": books,
            "doulists": doulists,
            "doulist_items": doulistItems,
            "plan_folders": planFolders,
            "plan_items": planItems,
            "book_words": bookWords,
            "book_meta": bookMeta,
            "movie_meta": movieMeta,
            "ignored_subjects": ignoredSubjects,
            "purged_records": purgedRecords
        ]
    }

    var summary: String {
        let base = L10n.Cloud.snapshotSummary(String(describing: records), String(describing: doulists), String(describing: planFolders))
        guard ignoredSubjects > 0 || purgedRecords > 0 else { return base }
        return "\(base) · \(L10n.Cloud.snapshotMarkerSummary(String(describing: ignoredSubjects), String(describing: purgedRecords)))"
    }
}

struct SyncSnapshotInfo: Identifiable, Hashable {
    var id: String { name }
    let url: URL
    let name: String
    let createdAt: Date
    let kind: SyncKind
    let device: String
    let isMine: Bool
    let isLatest: Bool
    let size: Int
    let counts: SyncCounts
    var sequence: Int = 1
    var isDownloaded: Bool = true

    var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 HH:mm"
        return formatter.string(from: createdAt)
    }

    var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

struct SyncBackupOutcome {
    let snapshot: SyncSnapshotInfo
    let skipped: Bool
    let directory: URL
}

enum CloudSyncError: LocalizedError {
    case noFolder
    case folderUnavailable
    case writeFailed(String)
    case invalidSnapshot(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFolder: L10n.Cloud.noFolder
        case .folderUnavailable: L10n.Cloud.folderUnavailable
        case .writeFailed(let message): message
        case .invalidSnapshot(let message): message
        case .restoreFailed(let message): message
        }
    }
}

private struct IOSRecordFields: Codable {
    var mediaType: String
    var subjectID: String
    var status: String
    var durationMinutes: Int?
    var pages: Int?
    var year: String?
    var releaseDate: String?
    var art: String?
    var coverURL: String?
    var coverSource: String?
    var coverData: String?
}

private struct IOSDoulistItemFields: Codable {
    var listKey: String
    var mediaType: String
    var subjectID: String
    var durationMinutes: Int?
    var pages: Int?
    var wordCount: Int?
    var year: String?
    var releaseDate: String?
    var rating: Int?
    var comment: String?
    var intro: String?
    var createdAt: Date?
}

private struct IOSPlanItemFields: Codable {
    var folderKey: String
    var mediaType: String
    var subjectID: String
    var isRead: Bool
    var statsText: String?
    var releaseDate: String?
    var note: String?
    var source: String?
    var sourceID: String?
}

private struct IOSSnapshotSidecar: Codable {
    var version: Int = 1
    var records: [IOSRecordFields]
    var doulistItems: [IOSDoulistItemFields]? = nil
    var planItems: [IOSPlanItemFields]? = nil
}

enum CloudSyncService {
    static let subdirectory = "书影记录"
    nonisolated static let snapshotPrefix = "douban_trace_"
    nonisolated static let snapshotSuffix = ".db"
    nonisolated static let manifestName = "latest.json"
    static let keepAuto = 3
    static let keepManual = 2
    static let bookmarkKey = "bookfilm.sync.folderBookmark"
    static let folderNameKey = "bookfilm.sync.folderName"
    static let lastStateKey = "bookfilm.sync.lastState"
    static let lastTimeKey = "bookfilm.sync.lastTime"
    static let lastSnapshotKey = "bookfilm.sync.lastSnapshot"
    static let autoBackupKey = "bookfilm.sync.autoBackup"
    static let autoSyncKey = "bookfilm.sync.autoSync"

    private static var heldRoot: URL?
    private static var holdingAccess = false

    private static var bookmarkFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BookFilmJournal", isDirectory: true)
            .appendingPathComponent("cloud-sync-folder.bookmark")
    }

    static var deviceName: String {
        #if canImport(UIKit)
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "iPhone" : name
        #else
        return "iPhone"
        #endif
    }

    static var deviceTag: String {
        let digest = Insecure.SHA1.hash(data: Data(deviceName.utf8))
        return digest.prefix(2).map { String(format: "%02x", $0) }.joined()
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    // MARK: - Folder

    static func hasFolder() -> Bool { resolveRoot() != nil }

    static func folderDisplayName() -> String {
        guard let root = resolveRoot() else { return L10n.Cloud.unselected }
        let name = root.lastPathComponent
        return name == subdirectory ? name : "\(name) / \(subdirectory)"
    }

    static func saveFolder(_ url: URL) throws {
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        releaseHeldFolder()
        try? FileManager.default.createDirectory(at: bookmarkFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: bookmarkFileURL, options: .atomic)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
    }

    static func clearFolder() {
        releaseHeldFolder()
        try? FileManager.default.removeItem(at: bookmarkFileURL)
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderNameKey)
        UserDefaults.standard.removeObject(forKey: lastStateKey)
        UserDefaults.standard.removeObject(forKey: lastTimeKey)
        UserDefaults.standard.removeObject(forKey: lastSnapshotKey)
    }

    static func resetLocalBookkeeping() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastStateKey)
        defaults.removeObject(forKey: lastTimeKey)
        defaults.removeObject(forKey: lastSnapshotKey)
        defaults.removeObject(forKey: "bookfilm.sync.lastSummary")
        defaults.set(false, forKey: autoBackupKey)
        defaults.set(false, forKey: autoSyncKey)
        for key in Array(defaults.dictionaryRepresentation().keys) where key.hasPrefix("bookfilm.sync.lastIDs.") {
            defaults.removeObject(forKey: key)
        }
    }

    static func resolveRoot() -> URL? {
        if let heldRoot { return heldRoot }
        let data: Data?
        if let stored = try? Data(contentsOf: bookmarkFileURL) {
            data = stored
        } else {
            data = UserDefaults.standard.data(forKey: bookmarkKey)
        }
        guard let data else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }

        let access = url.startAccessingSecurityScopedResource()
        if access {
            if let refreshed = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
            heldRoot = url
            holdingAccess = true
        } else if stale {
            return nil
        } else {
            heldRoot = url
        }
        return url
    }

    private static func releaseHeldFolder() {
        if holdingAccess {
            heldRoot?.stopAccessingSecurityScopedResource()
        }
        heldRoot = nil
        holdingAccess = false
    }

    static func snapshotsDirectory(create: Bool) throws -> URL? {
        guard let root = resolveRoot() else { return nil }
        let candidates = snapshotDirectoryCandidates(root: root)
        let directory = candidates.first(where: hasSnapshotData)
            ?? candidates[0]
        if create {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw CloudSyncError.writeFailed(L10n.Cloud.createDirFailed(error.localizedDescription))
            }
        }
        return directory
    }

    private static func snapshotDirectoryCandidates(root: URL) -> [URL] {
        let nested = root.appendingPathComponent(subdirectory, isDirectory: true)
        return root.lastPathComponent == subdirectory
            ? [root, nested]
            : [nested, root]
    }

    nonisolated private static func hasSnapshotData(in directory: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return entries.contains {
            $0 == manifestName || $0 == "devices.json"
                || $0.hasPrefix(snapshotPrefix)
                || ($0.hasPrefix(".") && $0.contains(snapshotPrefix))
        }
    }

    static func lastBackupText() -> String {
        guard let raw = UserDefaults.standard.string(forKey: lastTimeKey), !raw.isEmpty else { return "" }
        guard let date = manifestDateFormatter.date(from: raw) else { return raw }
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "M 月 d 日 HH:mm"
        return display.string(from: date)
    }

    static func autoSyncCandidate(current: LibrarySnapshot, exploreSites: [ExploreSite] = []) -> SyncSnapshotInfo? {
        guard resolveRoot() != nil,
              let manifest = loadManifest(),
              manifest.snapshot != UserDefaults.standard.string(forKey: lastSnapshotKey) else {
            return nil
        }
        let localState = stateID(current, exploreSites: exploreSites)
        let lastState = UserDefaults.standard.string(forKey: lastStateKey)
        guard lastState == nil ? current.records.isEmpty : lastState == localState else {
            return nil
        }
        return listSnapshots().first { $0.name == manifest.snapshot }
    }

    // MARK: - Manifest and listing

    private struct Manifest: Codable {
        var snapshot: String
        var createdAt: String
        var createdTs: Int
        var device: String
        var appVersion: String
        var sha256: String
        var size: Int
        var kind: String
        var recordsUpdated: String
        var counts: [String: Int]
        var tag: String? = nil
        var platform: String? = nil
        var arch: String? = nil

        enum CodingKeys: String, CodingKey {
            case snapshot
            case createdAt = "created_at"
            case createdTs = "created_ts"
            case device
            case appVersion = "app_version"
            case sha256
            case size
            case kind
            case recordsUpdated = "records_updated"
            case counts
            case tag
            case platform
            case arch
        }
    }

    private static func loadManifest() -> Manifest? {
        guard let root = resolveRoot() else { return nil }
        let candidates = snapshotDirectoryCandidates(root: root)
        for directory in candidates {
            let url = directory.appendingPathComponent(manifestName)
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  !manifest.snapshot.isEmpty else { continue }
            return manifest
        }
        return nil
    }

    static func listSnapshots() -> [SyncSnapshotInfo] {
        guard let root = resolveRoot() else { return [] }
        let manifest = loadManifest()
        let directories = snapshotDirectoryCandidates(root: root)
        let deviceProfiles = loadDeviceProfiles(from: directories)
        var candidates: [String: (url: URL, isDownloaded: Bool)] = [:]
        for directory in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for entry in entries {
                if entry.hasPrefix(snapshotPrefix), entry.hasSuffix(snapshotSuffix) {
                    candidates[entry] = (directory.appendingPathComponent(entry), true)
                } else if entry.hasPrefix("."), entry.hasSuffix(snapshotSuffix + ".icloud") {
                    let name = String(entry.dropFirst().dropLast(".icloud".count))
                    if candidates[name]?.isDownloaded != true {
                        candidates[name] = (directory.appendingPathComponent(name), false)
                    }
                }
            }
        }

        var result: [SyncSnapshotInfo] = []
        for (name, entry) in candidates {
            guard let parsed = parseName(name) else { continue }
            let url = entry.url
            let size = entry.isDownloaded ? ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) : 0
            let counts: SyncCounts
            if let manifest, manifest.snapshot == name {
                counts = SyncCounts(manifest.counts)
            } else {
                counts = entry.isDownloaded ? (readCounts(at: url) ?? SyncCounts()) : SyncCounts()
            }
            let isLatest = manifest?.snapshot == name
            let profile = deviceProfiles[parsed.tag]
            let device: String
            if isLatest, let manifestDevice = manifest?.device, !manifestDevice.isEmpty {
                device = [manifestDevice, manifest?.platform]
                    .compactMap { value in
                        guard let value, !value.isEmpty else { return nil }
                        return value
                    }
                    .joined(separator: " · ")
            } else {
                let name = profile?["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = (name?.isEmpty == false ? name : nil)
                    ?? (parsed.tag == deviceTag ? L10n.Cloud.localDevice : L10n.Cloud.otherDevice(parsed.tag))
                let platform = profile?["platform"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let platform, !platform.isEmpty {
                    device = "\(base) · \(platform)"
                } else {
                    device = base
                }
            }
            result.append(
                SyncSnapshotInfo(
                    url: url,
                    name: name,
                    createdAt: parsed.date,
                    kind: parsed.kind,
                    device: device,
                    isMine: parsed.tag == deviceTag,
                    isLatest: isLatest,
                    size: size,
                    counts: counts,
                    sequence: parsed.seq,
                    isDownloaded: entry.isDownloaded
                )
            )
        }
        return result.sorted {
            $0.createdAt == $1.createdAt ? $0.sequence > $1.sequence : $0.createdAt > $1.createdAt
        }
    }

    static func requestDownload(at url: URL) -> Bool {
        guard resolveRoot() != nil else { return false }
        guard !FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return true
        } catch {
            return false
        }
    }

    private static func loadDeviceProfiles(from directories: [URL]) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for directory in directories {
            let url = directory.appendingPathComponent("devices.json")
            guard let data = try? Data(contentsOf: url),
                  let profiles = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { continue }
            result.merge(profiles) { current, incoming in incoming }
        }
        return result
    }

    private static func parseName(_ name: String) -> (tag: String, kind: SyncKind, date: Date, seq: Int)? {
        guard name.hasPrefix(snapshotPrefix), name.hasSuffix(snapshotSuffix) else { return nil }
        let core = String(name.dropFirst(snapshotPrefix.count).dropLast(snapshotSuffix.count))
        let parts = core.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return nil }
        let datePart = parts[0] + "_" + parts[1]
        guard datePart.count == 15 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        guard let date = formatter.date(from: datePart) else { return nil }
        guard parts.count >= 3 else { return nil }
        let tag = parts[2]
        let kind = parts.count >= 4 && parts[3] == "auto" ? SyncKind.auto : .manual
        let seq = parts.count >= 5 ? (Int(parts[4]) ?? 1) : 1
        return (tag, kind, date, seq)
    }

    // MARK: - Backup

    static func backup(
        snapshot: LibrarySnapshot,
        kind: SyncKind,
        force: Bool = true,
        exploreSites: [ExploreSite] = []
    ) throws -> SyncBackupOutcome {
        guard let directory = try snapshotsDirectory(create: true) else {
            throw CloudSyncError.noFolder
        }
        let state = stateID(snapshot, exploreSites: exploreSites)
        if !force,
           UserDefaults.standard.string(forKey: lastStateKey) == state,
           let manifest = loadManifest(),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifest.snapshot).path) {
            let info = listSnapshots().first { $0.name == manifest.snapshot }
                ?? SyncSnapshotInfo(
                    url: directory.appendingPathComponent(manifest.snapshot),
                    name: manifest.snapshot,
                    createdAt: Date(),
                    kind: kind,
                    device: deviceName,
                    isMine: true,
                    isLatest: true,
                    size: manifest.size,
                    counts: SyncCounts(manifest.counts)
                )
            return SyncBackupOutcome(snapshot: info, skipped: true, directory: directory)
        }

        let name = uniqueSnapshotName(in: directory, kind: kind)
        let finalURL = directory.appendingPathComponent(name)
        let tempURL = directory.appendingPathComponent(".\(name).part")
        try? FileManager.default.removeItem(at: tempURL)

        do {
            try DesktopSnapshotBridge.write(snapshot, exploreSites: exploreSites, to: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw CloudSyncError.writeFailed(L10n.Cloud.writeSnapshotFailed(error.localizedDescription))
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
            try writeSidecar(for: snapshot, snapshotURL: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw CloudSyncError.writeFailed(L10n.Cloud.saveSnapshotFailed(error.localizedDescription))
        }

        let counts = DesktopSnapshotBridge.counts(at: finalURL) ?? SyncCounts()
        let manifest = Manifest(
            snapshot: name,
            createdAt: manifestDateFormatter.string(from: Date()),
            createdTs: Int(Date().timeIntervalSince1970),
            device: deviceName,
            appVersion: appVersion,
            sha256: sha256(at: finalURL),
            size: (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
            kind: kind.rawValue,
            recordsUpdated: latestRecordDate(snapshot),
            counts: counts.dictionary,
            tag: deviceTag,
            platform: "iOS",
            arch: "arm64"
        )
        try writeManifest(manifest, to: directory)
        writeDeviceProfile(to: directory)
        pruneSnapshots(in: directory)

        UserDefaults.standard.set(state, forKey: lastStateKey)
        UserDefaults.standard.set(manifest.createdAt, forKey: lastTimeKey)
        UserDefaults.standard.set(name, forKey: lastSnapshotKey)

        let info = SyncSnapshotInfo(
            url: finalURL,
            name: name,
            createdAt: Date(),
            kind: kind,
            device: deviceName,
            isMine: true,
            isLatest: true,
            size: manifest.size,
            counts: counts
        )
        return SyncBackupOutcome(snapshot: info, skipped: false, directory: directory)
    }

    private static func uniqueSnapshotName(in directory: URL, kind: SyncKind) -> String {
        let stamp = fileStampFormatter.string(from: Date())
        let prefix = "\(snapshotPrefix)\(stamp)_\(deviceTag)_\(kind.rawValue)"
        var maxSequence = 0
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            for entry in entries {
                let name: String
                if entry.hasPrefix("."), entry.hasSuffix(snapshotSuffix + ".icloud") {
                    name = String(entry.dropFirst().dropLast(".icloud".count))
                } else {
                    name = entry
                }
                guard name.hasPrefix(prefix),
                      let parsed = parseName(name),
                      parsed.tag == deviceTag,
                      parsed.kind == kind else { continue }
                maxSequence = max(maxSequence, parsed.seq)
            }
        }
        let next = maxSequence + 1
        if next <= 1 {
            return "\(prefix)\(snapshotSuffix)"
        }
        return "\(prefix)_\(next)\(snapshotSuffix)"
    }

    private static func writeDeviceProfile(to directory: URL) {
        let url = directory.appendingPathComponent("devices.json")
        var devices: [String: [String: String]] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            devices = existing
        }
        devices[deviceTag] = [
            "name": deviceName,
            "platform": "iOS",
            "arch": "arm64",
            "last_seen": manifestDateFormatter.string(from: Date())
        ]
        guard let data = try? JSONEncoder().encode(devices) else { return }
        // 直接原子覆盖：先删后移会让另一端短暂读不到文件，中断时还会丢登记信息。
        try? data.write(to: url, options: .atomic)
    }

    private static func writeManifest(_ manifest: Manifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let url = directory.appendingPathComponent(manifestName)
        try data.write(to: url, options: .atomic)
    }

    private static func pruneSnapshots(in directory: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        var groups: [String: [String]] = [:]
        var seen = Set<String>()
        for entry in entries {
            let name: String
            if entry.hasPrefix(snapshotPrefix), entry.hasSuffix(snapshotSuffix) {
                name = entry
            } else if entry.hasPrefix("."), entry.hasSuffix(snapshotSuffix + ".icloud") {
                name = String(entry.dropFirst().dropLast(".icloud".count))
            } else {
                continue
            }
            guard name != manifestName, parseName(name) != nil, seen.insert(name).inserted else { continue }
            guard let parsed = parseName(name) else { continue }
            let key = "\(parsed.tag)|\(parsed.kind.rawValue)"
            groups[key, default: []].append(name)
        }
        for (key, values) in groups {
            let keep = key.hasSuffix("|auto") ? keepAuto : keepManual
            let sorted = values.sorted {
                let left = parseName($0)
                let right = parseName($1)
                if let left, let right, left.date == right.date {
                    return left.seq > right.seq
                }
                return $0 > $1
            }
            for name in sorted.dropFirst(keep) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name + ".ios.json"))
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(".\(name).icloud"))
            }
        }
    }

    // MARK: - Restore

    static func restore(_ info: SyncSnapshotInfo, current: LibrarySnapshot, exploreSites: [ExploreSite] = []) throws -> (LibrarySnapshot, URL, [ExploreSite]) {
        guard FileManager.default.fileExists(atPath: info.url.path) else {
            throw CloudSyncError.invalidSnapshot(L10n.Cloud.snapshotNotDownloaded)
        }
        // 清单只描述最新一份快照；恢复它之前比对 sha256，避免 iCloud 还没同步完就整库覆盖。
        if info.isLatest, let manifest = loadManifest(), !manifest.sha256.isEmpty,
           sha256(at: info.url) != manifest.sha256 {
            throw CloudSyncError.invalidSnapshot(L10n.Cloud.snapshotIntegrityFailed)
        }
        let localBackup = try writeLocalBackup(current)
        do {
            var restored = try DesktopSnapshotBridge.read(from: info.url)
            applySidecar(to: &restored, snapshotURL: info.url)
            restored.reports = current.reports
            let marksAuthoritative = DesktopSnapshotBridge.hasMarksVersion(at: info.url)
            let isIOSSnapshot = FileManager.default.fileExists(
                atPath: sidecarURL(for: info.url).path
            ) || !DesktopSnapshotBridge.readExploreSites(from: info.url).isEmpty
            if !marksAuthoritative,
               isIOSSnapshot,
               (restored.ignoredSubjects?.isEmpty ?? true),
               (restored.purgedRecords?.isEmpty ?? true) {
                restored.ignoredSubjects = current.ignoredSubjects
                restored.purgedRecords = current.purgedRecords
            }
            let restoredExploreSites = DesktopSnapshotBridge.readExploreSites(from: info.url)
            UserDefaults.standard.set(info.name, forKey: lastSnapshotKey)
            UserDefaults.standard.set(manifestDateFormatter.string(from: Date()), forKey: lastTimeKey)
            UserDefaults.standard.set(stateID(restored, exploreSites: restoredExploreSites.isEmpty ? exploreSites : restoredExploreSites), forKey: lastStateKey)
            return (restored, localBackup, restoredExploreSites)
        } catch {
            throw CloudSyncError.restoreFailed(L10n.Cloud.restoreFailed(error.localizedDescription))
        }
    }

    static func writeLocalBackup(_ snapshot: LibrarySnapshot) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("BookFilmJournal", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "library_before_restore_\(fileStampFormatter.string(from: Date())).json"
        let url = directory.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)

        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let backups = files.filter { $0.lastPathComponent.hasPrefix("library_before_restore_") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for file in backups.dropFirst(5) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return url
    }

    nonisolated private static func sidecarListKey(_ list: Doulist) -> String {
        if let id = list.doubanID, !id.isEmpty { return "douban:\(id)" }
        let title = list.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return "local:\(list.mediaType.rawValue):\(title)"
    }

    nonisolated private static func sidecarFolderKey(_ folder: PlanFolder) -> String {
        let title = folder.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return "local:\(folder.mediaType.rawValue):\(title)"
    }

    private static func writeSidecar(for snapshot: LibrarySnapshot, snapshotURL: URL) throws {
        let fields = snapshot.records.filter { $0.isHidden != true }.map { record in
            let source = record.coverSource ?? (record.localCover == true ? .builtin : .douban)
            let coverData = source == .link ? CoverStore.base64(for: record.linkCoverKey) : nil
            return IOSRecordFields(
                mediaType: record.mediaType.rawValue,
                subjectID: record.subjectID,
                status: record.status.rawValue,
                durationMinutes: record.durationMinutes,
                pages: record.pages,
                year: record.year,
                releaseDate: record.releaseDate,
                art: record.art.rawValue,
                coverURL: record.coverURL,
                coverSource: source.rawValue,
                coverData: coverData
            )
        }
        let listKeys = Dictionary(
            snapshot.doulists.map { ($0.id, sidecarListKey($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let itemFields = snapshot.doulistItems.compactMap { item -> IOSDoulistItemFields? in
            guard let listKey = listKeys[item.doulistID] else { return nil }
            return IOSDoulistItemFields(
                listKey: listKey,
                mediaType: item.mediaType.rawValue,
                subjectID: item.subjectID,
                durationMinutes: item.durationMinutes,
                pages: item.pages,
                wordCount: item.wordCount,
                year: item.year,
                releaseDate: item.releaseDate,
                rating: item.rating,
                comment: item.comment,
                intro: item.intro,
                createdAt: item.createdAt
            )
        }
        let folderKeys = Dictionary(
            snapshot.planFolders.map { ($0.id, sidecarFolderKey($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let planFields = snapshot.planItems.compactMap { item -> IOSPlanItemFields? in
            guard let folderKey = folderKeys[item.folderID] else { return nil }
            return IOSPlanItemFields(
                folderKey: folderKey,
                mediaType: item.mediaType.rawValue,
                subjectID: item.subjectID,
                isRead: item.isRead,
                statsText: item.statsText,
                releaseDate: item.releaseDate,
                note: item.note,
                source: item.source,
                sourceID: item.sourceID
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(IOSSnapshotSidecar(records: fields, doulistItems: itemFields, planItems: planFields))
        try data.write(to: sidecarURL(for: snapshotURL), options: .atomic)
    }

    private static func applySidecar(to snapshot: inout LibrarySnapshot, snapshotURL: URL) {
        let url = sidecarURL(for: snapshotURL)
        guard let data = try? Data(contentsOf: url),
              let sidecar = decodeSidecar(data) else { return }
        let lookup = Dictionary(
            sidecar.records.map { ("\($0.mediaType)|\($0.subjectID)|\($0.status)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        snapshot.records = snapshot.records.map { record in
            let key = "\(record.mediaType.rawValue)|\(record.subjectID)|\(record.status.rawValue)"
            guard let fields = lookup[key] else { return record }
            var value = record
            if let duration = fields.durationMinutes { value.durationMinutes = duration }
            if let pages = fields.pages { value.pages = pages }
            if let year = fields.year { value.year = year }
            if let release = fields.releaseDate { value.releaseDate = release }
            if let raw = fields.art, let art = PosterArt(rawValue: raw) { value.art = art }
            if let cover = fields.coverURL { value.coverURL = cover }
            if let raw = fields.coverSource, let source = CoverSource(rawValue: raw) {
                value.coverSource = source
                value.localCover = source != .douban
                if source == .link, let data = fields.coverData {
                    _ = CoverStore.writeBase64(data, key: value.linkCoverKey)
                }
            }
            return value
        }

        let bySubject = Dictionary(snapshot.records.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
        snapshot.doulistItems = snapshot.doulistItems.map { item in
            guard let record = bySubject[item.subjectID] else { return item }
            var value = item
            value.isRead = record.status == .done
            value.art = record.art
            value.durationMinutes = record.durationMinutes
            value.pages = record.pages
            value.wordCount = record.wordCount
            value.year = record.year
            if let release = record.releaseDate { value.releaseDate = release }
            return value
        }
        snapshot.planItems = snapshot.planItems.map { item in
            guard let record = bySubject[item.subjectID] else { return item }
            var value = item
            value.isRead = record.status == .done
            value.art = record.art
            value.statsText = record.statsText
            if let release = record.releaseDate { value.releaseDate = release }
            return value
        }

        if let planFields = sidecar.planItems {
            let planLookup = Dictionary(
                planFields.map { ("\($0.folderKey)|\($0.mediaType)|\($0.subjectID)", $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let folderKeys = Dictionary(
                snapshot.planFolders.map { ($0.id, sidecarFolderKey($0)) },
                uniquingKeysWith: { first, _ in first }
            )
            snapshot.planItems = snapshot.planItems.map { item in
                guard let folderKey = folderKeys[item.folderID] else { return item }
                let key = "\(folderKey)|\(item.mediaType.rawValue)|\(item.subjectID)"
                guard let fields = planLookup[key] else { return item }
                var value = item
                value.isRead = fields.isRead
                if let stats = fields.statsText { value.statsText = stats }
                if let release = fields.releaseDate { value.releaseDate = release }
                if let note = fields.note { value.note = note }
                if let source = fields.source { value.source = source }
                if let sourceID = fields.sourceID { value.sourceID = sourceID }
                return value
            }
        }

        guard let itemFields = sidecar.doulistItems else { return }
        let itemLookup = Dictionary(
            itemFields.map { ("\($0.listKey)|\($0.mediaType)|\($0.subjectID)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        snapshot.doulistItems = snapshot.doulistItems.map { item in
            guard let listKey = snapshot.doulists.first(where: { $0.id == item.doulistID }).map(sidecarListKey) else {
                return item
            }
            let key = "\(listKey)|\(item.mediaType.rawValue)|\(item.subjectID)"
            guard let fields = itemLookup[key] else { return item }
            var value = item
            value.durationMinutes = fields.durationMinutes ?? value.durationMinutes
            value.pages = fields.pages ?? value.pages
            value.wordCount = fields.wordCount ?? value.wordCount
            value.year = fields.year ?? value.year
            value.releaseDate = fields.releaseDate ?? value.releaseDate
            value.rating = fields.rating ?? value.rating
            value.comment = fields.comment ?? value.comment
            value.intro = fields.intro ?? value.intro
            value.createdAt = fields.createdAt ?? value.createdAt
            return value
        }
    }

    private static func decodeSidecar(_ data: Data) -> IOSSnapshotSidecar? {
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(IOSSnapshotSidecar.self, from: data) { return value }
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(IOSSnapshotSidecar.self, from: data)
    }

    private static func sidecarURL(for snapshotURL: URL) -> URL {
        snapshotURL.deletingLastPathComponent()
            .appendingPathComponent(snapshotURL.lastPathComponent + ".ios.json")
    }

    // MARK: - Utilities

    static func stateID(_ snapshot: LibrarySnapshot, exploreSites: [ExploreSite] = []) -> String {
        var value = snapshot
        value.reports = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(value) else { return UUID().uuidString }
        let coverState = snapshot.records.compactMap { record -> String? in
            guard record.isCustomCover else { return nil }
            if record.coverSource == .link, let fingerprint = CoverStore.fingerprint(for: record.linkCoverKey) {
                return "\(record.subjectID):link:\(fingerprint)"
            }
            return "\(record.subjectID):\(record.coverSource?.rawValue ?? "builtin"):\(record.art.rawValue)"
        }.joined(separator: "|")
        data.append(contentsOf: coverState.utf8)
        if !exploreSites.isEmpty, let exploreData = try? JSONEncoder().encode(exploreSites) {
            data.append(exploreData)
        }
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func latestRecordDate(_ snapshot: LibrarySnapshot) -> String {
        let dates = snapshot.records.map(\.effectiveDate) + snapshot.records.map(\.markedDate)
        guard let latest = dates.max() else { return "" }
        return manifestDateFormatter.string(from: latest)
    }

    private static func readCounts(at url: URL) -> SyncCounts? {
        DesktopSnapshotBridge.counts(at: url)
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private static let manifestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

// MARK: - Desktop SQLite bridge

enum DesktopSnapshotBridge {
    private static let schema = """
    CREATE TABLE IF NOT EXISTS records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_type TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        cover_url TEXT NOT NULL DEFAULT '',
        cover_path TEXT NOT NULL DEFAULT '',
        rating INTEGER NOT NULL DEFAULT 0,
        marked_date TEXT NOT NULL DEFAULT '',
        effective_date TEXT NOT NULL DEFAULT '',
        date_overridden INTEGER NOT NULL DEFAULT 0,
        rating_overridden INTEGER NOT NULL DEFAULT 0,
        comment_overridden INTEGER NOT NULL DEFAULT 0,
        comment TEXT NOT NULL DEFAULT '',
        intro TEXT NOT NULL DEFAULT '',
        word_count INTEGER NOT NULL DEFAULT 0,
        book_file TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'douban',
        status TEXT NOT NULL DEFAULT 'done',
        synced_at TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL DEFAULT '',
        deleted_by TEXT NOT NULL DEFAULT '',
        UNIQUE(media_type, subject_id, status)
    );
    CREATE TABLE IF NOT EXISTS doulists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_type TEXT NOT NULL DEFAULT 'movie',
        douban_id TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        item_count INTEGER NOT NULL DEFAULT 0,
        relation TEXT NOT NULL DEFAULT 'created',
        position INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS doulist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doulist_id INTEGER NOT NULL REFERENCES doulists(id) ON DELETE CASCADE,
        media_type TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        cover_url TEXT NOT NULL DEFAULT '',
        cover_path TEXT NOT NULL DEFAULT '',
        rating INTEGER NOT NULL DEFAULT 0,
        comment TEXT NOT NULL DEFAULT '',
        intro TEXT NOT NULL DEFAULT '',
        position INTEGER NOT NULL DEFAULT 0,
        create_time TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'done',
        duration_minutes INTEGER NOT NULL DEFAULT 0,
        pages INTEGER NOT NULL DEFAULT 0,
        word_count INTEGER NOT NULL DEFAULT 0,
        year TEXT NOT NULL DEFAULT '',
        release_date TEXT NOT NULL DEFAULT '',
        UNIQUE(doulist_id, media_type, subject_id)
    );
    CREATE TABLE IF NOT EXISTS plan_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_type TEXT NOT NULL,
        title TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        position INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL DEFAULT '',
        UNIQUE(media_type, title)
    );
    CREATE TABLE IF NOT EXISTS plan_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER NOT NULL DEFAULT 0,
        media_type TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        cover_url TEXT NOT NULL DEFAULT '',
        cover_path TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        source_id TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        position INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'done',
        release_date TEXT NOT NULL DEFAULT '',
        UNIQUE(folder_id, media_type, subject_id)
    );
    CREATE TABLE IF NOT EXISTS book_words (
        subject_id TEXT PRIMARY KEY,
        word_count INTEGER NOT NULL DEFAULT 0,
        book_file TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS book_meta (
        subject_id TEXT PRIMARY KEY,
        pages INTEGER NOT NULL DEFAULT 0,
        pages_manual INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS movie_meta (
        subject_id TEXT PRIMARY KEY,
        duration_minutes INTEGER NOT NULL DEFAULT 0,
        duration_manual INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS ignored_subjects (
        media_type TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT '',
        PRIMARY KEY(media_type, subject_id)
    );
    CREATE TABLE IF NOT EXISTS purged_records (
        media_type TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'done',
        title TEXT NOT NULL DEFAULT '',
        purged_at TEXT NOT NULL DEFAULT '',
        PRIMARY KEY(media_type, subject_id, status)
    );
    """

    private static let requiredTables = ["records", "settings", "doulists", "plan_folders"]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let secondFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: Write

    static func write(_ snapshot: LibrarySnapshot, exploreSites: [ExploreSite], to url: URL) throws {
        let db = try open(url, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        defer { sqlite3_close(db) }
        try exec(db, schema)
        try exec(db, "BEGIN IMMEDIATE")

        do {
            let now = secondFormatter.string(from: Date())
            for record in snapshot.records where record.isHidden != true {
                try insertRecord(db, record, now: now)
            }

            var doulistIDs: [UUID: Int64] = [:]
            for (index, doulist) in snapshot.doulists.enumerated() {
                let id = try insertDoulist(db, doulist, index: index, now: now)
                doulistIDs[doulist.id] = id
            }
            for (index, item) in snapshot.doulistItems.enumerated() {
                guard let doulistID = doulistIDs[item.doulistID] else { continue }
                try insertDoulistItem(db, item, doulistID: doulistID, position: index, now: now)
            }

            for subject in snapshot.ignoredSubjects ?? [] {
                try insertIgnoredSubject(db, subject, now: now)
            }
            for record in snapshot.purgedRecords ?? [] {
                try insertPurgedRecord(db, record, now: now)
            }

            var folderIDs: [UUID: Int64] = [:]
            for (index, folder) in snapshot.planFolders.enumerated() {
                let id = try insertPlanFolder(db, folder, index: index, now: now)
                folderIDs[folder.id] = id
            }
            for item in snapshot.planItems {
                guard let folderID = folderIDs[item.folderID] else { continue }
                try insertPlanItem(db, item, folderID: folderID, now: now)
            }

            try insertSetting(db, key: "snapshot_marks_version", value: "1")
            if !exploreSites.isEmpty,
               let data = try? JSONEncoder().encode(exploreSites),
               let json = String(data: data, encoding: .utf8) {
                try insertSetting(db, key: "ios_explore_sites", value: json)
            }

            for record in snapshot.records where record.mediaType == .book && record.isHidden != true {
                if let words = record.wordCount, words > 0 {
                    try insertBookWords(db, record: record, now: now)
                }
                if let pages = record.pages, pages > 0 {
                    try insertBookMeta(db, record: record, now: now)
                }
            }
            var movieDurations: [String: Int] = [:]
            for record in snapshot.records where record.mediaType == .movie && record.isHidden != true {
                guard let duration = record.durationMinutes, duration > 0 else { continue }
                movieDurations[record.subjectID] = max(movieDurations[record.subjectID] ?? 0, duration)
            }
            for (subjectID, duration) in movieDurations {
                try insertMovieMeta(db, subjectID: subjectID, duration: duration, now: now)
            }

            try exec(db, "COMMIT")
        } catch {
            try? exec(db, "ROLLBACK")
            throw error
        }

        guard try integrityCheck(db) else {
            throw CloudSyncError.writeFailed(L10n.Cloud.snapshotIntegrityFailed)
        }
    }

    private static func insertRecord(_ db: OpaquePointer, _ record: MediaRecord, now: String) throws {
        let sql = """
        INSERT OR REPLACE INTO records
        (media_type, subject_id, title, url, cover_url, cover_path, rating, marked_date,
         effective_date, date_overridden, rating_overridden, comment_overridden, comment, intro,
         word_count, book_file, source, status, synced_at, created_at, updated_at, deleted_at, deleted_by)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, record.mediaType.rawValue)
        bind(stmt, 2, record.subjectID)
        bind(stmt, 3, record.title)
        bind(stmt, 4, record.doubanURL ?? "")
        bind(stmt, 5, "")
        bind(stmt, 6, "")
        bind(stmt, 7, Int64(record.rating))
        bind(stmt, 8, dayFormatter.string(from: record.markedDate))
        bind(stmt, 9, dayFormatter.string(from: record.effectiveDate))
        bind(stmt, 10, record.isLocalEdited ? 1 : 0)
        bind(stmt, 11, record.isLocalEdited ? 1 : 0)
        bind(stmt, 12, record.isLocalEdited ? 1 : 0)
        bind(stmt, 13, record.comment)
        bind(stmt, 14, record.intro)
        bind(stmt, 15, Int64(record.wordCount ?? 0))
        bind(stmt, 16, "")
        bind(stmt, 17, record.isLocalEdited ? "local" : "douban")
        bind(stmt, 18, record.status.rawValue)
        bind(stmt, 19, now)
        bind(stmt, 20, now)
        bind(stmt, 21, now)
        bind(stmt, 22, record.deletedAt.map { secondFormatter.string(from: $0) } ?? "")
        if let source = record.deleteSource {
            bind(stmt, 23, source == .sync ? "sync" : "user")
        } else {
            bind(stmt, 23, "")
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertIgnoredSubject(_ db: OpaquePointer, _ subject: IgnoredSubject, now: String) throws {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO ignored_subjects (media_type, subject_id, created_at)
        VALUES (?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, subject.mediaType.rawValue)
        bind(stmt, 2, subject.subjectID)
        bind(stmt, 3, subject.createdAt == .distantPast ? now : secondFormatter.string(from: subject.createdAt))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertPurgedRecord(_ db: OpaquePointer, _ record: PurgedRecord, now: String) throws {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO purged_records
        (media_type, subject_id, status, title, purged_at)
        VALUES (?,?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, record.mediaType.rawValue)
        bind(stmt, 2, record.subjectID)
        bind(stmt, 3, record.status.rawValue)
        bind(stmt, 4, record.title)
        bind(stmt, 5, record.purgedAt == .distantPast ? now : secondFormatter.string(from: record.purgedAt))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertDoulist(_ db: OpaquePointer, _ doulist: Doulist, index: Int, now: String) throws -> Int64 {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO doulists
        (media_type, douban_id, title, url, item_count, relation, position, synced_at, deleted_at)
        VALUES (?,?,?,?,?,?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, doulist.mediaType.rawValue)
        bind(stmt, 2, doulist.doubanID ?? "ios-local-\(doulist.id.uuidString)")
        bind(stmt, 3, doulist.title)
        bind(stmt, 4, "")
        bind(stmt, 5, Int64(doulist.itemCount))
        bind(stmt, 6, doulist.isFollowing ? "followed" : "created")
        bind(stmt, 7, Int64(index))
        bind(stmt, 8, now)
        bind(stmt, 9, doulist.deletedAt.map { secondFormatter.string(from: $0) } ?? "")
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
        return sqlite3_last_insert_rowid(db)
    }

    private static func insertDoulistItem(_ db: OpaquePointer, _ item: DoulistItem, doulistID: Int64, position: Int, now: String) throws {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO doulist_items
        (doulist_id, media_type, subject_id, title, url, cover_url, cover_path, rating,
         comment, intro, position, create_time, status, duration_minutes, pages,
         word_count, year, release_date)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, doulistID)
        bind(stmt, 2, item.mediaType.rawValue)
        bind(stmt, 3, item.subjectID)
        bind(stmt, 4, item.title)
        bind(stmt, 5, doubanURL(for: item.mediaType, subjectID: item.subjectID))
        bind(stmt, 6, item.coverURL ?? "")
        bind(stmt, 7, "")
        bind(stmt, 8, Int64(item.rating ?? 0))
        bind(stmt, 9, item.comment ?? "")
        bind(stmt, 10, item.intro ?? "")
        bind(stmt, 11, Int64(position))
        bind(stmt, 12, item.createdAt.map { secondFormatter.string(from: $0) } ?? now)
        bind(stmt, 13, item.isRead ? "done" : "wish")
        bind(stmt, 14, Int64(item.durationMinutes ?? 0))
        bind(stmt, 15, Int64(item.pages ?? 0))
        bind(stmt, 16, Int64(item.wordCount ?? 0))
        bind(stmt, 17, item.year ?? "")
        bind(stmt, 18, item.releaseDate ?? "")
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertPlanFolder(_ db: OpaquePointer, _ folder: PlanFolder, index: Int, now: String) throws -> Int64 {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO plan_folders
        (media_type, title, note, position, created_at, deleted_at)
        VALUES (?,?,?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, folder.mediaType.rawValue)
        bind(stmt, 2, folder.title)
        bind(stmt, 3, folder.note)
        bind(stmt, 4, Int64(index))
        bind(stmt, 5, secondFormatter.string(from: folder.createdAt))
        bind(stmt, 6, folder.deletedAt.map { secondFormatter.string(from: $0) } ?? "")
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
        return sqlite3_last_insert_rowid(db)
    }

    private static func insertPlanItem(_ db: OpaquePointer, _ item: PlanItem, folderID: Int64, now: String) throws {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO plan_items
        (folder_id, media_type, subject_id, title, url, cover_url, cover_path, source,
         source_id, note, position, created_at, deleted_at, status, release_date)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, folderID)
        bind(stmt, 2, item.mediaType.rawValue)
        bind(stmt, 3, item.subjectID)
        bind(stmt, 4, item.title)
        bind(stmt, 5, doubanURL(for: item.mediaType, subjectID: item.subjectID))
        bind(stmt, 6, "")
        bind(stmt, 7, "")
        bind(stmt, 8, item.source ?? "manual")
        bind(stmt, 9, item.sourceID ?? "")
        bind(stmt, 10, item.note)
        bind(stmt, 11, Int64(item.position))
        bind(stmt, 12, now)
        bind(stmt, 13, item.deletedAt.map { secondFormatter.string(from: $0) } ?? "")
        bind(stmt, 14, item.isRead ? "done" : "wish")
        bind(stmt, 15, item.releaseDate ?? "")
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertSetting(_ db: OpaquePointer, key: String, value: String) throws {
        let stmt = try prepare(db, "INSERT OR REPLACE INTO settings (key, value) VALUES (?,?)")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, key)
        bind(stmt, 2, value)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertBookWords(_ db: OpaquePointer, record: MediaRecord, now: String) throws {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO book_words (subject_id, word_count, book_file, updated_at)
        VALUES (?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, record.subjectID)
        bind(stmt, 2, Int64(record.wordCount ?? 0))
        bind(stmt, 3, "")
        bind(stmt, 4, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertMovieMeta(_ db: OpaquePointer, subjectID: String, duration: Int, now: String) throws {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO movie_meta (subject_id, duration_minutes, duration_manual, updated_at)
        VALUES (?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, subjectID)
        bind(stmt, 2, Int64(duration))
        bind(stmt, 3, 0)
        bind(stmt, 4, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    private static func insertBookMeta(_ db: OpaquePointer, record: MediaRecord, now: String) throws {
        let stmt = try prepare(db, """
        INSERT OR REPLACE INTO book_meta (subject_id, pages, pages_manual, updated_at)
        VALUES (?,?,?,?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, record.subjectID)
        bind(stmt, 2, Int64(record.pages ?? 0))
        bind(stmt, 3, 0)
        bind(stmt, 4, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
    }

    static func hasMarksVersion(at url: URL) -> Bool {
        guard let db = try? open(url, flags: SQLITE_OPEN_READONLY) else { return false }
        defer { sqlite3_close(db) }
        guard hasTable(db, "settings") else { return false }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM settings WHERE key = 'snapshot_marks_version'", -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return false }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return text(stmt, 0) == "1"
    }

    static func readExploreSites(from url: URL) -> [ExploreSite] {
        guard let db = try? open(url, flags: SQLITE_OPEN_READONLY) else { return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM settings WHERE key = 'ios_explore_sites'", -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cString = sqlite3_column_text(stmt, 0) else { return [] }
        let data = Data(String(cString: cString).utf8)
        return (try? JSONDecoder().decode([ExploreSite].self, from: data)) ?? []
    }

    // MARK: Read

    static func counts(at url: URL) -> SyncCounts? {
        guard let db = try? open(url, flags: SQLITE_OPEN_READONLY) else { return nil }
        defer { sqlite3_close(db) }
        var counts = SyncCounts()
        counts.records = scalar(db, "SELECT COUNT(*) FROM records")
        counts.movies = scalar(db, "SELECT COUNT(*) FROM records WHERE media_type='movie'")
        counts.books = scalar(db, "SELECT COUNT(*) FROM records WHERE media_type='book'")
        counts.doulists = scalar(db, "SELECT COUNT(*) FROM doulists")
        counts.doulistItems = scalar(db, "SELECT COUNT(*) FROM doulist_items")
        counts.planFolders = scalar(db, "SELECT COUNT(*) FROM plan_folders")
        counts.planItems = scalar(db, "SELECT COUNT(*) FROM plan_items")
        counts.bookWords = scalar(db, "SELECT COUNT(*) FROM book_words")
        counts.bookMeta = scalar(db, "SELECT COUNT(*) FROM book_meta")
        counts.movieMeta = scalar(db, "SELECT COUNT(*) FROM movie_meta")
        counts.ignoredSubjects = scalar(db, "SELECT COUNT(*) FROM ignored_subjects")
        counts.purgedRecords = scalar(db, "SELECT COUNT(*) FROM purged_records")
        return counts
    }

    static func read(from url: URL) throws -> LibrarySnapshot {
        let db = try open(url, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(db) }
        guard try integrityCheck(db) else {
            throw CloudSyncError.invalidSnapshot(L10n.Cloud.databaseIntegrityFailed)
        }
        let tables = Set(tableNames(db))
        for table in requiredTables where !tables.contains(table) {
            throw CloudSyncError.invalidSnapshot(L10n.Cloud.notSnapshot(table))
        }

        var records = try readRecords(db)
        let wordCounts = try readBookWords(db)
        let pages = try readBookMeta(db)
        let movieDurations = try readMovieMeta(db)
        records = records.map { record in
            var value = record
            if let words = wordCounts[record.subjectID] { value.wordCount = words }
            if let page = pages[record.subjectID] { value.pages = page }
            if record.mediaType == .movie, let duration = movieDurations[record.subjectID] {
                value.durationMinutes = duration
            }
            return value
        }
        let recordLookup = Dictionary(records.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })

        var doulists = try readDoulists(db)
        let doulistItems = try readDoulistItems(db, records: recordLookup)
        let itemCounts = Dictionary(grouping: doulistItems, by: \.doulistID).mapValues(\.count)
        let readCounts = Dictionary(grouping: doulistItems.filter(\.isRead), by: \.doulistID).mapValues(\.count)
        doulists = doulists.map { doulist in
            var value = doulist
            value.itemCount = itemCounts[doulist.id] ?? doulist.itemCount
            value.readCount = readCounts[doulist.id] ?? 0
            value.arts = Array(doulistItems.filter { $0.doulistID == doulist.id }.prefix(4).map(\.art))
            return value
        }

        var folders = try readPlanFolders(db)
        let planItems = try readPlanItems(db, records: recordLookup)
        folders = folders.map { folder in
            var value = folder
            let items = planItems.filter { $0.folderID == folder.id }
            value.itemCount = items.count
            value.readCount = items.filter(\.isRead).count
            value.arts = Array(items.prefix(2).map(\.art))
            return value
        }

        return LibrarySnapshot(
            records: records,
            doulists: doulists,
            doulistItems: doulistItems,
            planFolders: folders,
            planItems: planItems,
            reports: [],
            ignoredSubjects: try readIgnoredSubjects(db),
            purgedRecords: try readPurgedRecords(db)
        )
    }

    private static func readRecords(_ db: OpaquePointer) throws -> [MediaRecord] {
        let sql = """
        SELECT media_type, subject_id, title, url, rating, marked_date, effective_date,
               date_overridden, rating_overridden, comment_overridden, comment, intro,
               word_count, status, deleted_at, deleted_by, cover_url
        FROM records ORDER BY id
        """
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }
        var result: [MediaRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let media = MediaType(rawValue: text(stmt, 0)) ?? .movie
            let subject = text(stmt, 1)
            let title = text(stmt, 2)
            let url = text(stmt, 3)
            let rating = Int(sqlite3_column_int64(stmt, 4))
            let marked = parseDate(text(stmt, 5)) ?? Date()
            let effective = parseDate(text(stmt, 6)) ?? marked
            let edited = sqlite3_column_int64(stmt, 7) != 0
                || sqlite3_column_int64(stmt, 8) != 0
                || sqlite3_column_int64(stmt, 9) != 0
            let comment = text(stmt, 10)
            let intro = text(stmt, 11)
            let words = Int(sqlite3_column_int64(stmt, 12))
            let status = RecordStatus(rawValue: text(stmt, 13)) ?? .done
            let deletedAt = parseDate(text(stmt, 14))
            let deletedBy = text(stmt, 15)
            let coverURL = text(stmt, 16)
            result.append(
                MediaRecord(
                    mediaType: media,
                    status: status,
                    title: title,
                    subjectID: subject,
                    doubanURL: url.isEmpty ? nil : url,
                    coverURL: coverURL.isEmpty ? nil : coverURL,
                    art: art(for: media, subjectID: subject, title: title),
                    markedDate: marked,
                    effectiveDate: effective,
                    rating: rating,
                    comment: comment,
                    intro: intro,
                    durationMinutes: media == .movie ? parseMovieDuration(intro) : nil,
                    wordCount: words > 0 ? words : nil,
                    year: parseYear(intro),
                    isLocalEdited: edited,
                    deletedAt: deletedAt,
                    deleteSource: deletedAt == nil ? nil : (deletedBy == "sync" ? .sync : .user)
                )
            )
        }
        return result
    }

    private static func parseMovieDuration(_ intro: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{2,3})\s*分钟"#),
              let match = regex.firstMatch(in: intro, range: NSRange(intro.startIndex..., in: intro)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: intro),
              let value = Int(intro[range]) else { return nil }
        return value > 0 ? value : nil
    }

    private static func parseYear(_ intro: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(19\d{2}|20\d{2})[-年/.]"#),
              let match = regex.firstMatch(in: intro, range: NSRange(intro.startIndex..., in: intro)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: intro) else { return nil }
        return String(intro[range])
    }

    private static func readIgnoredSubjects(_ db: OpaquePointer) throws -> [IgnoredSubject] {
        guard hasTable(db, "ignored_subjects") else { return [] }
        let stmt = try prepare(db, "SELECT media_type, subject_id, created_at FROM ignored_subjects")
        defer { sqlite3_finalize(stmt) }
        var result: [IgnoredSubject] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let media = MediaType(rawValue: text(stmt, 0)) else { continue }
            result.append(IgnoredSubject(
                mediaType: media,
                subjectID: text(stmt, 1),
                createdAt: parseDate(text(stmt, 2)) ?? Date()
            ))
        }
        return result
    }

    private static func readPurgedRecords(_ db: OpaquePointer) throws -> [PurgedRecord] {
        guard hasTable(db, "purged_records") else { return [] }
        let stmt = try prepare(db, "SELECT media_type, subject_id, status, title, purged_at FROM purged_records")
        defer { sqlite3_finalize(stmt) }
        var result: [PurgedRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let media = MediaType(rawValue: text(stmt, 0)),
                  let status = RecordStatus(rawValue: text(stmt, 2)) else { continue }
            result.append(PurgedRecord(
                mediaType: media,
                subjectID: text(stmt, 1),
                status: status,
                title: text(stmt, 3),
                purgedAt: parseDate(text(stmt, 4)) ?? Date()
            ))
        }
        return result
    }

    private static func readMovieMeta(_ db: OpaquePointer) throws -> [String: Int] {
        guard hasTable(db, "movie_meta") else { return [:] }
        let stmt = try prepare(db, "SELECT subject_id, duration_minutes FROM movie_meta")
        defer { sqlite3_finalize(stmt) }
        var result: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let value = Int(sqlite3_column_int64(stmt, 1))
            if value > 0 { result[text(stmt, 0)] = value }
        }
        return result
    }

    private static func readBookWords(_ db: OpaquePointer) throws -> [String: Int] {
        guard hasTable(db, "book_words") else { return [:] }
        let stmt = try prepare(db, "SELECT subject_id, word_count FROM book_words")
        defer { sqlite3_finalize(stmt) }
        var result: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let value = Int(sqlite3_column_int64(stmt, 1))
            if value > 0 { result[text(stmt, 0)] = value }
        }
        return result
    }

    private static func readBookMeta(_ db: OpaquePointer) throws -> [String: Int] {
        guard hasTable(db, "book_meta") else { return [:] }
        let stmt = try prepare(db, "SELECT subject_id, pages FROM book_meta")
        defer { sqlite3_finalize(stmt) }
        var result: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let value = Int(sqlite3_column_int64(stmt, 1))
            if value > 0 { result[text(stmt, 0)] = value }
        }
        return result
    }

    private static func readDoulists(_ db: OpaquePointer) throws -> [Doulist] {
        let stmt = try prepare(db, """
        SELECT id, media_type, title, relation, item_count, position, douban_id, deleted_at
        FROM doulists ORDER BY id
        """)
        defer { sqlite3_finalize(stmt) }
        var rows: [(position: Int, index: Int, value: Doulist)] = []
        var index = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let media = MediaType(rawValue: text(stmt, 1)) ?? .movie
            let position = Int(sqlite3_column_int64(stmt, 5))
            let doubanID = doubanID(fromStored: text(stmt, 6))
            let id = doubanID.map(DoubanSyncService.stableID(forDoubanDoulistID:))
                ?? stableUUID(prefix: "1", index: index)
            rows.append((
                position: position,
                index: index,
                value: Doulist(
                    id: id,
                    title: text(stmt, 2),
                    doubanID: doubanID,
                    mediaType: media,
                    isFollowing: text(stmt, 3) != "created",
                    isPublic: true,
                    itemCount: Int(sqlite3_column_int64(stmt, 4)),
                    readCount: 0,
                    arts: [],
                    updatedAt: Date(),
                    deletedAt: parseDate(text(stmt, 7))
                )
            ))
            index += 1
        }
        return rows.sorted {
            $0.position == $1.position ? $0.index < $1.index : $0.position < $1.position
        }.map(\.value)
    }

    private static func readDoulistItems(_ db: OpaquePointer, records: [String: MediaRecord]) throws -> [DoulistItem] {
        let hasStatus = hasColumn(db, "doulist_items", "status")
        let hasDuration = hasColumn(db, "doulist_items", "duration_minutes")
        let hasPages = hasColumn(db, "doulist_items", "pages")
        let hasWords = hasColumn(db, "doulist_items", "word_count")
        let hasYear = hasColumn(db, "doulist_items", "year")
        let hasRelease = hasColumn(db, "doulist_items", "release_date")
        let hasCover = hasColumn(db, "doulist_items", "cover_url")
        let extraColumns = [
            (hasStatus, "status"),
            (hasDuration, "duration_minutes"),
            (hasPages, "pages"),
            (hasWords, "word_count"),
            (hasYear, "year"),
            (hasRelease, "release_date"),
            (hasCover, "cover_url")
        ].filter { $0.0 }.map { ", \($0.1)" }.joined()
        let stmt = try prepare(db, """
        SELECT doulist_id, media_type, subject_id, title, position, rating, comment, intro, create_time\(extraColumns)
        FROM doulist_items ORDER BY doulist_id, position, id
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [DoulistItem] = []
        let listStmt = try prepare(db, "SELECT id, douban_id FROM doulists ORDER BY id")
        var listIDsOrdered: [(rawID: Int64, doubanID: String?)] = []
        while sqlite3_step(listStmt) == SQLITE_ROW {
            listIDsOrdered.append((
                sqlite3_column_int64(listStmt, 0),
                doubanID(fromStored: text(listStmt, 1))
            ))
        }
        sqlite3_finalize(listStmt)
        var listIDs: [Int64: UUID] = [:]
        for (index, entry) in listIDsOrdered.enumerated() {
            listIDs[entry.rawID] = entry.doubanID.map(DoubanSyncService.stableID(forDoubanDoulistID:))
                ?? stableUUID(prefix: "1", index: index)
        }

        var extraIndex = 9
        let statusIndex: Int32? = hasStatus ? Int32(extraIndex) : nil
        if hasStatus { extraIndex += 1 }
        let durationIndex: Int32? = hasDuration ? Int32(extraIndex) : nil
        if hasDuration { extraIndex += 1 }
        let pagesIndex: Int32? = hasPages ? Int32(extraIndex) : nil
        if hasPages { extraIndex += 1 }
        let wordsIndex: Int32? = hasWords ? Int32(extraIndex) : nil
        if hasWords { extraIndex += 1 }
        let yearIndex: Int32? = hasYear ? Int32(extraIndex) : nil
        if hasYear { extraIndex += 1 }
        let releaseIndex: Int32? = hasRelease ? Int32(extraIndex) : nil
        if hasRelease { extraIndex += 1 }
        let coverIndex: Int32? = hasCover ? Int32(extraIndex) : nil

        while sqlite3_step(stmt) == SQLITE_ROW {
            let mapIndex = listIDs[sqlite3_column_int64(stmt, 0)]
            guard let mapIndex else { continue }
            let media = MediaType(rawValue: text(stmt, 1)) ?? .movie
            let subject = text(stmt, 2)
            let record = records[subject]
            let title = text(stmt, 3)
            let itemIsRead: Bool
            if let statusIndex {
                itemIsRead = text(stmt, statusIndex) == "done"
            } else {
                itemIsRead = record?.status == .done
            }
            let duration: Int? = durationIndex.map { Int(sqlite3_column_int64(stmt, $0)) }.flatMap { value in
                value > 0 ? value : nil
            } ?? record?.durationMinutes
            let pages: Int? = pagesIndex.map { Int(sqlite3_column_int64(stmt, $0)) }.flatMap { value in
                value > 0 ? value : nil
            } ?? record?.pages
            let words: Int? = wordsIndex.map { Int(sqlite3_column_int64(stmt, $0)) }.flatMap { value in
                value > 0 ? value : nil
            } ?? record?.wordCount
            let year: String? = yearIndex.map { text(stmt, $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? record?.year
            let releaseDate: String? = releaseIndex.map { text(stmt, $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? record?.releaseDate
            let coverURL = coverIndex.map { text(stmt, $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? record?.coverURL
            result.append(
                DoulistItem(
                    doulistID: mapIndex,
                    mediaType: media,
                    title: title,
                    subjectID: subject,
                    isRead: itemIsRead,
                    art: record?.art ?? art(for: media, subjectID: subject, title: title),
                    durationMinutes: duration,
                    pages: pages,
                    wordCount: words,
                    year: year,
                    releaseDate: releaseDate,
                    coverURL: coverURL,
                    rating: Int(sqlite3_column_int64(stmt, 5)),
                    comment: text(stmt, 6).isEmpty ? nil : text(stmt, 6),
                    intro: text(stmt, 7).isEmpty ? nil : text(stmt, 7),
                    createdAt: parseDate(text(stmt, 8))
                )
            )
        }
        return result
    }

    private static func readPlanFolders(_ db: OpaquePointer) throws -> [PlanFolder] {
        let stmt = try prepare(db, """
        SELECT id, media_type, title, note, position, created_at, deleted_at
        FROM plan_folders ORDER BY position, id
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [PlanFolder] = []
        var index = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let media = MediaType(rawValue: text(stmt, 1)) ?? .movie
            result.append(
                PlanFolder(
                    id: stableUUID(prefix: "2", index: index),
                    title: text(stmt, 2),
                    mediaType: media,
                    note: text(stmt, 3),
                    arts: [],
                    itemCount: 0,
                    readCount: 0,
                    createdAt: parseDate(text(stmt, 5)) ?? Date(),
                    deletedAt: parseDate(text(stmt, 6))
                )
            )
            index += 1
        }
        return result
    }

    private static func readPlanItems(_ db: OpaquePointer, records: [String: MediaRecord]) throws -> [PlanItem] {
        let hasStatus = hasColumn(db, "plan_items", "status")
        let hasRelease = hasColumn(db, "plan_items", "release_date")
        let extra = (hasStatus ? ", status" : "") + (hasRelease ? ", release_date" : "")
        let stmt = try prepare(db, """
        SELECT folder_id, media_type, subject_id, title, position, source, source_id, note, deleted_at\(extra)
        FROM plan_items ORDER BY folder_id, position, id
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [PlanItem] = []
        let folderStmt = try prepare(db, "SELECT id FROM plan_folders ORDER BY position, id")
        var folderIDsOrdered: [Int64] = []
        while sqlite3_step(folderStmt) == SQLITE_ROW {
            folderIDsOrdered.append(sqlite3_column_int64(folderStmt, 0))
        }
        sqlite3_finalize(folderStmt)
        var folderIDs: [Int64: UUID] = [:]
        for (index, id) in folderIDsOrdered.enumerated() {
            folderIDs[id] = stableUUID(prefix: "2", index: index)
        }
        var extraIndex = 9
        let statusIndex: Int32? = hasStatus ? Int32(extraIndex) : nil
        if hasStatus { extraIndex += 1 }
        let releaseIndex: Int32? = hasRelease ? Int32(extraIndex) : nil

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let folderID = folderIDs[sqlite3_column_int64(stmt, 0)] else { continue }
            let media = MediaType(rawValue: text(stmt, 1)) ?? .movie
            let subject = text(stmt, 2)
            let record = records[subject]
            let title = text(stmt, 3)
            let itemIsRead: Bool
            if let statusIndex {
                itemIsRead = text(stmt, statusIndex) == "done"
            } else {
                itemIsRead = record?.status == .done
            }
            let releaseDate = releaseIndex.map { text(stmt, $0) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? record?.releaseDate
            result.append(
                PlanItem(
                    folderID: folderID,
                    mediaType: media,
                    title: title,
                    subjectID: subject,
                    isRead: itemIsRead,
                    art: record?.art ?? art(for: media, subjectID: subject, title: title),
                    statsText: record?.statsText ?? "",
                    position: Int(sqlite3_column_int64(stmt, 4)),
                    coverURL: record?.coverURL,
                    releaseDate: releaseDate,
                    deletedAt: parseDate(text(stmt, 8)),
                    source: text(stmt, 5).isEmpty ? nil : text(stmt, 5),
                    sourceID: text(stmt, 6).isEmpty ? nil : text(stmt, 6),
                    note: text(stmt, 7)
                )
            )
        }
        return result
    }

    // MARK: SQLite helpers

    private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw CloudSyncError.writeFailed(L10n.Cloud.openDatabaseFailed(result))
        }
        return handle
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? L10n.Cloud.sqliteFailed
            sqlite3_free(error)
            throw CloudSyncError.writeFailed(message)
        }
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw dbError(db)
        }
        return stmt
    }

    private static func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private static func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int) {
        sqlite3_bind_int64(stmt, index, Int64(value))
    }

    private static func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    private static func text(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: value)
    }

    private static func scalar(_ db: OpaquePointer, _ sql: String) -> Int {
        guard let stmt = try? prepare(db, sql) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func integrityCheck(_ db: OpaquePointer) throws -> Bool {
        let stmt = try prepare(db, "PRAGMA integrity_check")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return text(stmt, 0) == "ok"
    }

    private static func integrityCheck(_ url: URL) throws -> Bool {
        let db = try open(url, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(db) }
        return try integrityCheck(db)
    }

    private static func tableNames(_ db: OpaquePointer) -> [String] {
        guard let stmt = try? prepare(db, "SELECT name FROM sqlite_master WHERE type='table'") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(text(stmt, 0)) }
        return result
    }

    private static func hasColumn(_ db: OpaquePointer, _ table: String, _ column: String) -> Bool {
        guard let stmt = try? prepare(db, "PRAGMA table_info(\(table))") else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if text(stmt, 1) == column { return true }
        }
        return false
    }

    private static func hasTable(_ db: OpaquePointer, _ name: String) -> Bool {
        tableNames(db).contains(name)
    }

    private static func dbError(_ db: OpaquePointer) -> CloudSyncError {
        CloudSyncError.writeFailed(String(cString: sqlite3_errmsg(db)))
    }

    private static func doubanID(fromStored value: String) -> String? {
        guard !value.isEmpty,
              !value.hasPrefix("ios-local-"),
              UUID(uuidString: value) == nil else { return nil }
        return value
    }

    private static func stableUUID(prefix: String, index: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%@%011d", prefix, index))") ?? UUID()
    }

    private static func parseDate(_ raw: String) -> Date? {
        if raw.isEmpty { return nil }
        if let date = isoFormatter.date(from: raw) { return date }
        if let date = secondFormatter.date(from: raw) { return date }
        if let date = dayFormatter.date(from: raw) { return date }
        return nil
    }

    private static func doubanURL(for media: MediaType, subjectID: String) -> String {
        guard !subjectID.isEmpty else { return "" }
        let host = media == .movie ? "movie" : "book"
        return "https://\(host).douban.com/subject/\(subjectID)/"
    }

    private static func art(for media: MediaType, subjectID: String, title: String) -> PosterArt {
        let seed = subjectID.isEmpty ? title : subjectID
        let hash = seed.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value }
        let options: [PosterArt] = media == .movie
            ? [.war, .space, .road, .dunes, .mountains, .sea, .bokeh, .forest, .city, .nebula, .anime, .volcano, .stage]
            : [.bookCream, .bookViolet, .bookSand, .bookIvory, .bookCharcoal, .bookSage, .bookTeal]
        return options[Int(hash % UInt32(options.count))]
    }
}
