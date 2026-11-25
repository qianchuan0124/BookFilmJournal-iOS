import Foundation
import CryptoKit

enum DoubanSyncMode: String, CaseIterable, Identifiable {
    case incrementalSync
    case incrementalAdd
    case full

    var id: String { rawValue }
    var label: String {
        switch self {
        case .incrementalSync: L10n.Sync.modeIncrementalSync
        case .incrementalAdd: L10n.Sync.modeIncrementalAdd
        case .full: L10n.Sync.modeFull
        }
    }
    var note: String {
        switch self {
        case .incrementalSync: L10n.Sync.modeNoteIncrementalSync
        case .incrementalAdd: L10n.Sync.modeNoteIncrementalAdd
        case .full: L10n.Sync.modeNoteFull
        }
    }
}

enum DoubanSyncScope: String, CaseIterable, Identifiable {
    case movieDone
    case movieWish
    case bookDone
    case bookWish

    var id: String { rawValue }
    var media: MediaType {
        switch self {
        case .movieDone, .movieWish: .movie
        case .bookDone, .bookWish: .book
        }
    }
    var status: RecordStatus {
        switch self {
        case .movieDone, .bookDone: .done
        case .movieWish, .bookWish: .wish
        }
    }
    var label: String {
        switch self {
        case .movieDone: L10n.Records.movieRecords
        case .movieWish: L10n.Records.movieWish
        case .bookDone: L10n.Records.bookRecords
        case .bookWish: L10n.Records.bookWish
        }
    }
}

struct DoubanSyncResult {
    var added = 0
    var updated = 0
    var removed = 0
    var mediaCount = 0
    var doulists = 0
    var doulistItems = 0
    var completedAt = Date()
}

enum DoubanSyncError: LocalizedError {
    case emptyID
    case loginRequired
    case noRecords(String)
    case http(Int)
    case parse

    var errorDescription: String? {
        switch self {
        case .emptyID: L10n.Sync.errorEmptyId
        case .loginRequired: L10n.Sync.errorLoginRequired
        case .noRecords(let user): L10n.Sync.errorNoRecords(user)
        case .http(let code): L10n.Sync.errorHttp(String(describing: code))
        case .parse: L10n.Sync.errorParse
        }
    }
}

@MainActor
enum DoubanSyncService {
    private struct RemoteRecord {
        var media: MediaType
        var status: RecordStatus
        var subjectID: String
        var title: String
        var url: String
        var rating: Int
        var date: Date
        var comment: String
        var intro: String
        var coverURL: String?
        var releaseDate: String?
        var durationMinutes: Int?
        var pages: Int?
        var wordCount: Int?
        var year: String?
    }

    private static func log(_ message: String) {
        NSLog("[DoubanSync] %@", message)
    }

    static func sync(
        userID: String,
        cookie: String?,
        scopes: [DoubanSyncScope],
        syncDoulists: Bool,
        mode: DoubanSyncMode,
        store: LibraryStore,
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> DoubanSyncResult {
        let user = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { throw DoubanSyncError.emptyID }
        guard !scopes.isEmpty || syncDoulists else { throw DoubanSyncError.noRecords(user) }

        log("start user=\(user) scopes=\(scopes.map(\.rawValue)) doulists=\(syncDoulists)")
        progress?(0, L10n.Sync.progressPrepare)
        var remote: [RemoteRecord] = []
        let steps = max(1, scopes.count + (syncDoulists ? 1 : 0))
        var step = 0
        for scope in scopes {
            let media = scope.media
            let status = scope.status
            let records = try await fetchCollection(
                user: user,
                cookie: cookie,
                media: media,
                status: status,
                progress: { fetched, total in
                    let fraction = total > 0 ? min(1, Double(fetched) / Double(total)) : 1
                    let overall = (Double(step) + fraction) / Double(steps)
                    progress?(min(0.99, overall), "\(scope.label) \(fetched)/\(max(total, fetched))")
                }
            )
            remote.append(contentsOf: records)
            log("scope \(scope.rawValue) fetched=\(records.count)")
            step += 1
        }

        if !remote.isEmpty {
            progress?(min(0.99, Double(step) / Double(steps)), L10n.Sync.progressDetails)
            remote = await enrichRemoteRecords(remote, cookie: cookie, progress: progress)
        }

        var result = DoubanSyncResult()
        if !remote.isEmpty {
            progress?(min(0.99, Double(step) / Double(steps)), L10n.Sync.progressWrite)
            result = merge(remote: remote, mode: mode, scopes: scopes, store: store)
        } else if !syncDoulists {
            throw DoubanSyncError.noRecords(user)
        }

        if syncDoulists {
            progress?(min(0.99, Double(step) / Double(steps)), L10n.Sync.progressDoulists)
            let doulistResult = try await syncUserDoulists(
                user: user,
                cookie: cookie,
                store: store,
                progress: { value, text in
                    let overall = (Double(step) + value) / Double(steps)
                    progress?(min(0.99, overall), text)
                }
            )
            result.doulists = doulistResult.0
            result.doulistItems = doulistResult.1
        }

        propagateRecordMetadata(in: store)
        progress?(1, L10n.Sync.progressCovers)
        await CoverStore.download(records: store.records, mediaTypes: Set(remote.map(\.media))) { done, total in
            progress?(0.99, L10n.Sync.progressCoverCache(String(describing: done), String(describing: total)))
        }
        return result
    }

    static func userID(fromCookie cookie: String?) -> String? {
        guard let cookie, !cookie.isEmpty else { return nil }
        let pattern = #"dbcl2\s*=\s*"?([0-9]{3,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cookie, range: NSRange(cookie.startIndex..., in: cookie)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: cookie) else { return nil }
        return String(cookie[range])
    }

    private static func syncUserDoulists(
        user: String,
        cookie: String?,
        store: LibraryStore,
        progress: ((Double, String) -> Void)?
    ) async throws -> (Int, Int) {
        var remoteDoulists: [(id: String, isFollowing: Bool, value: [String: Any])] = []
        for endpoint in ["following_doulists", "owned_doulists"] {
            let isFollowing = endpoint == "following_doulists"
            var start = 0
            var total = Int.max
            var page = 0
            while start < total && page < 30 {
                guard let url = URL(string: "https://m.douban.com/rexxar/api/v2/user/\(user)/\(endpoint)?start=\(start)&count=50&ck=&for_mobile=1") else { break }
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
                if let cookie, !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { break }
                log("doulists endpoint=\(endpoint) start=\(start) status=\(http.statusCode) bytes=\(data.count)")
                if http.statusCode == 401 || http.statusCode == 403 { throw DoubanSyncError.loginRequired }
                if http.statusCode == 404 { break }
                guard (200..<300).contains(http.statusCode),
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let raw = object["doulists"] as? [[String: Any]] else {
                    log("doulists parse failed endpoint=\(endpoint) body=\(String(decoding: data.prefix(160), as: UTF8.self))")
                    break
                }
                log("doulists parsed endpoint=\(endpoint) count=\(raw.count) total=\(object["total"] ?? "nil")")
                total = intValue(object["total"]) ?? raw.count
                for value in raw {
                    if let id = stringValue(value["id"]), !id.isEmpty {
                        remoteDoulists.append((id, isFollowing, value))
                    }
                }
                if raw.isEmpty { break }
                start += max(max(intValue(object["count"]) ?? raw.count, raw.count), 1)
                page += 1
                try await Task.sleep(for: .milliseconds(160))
            }
        }

        let knownIDs = Set(remoteDoulists.map(\.id))
        let htmlOwned = try await fetchOwnedDoulistsFromHTML(user: user, cookie: cookie, known: knownIDs)
        remoteDoulists.append(contentsOf: htmlOwned)

        let fetchedIDs = Set(remoteDoulists.map(\.id))
        for known in store.doulists where !known.isFollowing {
            guard let doubanID = known.doubanID, !fetchedIDs.contains(doubanID) else { continue }
            log("owned doulist fallback id=\(doubanID) title=\(known.title)")
            remoteDoulists.append((doubanID, false, [
                "id": doubanID,
                "title": known.title,
                "category": known.mediaType.rawValue
            ]))
        }

        var itemTotal = 0
        for (index, remote) in remoteDoulists.enumerated() {
            progress?(Double(index) / Double(max(1, remoteDoulists.count)), "同步豆列 \(index + 1)/\(remoteDoulists.count)")
            let media: MediaType = (stringValue(remote.value["category"]) == "book") ? .book : .movie
            let title = stringValue(remote.value["title"]) ?? "未命名豆列"
            let listID = stableUUID("doulist-\(remote.id)")
            var doulist = Doulist(
                id: listID,
                title: title,
                doubanID: remote.id,
                mediaType: media,
                isFollowing: remote.isFollowing,
                isPublic: !(remote.value["is_private"] as? Bool ?? false),
                itemCount: intValue(remote.value["items_count"]) ?? 0,
                readCount: 0,
                arts: [],
                updatedAt: Date()
            )
            let normalizedTitle = title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let globalIndex = store.doulists.firstIndex {
                if $0.id == listID { return true }
                if let existingID = $0.doubanID, !existingID.isEmpty {
                    return existingID == remote.id
                }
                guard $0.mediaType == media else { return false }
                let existingTitle = $0.title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                    .lowercased()
                return existingTitle == normalizedTitle
            }
            if let globalIndex {
                doulist.id = store.doulists[globalIndex].id
                doulist.readCount = store.doulists[globalIndex].readCount
                doulist.deletedAt = store.doulists[globalIndex].deletedAt
                store.doulists[globalIndex] = doulist
            } else {
                store.doulists.append(doulist)
            }

            let isCollection = !remote.id.allSatisfy(\.isNumber)
            let items = try await fetchDoulistItems(
                doubanID: remote.id,
                doulistID: doulist.id,
                media: media,
                isCollection: isCollection,
                cookie: cookie
            )
            let existing = store.doulistItems.filter { $0.doulistID == doulist.id }
            if items.isEmpty && !existing.isEmpty {
                log("doulist items empty, keep existing id=\(remote.id) count=\(existing.count)")
                itemTotal += existing.count
                continue
            }
            var bySubject = Dictionary(existing.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
            var merged: [DoulistItem] = []
            for var item in items {
                let exact = store.records.first {
                    $0.subjectID == item.subjectID && $0.mediaType == item.mediaType && !$0.isDeleted
                }
                let readEdition = readEdition(of: item, in: store.records)
                let record = readEdition ?? exact
                if let old = bySubject[item.subjectID] {
                    item.id = old.id
                    item.isRead = old.isRead || readEdition != nil || exact?.status == .done
                    item.durationMinutes = item.durationMinutes ?? old.durationMinutes ?? record?.durationMinutes
                    item.pages = item.pages ?? old.pages ?? record?.pages
                    item.wordCount = item.wordCount ?? old.wordCount ?? record?.wordCount
                    item.year = old.year ?? record?.year
                    item.releaseDate = item.releaseDate ?? old.releaseDate ?? record?.releaseDate
                    item.coverURL = item.coverURL ?? old.coverURL ?? record?.coverURL
                } else if let record {
                    item.isRead = record.status == .done
                    item.durationMinutes = item.durationMinutes ?? record.durationMinutes
                    item.pages = item.pages ?? record.pages
                    item.wordCount = record.wordCount
                    item.year = item.year ?? record.year
                    item.releaseDate = item.releaseDate ?? record.releaseDate
                    item.coverURL = item.coverURL ?? record.coverURL
                } else {
                    item.isRead = false
                }
                merged.append(item)
                bySubject[item.subjectID] = item
            }
            if !existing.isEmpty {
                let oldOrder = existing.map(\.subjectID)
                let oldIDs = Set(oldOrder)
                let mergedByID = Dictionary(merged.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
                var ordered = oldOrder.compactMap { mergedByID[$0] }
                ordered.append(contentsOf: merged.filter { !oldIDs.contains($0.subjectID) })
                merged = ordered
            }

            for item in merged {
                for planIndex in store.planItems.indices where store.planItems[planIndex].subjectID == item.subjectID {
                    if store.planItems[planIndex].statsText.isEmpty
                        || store.planItems[planIndex].statsText.contains("未设置")
                        || store.planItems[planIndex].statsText.contains("未统计") {
                        store.planItems[planIndex].statsText = item.statsText
                    }
                    if store.planItems[planIndex].coverURL == nil { store.planItems[planIndex].coverURL = item.coverURL }
                    if store.planItems[planIndex].releaseDate == nil { store.planItems[planIndex].releaseDate = item.releaseDate }
                }
            }
            store.doulistItems.removeAll { $0.doulistID == doulist.id }
            store.doulistItems.append(contentsOf: merged)
            itemTotal += merged.count
            if let index = store.doulists.firstIndex(where: { $0.id == doulist.id }) {
                store.doulists[index].itemCount = merged.count
                store.doulists[index].readCount = merged.filter(\.isRead).count
                store.doulists[index].arts = Array(merged.prefix(4).map(\.art))
            }
            store.save()
        }
        log("doulist sync done lists=\(remoteDoulists.count) items=\(itemTotal)")
        store.deduplicateDoulists()
        store.normalizeDoulistMediaTypes()
        store.ensureShadowRecords()
        store.save()
        await CoverStore.download(doulistItems: store.doulistItems) { done, total in
            progress?(0.99, "缓存豆列封面 \(done)/\(total)")
        }
        return (remoteDoulists.count, itemTotal)
    }

    private static func fetchOwnedDoulistsFromHTML(
        user: String,
        cookie: String?,
        known: Set<String>
    ) async throws -> [(id: String, isFollowing: Bool, value: [String: Any])] {
        guard let cookie, !cookie.isEmpty else { return [] }
        let urls = [
            "https://www.douban.com/people/\(user)/doulists?start=0&sort=time&type=all",
            "https://www.douban.com/people/\(user)/doulists",
            "https://m.douban.com/people/\(user)/doulists?start=0",
            "https://m.douban.com/people/\(user)/doulists"
        ]
        var result: [(String, Bool, [String: Any])] = []
        var seen = known
        for value in urls {
            guard let url = URL(string: value) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let isMobile = value.contains("m.douban.com")
            request.setValue(isMobile ? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15" : "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://www.douban.com/people/\(user)/", forHTTPHeaderField: "Referer")
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                log("owned doulists HTML url=\(value) status=\(code) bytes=\(data.count)")
                guard (200..<300).contains(code) else { continue }
                let html = String(decoding: data, as: UTF8.self)
                let links = parseDoulistLinks(html)
                log("owned doulists HTML parsed=\(links.count)")
                if links.isEmpty {
                    let body = html.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    log("owned doulists HTML body=\(String(body.prefix(260)))")
                }
                for link in links where !seen.contains(link.id) {
                    seen.insert(link.id)
                    result.append((link.id, false, [
                        "id": link.id,
                        "title": link.title,
                        "category": "movie"
                    ]))
                }
                if !result.isEmpty { break }
            } catch {
                log("owned doulists HTML error=\(error.localizedDescription)")
            }
        }
        return result
    }

    private static func parseDoulistLinks(_ html: String) -> [(id: String, title: String)] {
        let pattern = #"<a[^>]+href="[^"]*/(?:doulist|subject_collection)/([0-9A-Za-z]+)/?[^"]*"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        var seen = Set<String>()
        var result: [(String, String)] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 2,
                  let idRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let id = String(html[idRange])
            let raw = String(html[titleRange])
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, id != "new", !raw.isEmpty, !["豆列", "片单", "书单", "全部"].contains(raw), !seen.contains(id) else { continue }
            seen.insert(id)
            result.append((id, raw))
        }
        return result
    }

    private static func fetchDoulistItems(
        doubanID: String,
        doulistID: UUID,
        media: MediaType,
        isCollection: Bool,
        cookie: String?
    ) async throws -> [DoulistItem] {
        var result: [DoulistItem] = []
        var start = 0
        var total = Int.max
        var page = 0
        while start < total && page < 30 {
            let path = isCollection ? "subject_collection" : "doulist"
            guard let url = URL(string: "https://m.douban.com/rexxar/api/v2/\(path)/\(doubanID)/items?start=\(start)&count=20&ck=&for_mobile=1") else { break }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            if let cookie, !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { break }
            log("doulist items id=\(doubanID) collection=\(isCollection) start=\(start) status=\(http.statusCode) bytes=\(data.count)")
            if http.statusCode == 401 || http.statusCode == 403 { throw DoubanSyncError.loginRequired }
            let itemKey = isCollection ? "subject_collection_items" : "items"
            guard (200..<300).contains(http.statusCode),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let raw = object[itemKey] as? [[String: Any]] else {
                log("doulist items parse failed id=\(doubanID) body=\(String(decoding: data.prefix(160), as: UTF8.self))")
                break
            }
            total = intValue(object["total"]) ?? raw.count
            for value in raw {
                let subjectValue = isCollection ? value["id"] : value["target_id"]
                guard let subjectID = stringValue(subjectValue), !subjectID.isEmpty,
                      let title = stringValue(value["title"]), !title.isEmpty else { continue }
                let itemMedia: MediaType = stringValue(value["type"]) == "book" ? .book : media
                let intro = isCollection
                    ? (stringValue(value["card_subtitle"]) ?? stringValue(value["description"]) ?? "")
                    : (stringValue(value["subtitle"]) ?? "")
                let year = intro.range(of: #"(19|20)\d{2}"#, options: .regularExpression).map { String(intro[$0]) }
                result.append(
                    DoulistItem(
                        doulistID: doulistID,
                        mediaType: itemMedia,
                        title: title,
                        subjectID: subjectID,
                        isRead: false,
                        art: placeholderArt(media: itemMedia, subjectID: subjectID, title: title),
                        durationMinutes: durationMinutes(from: intro),
                        pages: pages(from: intro),
                        year: year,
                        releaseDate: releaseDate(from: intro),
                        coverURL: stringValue(value["cover_url"])
                    )
                )
            }
            if raw.isEmpty { break }
            start += max(max(intValue(object["count"]) ?? raw.count, raw.count), 1)
            page += 1
            try await Task.sleep(for: .milliseconds(160))
        }
        return await enrichDoulistItems(result, cookie: cookie)
    }

    private static func propagateRecordMetadata(in store: LibraryStore) {
        var bySubject: [String: MediaRecord] = [:]
        for record in store.records where !record.isDeleted {
            bySubject[record.subjectID] = record
        }
        var changed = false
        for index in store.doulistItems.indices {
            guard let record = bySubject[store.doulistItems[index].subjectID] else { continue }
            var item = store.doulistItems[index]
            if item.pages == nil, let pages = record.pages { item.pages = pages; changed = true }
            if item.wordCount == nil, let words = record.wordCount { item.wordCount = words; changed = true }
            if item.durationMinutes == nil, let duration = record.durationMinutes { item.durationMinutes = duration; changed = true }
            if item.releaseDate == nil, let release = record.releaseDate { item.releaseDate = release; changed = true }
            if item.year == nil, let year = record.year { item.year = year; changed = true }
            store.doulistItems[index] = item
        }
        for index in store.planItems.indices {
            guard let record = bySubject[store.planItems[index].subjectID] else { continue }
            var item = store.planItems[index]
            if item.statsText.contains("未统计") || item.statsText.isEmpty {
                item.statsText = record.statsText
                changed = true
            }
            if item.releaseDate == nil, let release = record.releaseDate { item.releaseDate = release; changed = true }
            store.planItems[index] = item
        }
        for item in store.doulistItems where item.title.contains("卡拉马佐夫") || item.title.contains("刀锋") {
            let pages = bySubject[item.subjectID]?.pages.map(String.init) ?? "-"
            let itemPages = item.pages.map(String.init) ?? "-"
            log("metadata item=\(item.title) subject=\(item.subjectID) pages=\(itemPages) recordPages=\(pages)")
        }
        if changed { store.save() }
    }

    private static func enrichRemoteRecords(_ records: [RemoteRecord], cookie: String?, progress: ((Double, String) -> Void)?) async -> [RemoteRecord] {
        var result = records
        let candidates = records.indices.filter { index in
            let record = records[index]
            if record.media == .book {
                return record.pages == nil || record.wordCount == nil
            }
            return record.durationMinutes == nil || (record.releaseDate ?? "").isEmpty
        }
        guard !candidates.isEmpty else { return result }
        log("enrich records=\(candidates.count)")
        for start in stride(from: 0, to: candidates.count, by: 2) {
            let end = min(start + 2, candidates.count)
            await withTaskGroup(of: (Int, SubjectDetailMeta?).self) { group in
                for index in candidates[start..<end] {
                    let record = records[index]
                    group.addTask {
                        (index, await SubjectDetailService.fetchSummary(subjectID: record.subjectID, media: record.media, cookie: cookie, debug: { log($0) }))
                    }
                }
                for await (index, meta) in group {
                    guard let meta else { continue }
                    if let duration = meta.durationMinutes { result[index].durationMinutes = duration }
                    if let pages = meta.pages { result[index].pages = pages }
                    if let wordCount = meta.wordCount { result[index].wordCount = wordCount }
                    if let year = meta.year { result[index].year = result[index].year ?? year }
                    if let release = meta.releaseDate { result[index].releaseDate = result[index].releaseDate ?? release }
                    if let cover = meta.coverURL, result[index].coverURL == nil { result[index].coverURL = cover }
                }
            }
            let done = min(end, candidates.count)
            progress?(Double(done) / Double(candidates.count), "补全详情 \(done)/\(candidates.count)")
            try? await Task.sleep(for: .milliseconds(120))
        }
        return result
    }

    private static func enrichDoulistItems(_ items: [DoulistItem], cookie: String?) async -> [DoulistItem] {
        var result = items
        let candidates = items.indices.filter { index in
            let item = items[index]
            return (item.coverURL ?? "").isEmpty
                || (item.releaseDate ?? "").isEmpty
                || (item.mediaType == .movie && item.durationMinutes == nil)
                || (item.mediaType == .book && item.pages == nil)
        }
        log("doulist items=\(items.count) withDuration=\(items.filter { $0.durationMinutes != nil }.count) withRelease=\(items.filter { ($0.releaseDate ?? "").isEmpty == false }.count) candidates=\(candidates.count)")
        guard !candidates.isEmpty else { return result }
        log("enrich doulist items=\(candidates.count)")
        for start in stride(from: 0, to: candidates.count, by: 2) {
            let end = min(start + 2, candidates.count)
            await withTaskGroup(of: (Int, SubjectDetailMeta?).self) { group in
                for index in candidates[start..<end] {
                    let item = items[index]
                    group.addTask {
                        (index, await SubjectDetailService.fetchSummary(subjectID: item.subjectID, media: item.mediaType, cookie: cookie, debug: { log($0) }))
                    }
                }
                for await (index, meta) in group {
                    let item = items[index]
                    log("enrich detail id=\(item.subjectID) media=\(item.mediaType.rawValue) meta=\(meta != nil) duration=\(meta?.durationMinutes ?? -1) pages=\(meta?.pages ?? -1) release=\(meta?.releaseDate ?? "-")")
                    guard let meta else { continue }
                    if let cover = meta.coverURL, !cover.isEmpty { result[index].coverURL = cover }
                    if let duration = meta.durationMinutes { result[index].durationMinutes = duration }
                    if let pages = meta.pages { result[index].pages = pages }
                    if let wordCount = meta.wordCount { result[index].wordCount = wordCount }
                    if let year = meta.year { result[index].year = result[index].year ?? year }
                    if let release = meta.releaseDate { result[index].releaseDate = release }
                }
            }
            try? await Task.sleep(for: .milliseconds(180))
        }
        return result
    }

    private static func durationMinutes(from text: String) -> Int? {
        guard let range = text.range(of: #"\d+\s*分钟"#, options: .regularExpression) else { return nil }
        return Int(text[range].filter(\.isNumber))
    }

    private static func pages(from text: String) -> Int? {
        guard let range = text.range(of: #"\d+\s*页"#, options: .regularExpression) else { return nil }
        return Int(text[range].filter(\.isNumber))
    }

    private static func releaseDate(from text: String) -> String? {
        if let range = text.range(of: #"\d{4}-\d{1,2}-\d{1,2}"#, options: .regularExpression) {
            return String(text[range])
        }
        if let range = text.range(of: #"(19|20)\d{2}"#, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    static func stableID(forDoubanDoulistID id: String) -> UUID {
        stableUUID("doulist-\(id)")
    }

    private static func stableUUID(_ value: String) -> UUID {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        let b = Array(digest.prefix(16))
        return UUID(uuid: (
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
        ))
    }

    private static func fetchCollection(
        user: String,
        cookie: String?,
        media: MediaType,
        status: RecordStatus,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [RemoteRecord] {
        let apiStatus = status == .done ? "done" : "mark"
        var result: [RemoteRecord] = []
        var start = 0
        var total = Int.max
        var page = 0
        while start < total && page < 30 {
            guard let url = URL(string: "https://m.douban.com/rexxar/api/v2/user/\(user)/interests?type=\(media.rawValue)&status=\(apiStatus)&start=\(start)&count=50&ck=&for_mobile=1") else {
                throw DoubanSyncError.parse
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            if let cookie, !cookie.isEmpty {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DoubanSyncError.parse }
            guard (200..<300).contains(http.statusCode) else { throw DoubanSyncError.http(http.statusCode) }
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                let text = String(decoding: data, as: UTF8.self)
                if text.contains("登录") || text.contains("login") || text.contains("permission") || text.contains("验证") {
                    throw DoubanSyncError.loginRequired
                }
                throw DoubanSyncError.parse
            }
            guard let rawInterests = object["interests"] as? [[String: Any]] else {
                let text = String(decoding: data, as: UTF8.self)
                if text.contains("登录") || text.contains("login") || text.contains("permission") || text.contains("验证") {
                    throw DoubanSyncError.loginRequired
                }
                throw DoubanSyncError.parse
            }
            total = intValue(object["total"]) ?? 0
            if rawInterests.isEmpty {
                progress?(result.count, total)
                break
            }
            var decodedCount = 0
            for raw in rawInterests {
                if let record = makeRemote(interest: raw, media: media, status: status) {
                    result.append(record)
                    decodedCount += 1
                }
            }
            guard decodedCount > 0 else { throw DoubanSyncError.parse }
            let advance = max(intValue(object["count"]) ?? 0, rawInterests.count, 1)
            start += advance
            progress?(result.count, total)
            page += 1
            try await Task.sleep(for: .milliseconds(160))
        }
        return result
    }

    private static func makeRemote(interest: [String: Any], media: MediaType, status: RecordStatus) -> RemoteRecord? {
        guard let subject = interest["subject"] as? [String: Any],
              let subjectID = stringValue(subject["id"]), !subjectID.isEmpty,
              let title = stringValue(subject["title"]), !title.isEmpty else {
            return nil
        }
        let date = parseDate(stringValue(interest["create_time"]) ?? "") ?? Date()
        let ratingObject = interest["rating"] as? [String: Any]
        let rating = status == .done ? Int((doubleValue(ratingObject?["value"]) ?? 0).rounded()) : 0
        let host = media == .movie ? "movie" : "book"
        let url = stringValue(subject["url"]).flatMap { $0.isEmpty ? nil : $0 }
            ?? "https://\(host).douban.com/subject/\(subjectID)/"
        return RemoteRecord(
            media: media,
            status: status,
            subjectID: subjectID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url,
            rating: max(0, min(5, rating)),
            date: date,
            comment: stringValue(interest["comment"]) ?? "",
            intro: stringValue(subject["card_subtitle"]) ?? "",
            coverURL: stringValue(subject["cover_url"]) ?? (subject["pic"] as? [String: Any]).flatMap { stringValue($0["large"]) },
            releaseDate: subjectReleaseDate(subject),
            durationMinutes: nil,
            pages: nil,
            wordCount: nil,
            year: stringValue(subject["year"])
        )
    }

    private static func subjectReleaseDate(_ subject: [String: Any]) -> String? {
        if let values = subject["pubdate"] as? [Any] {
            for value in values {
                let text = stringValue(value) ?? ""
                if let range = text.range(of: #"\d{4}-\d{1,2}-\d{1,2}"#, options: .regularExpression) {
                    return String(text[range])
                }
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func merge(remote: [RemoteRecord], mode: DoubanSyncMode, scopes: [DoubanSyncScope], store: LibraryStore) -> DoubanSyncResult {
        var result = DoubanSyncResult()
        var existingMap: [String: Int] = [:]
        for (index, record) in store.records.enumerated() {
            existingMap[key(record.mediaType, record.subjectID, record.status)] = index
        }
        for item in remote {
            if store.isIgnored(media: item.media, subjectID: item.subjectID) { continue }
            if store.isPurged(media: item.media, subjectID: item.subjectID, status: item.status) { continue }
            let itemKey = key(item.media, item.subjectID, item.status)
            if let index = existingMap[itemKey] {
                var existing = store.records[index]
                if existing.isDeleted {
                    guard existing.deleteSource == .sync else { continue }
                    existing.deletedAt = nil
                    existing.deleteSource = nil
                }
                if mode == .incrementalAdd {
                    if existing.localCover != true, let cover = item.coverURL, !cover.isEmpty {
                        existing.coverURL = cover
                        store.records[index] = existing
                    }
                    continue
                }
                if !existing.isLocalEdited {
                    existing.title = item.title
                    existing.doubanURL = item.url
                    existing.markedDate = item.date
                    existing.effectiveDate = item.date
                    existing.rating = item.rating
                    existing.comment = item.comment
                    existing.intro = item.intro
                    if let duration = item.durationMinutes { existing.durationMinutes = duration }
                    if let pages = item.pages { existing.pages = pages }
                    if let wordCount = item.wordCount { existing.wordCount = wordCount }
                    if let year = item.year { existing.year = year }
                    if let release = item.releaseDate { existing.releaseDate = release }
                } else {
                    if existing.durationMinutes == nil, let duration = item.durationMinutes { existing.durationMinutes = duration }
                    if existing.pages == nil, let pages = item.pages { existing.pages = pages }
                    if existing.wordCount == nil, let wordCount = item.wordCount { existing.wordCount = wordCount }
                    if existing.year == nil, let year = item.year { existing.year = year }
                    if existing.releaseDate == nil, let release = item.releaseDate { existing.releaseDate = release }
                }
                if existing.localCover != true, let cover = item.coverURL, !cover.isEmpty { existing.coverURL = cover }
                store.records[index] = existing
                result.updated += 1
            } else {
                let record = MediaRecord(
                    mediaType: item.media,
                    status: item.status,
                    title: item.title,
                    subjectID: item.subjectID,
                    doubanURL: item.url,
                    coverURL: item.coverURL,
                    art: placeholderArt(media: item.media, subjectID: item.subjectID, title: item.title),
                    markedDate: item.date,
                    effectiveDate: item.date,
                    rating: item.rating,
                    comment: item.comment,
                    intro: item.intro,
                    durationMinutes: item.durationMinutes,
                    pages: item.pages,
                    wordCount: item.wordCount,
                    year: item.year,
                    releaseDate: item.releaseDate
                )
                store.records.append(record)
                existingMap[itemKey] = store.records.count - 1
                result.added += 1
            }
        }

        let selectedMedia = Set(remote.map(\.media))
        let defaults = UserDefaults.standard
        for media in selectedMedia {
            for status in RecordStatus.allCases where scopes.contains(where: { $0.media == media && $0.status == status }) {
                let remoteIDs = Set(remote.filter { $0.media == media && $0.status == status }.map(\.subjectID))
                let previous = Set(defaults.stringArray(forKey: lastIDsKey(media, status)) ?? [])
                var index = 0
                while index < store.records.count {
                    var record = store.records[index]
                    guard record.mediaType == media, record.status == status, !record.isDeleted, record.isHidden != true else {
                        index += 1
                        continue
                    }
                    let shouldRemove: Bool
                    switch mode {
                    case .incrementalAdd:
                        shouldRemove = false
                    case .incrementalSync:
                        shouldRemove = previous.contains(record.subjectID) && !remoteIDs.contains(record.subjectID)
                    case .full:
                        shouldRemove = !remoteIDs.contains(record.subjectID)
                    }
                    if shouldRemove {
                        record.deletedAt = Date()
                        record.deleteSource = .sync
                        store.records[index] = record
                        result.removed += 1
                    }
                    index += 1
                }
                defaults.set(Array(remoteIDs), forKey: lastIDsKey(media, status))
            }
        }

        propagateCovers(in: store)
        store.save()
        result.mediaCount = remote.count
        result.completedAt = Date()
        defaults.set(result.completedAt.timeIntervalSince1970, forKey: "bookfilm.sync.lastTime")
        defaults.set("\(result.added)|\(result.updated)|\(result.removed)", forKey: "bookfilm.sync.lastSummary")
        return result
    }

    private static func propagateCovers(in store: LibraryStore) {
        var covers: [String: String] = [:]
        var local: Set<String> = []
        for record in store.records where !record.isDeleted {
            if record.localCover == true {
                local.insert(record.subjectID)
            } else if let cover = record.coverURL, !cover.isEmpty {
                covers[record.subjectID] = cover
            }
        }
        for index in store.doulistItems.indices {
            let subject = store.doulistItems[index].subjectID
            if local.contains(subject) {
                store.doulistItems[index].coverURL = nil
            } else if let cover = covers[subject] {
                store.doulistItems[index].coverURL = cover
            }
        }
        for index in store.planItems.indices {
            let subject = store.planItems[index].subjectID
            if local.contains(subject) {
                store.planItems[index].coverURL = nil
            } else if let cover = covers[subject] {
                store.planItems[index].coverURL = cover
            }
        }
    }

    private static func lastIDsKey(_ media: MediaType, _ status: RecordStatus) -> String {
        "bookfilm.sync.lastIDs.\(media.rawValue).\(status.rawValue)"
    }

    private static func readEdition(of item: DoulistItem, in records: [MediaRecord]) -> MediaRecord? {
        let target = normalizedTitle(item.title)
        guard target.count >= 2 else { return nil }
        return records.first { record in
            guard !record.isDeleted,
                  record.mediaType == item.mediaType,
                  record.status == .done else { return false }
            let title = normalizedTitle(record.title)
            guard !title.isEmpty else { return false }
            return title == target
                || (min(title.count, target.count) >= 4 && (title.contains(target) || target.contains(title)))
        }
    }

    private static func normalizedTitle(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || isCJK($0) }
            .map(String.init)
            .joined()
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    private static func key(_ media: MediaType, _ subject: String, _ status: RecordStatus) -> String {
        "\(media.rawValue)|\(subject)|\(status.rawValue)"
    }

    private static func parseDate(_ value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)
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
