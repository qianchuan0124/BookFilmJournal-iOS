import Foundation
import SwiftUI
import Observation
#if canImport(WebKit)
import WebKit
#endif

struct ExploreSite: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var urlString: String
    var searchURLTemplate: String?
    var kind: MediaType
    var isLocal: Bool

    var url: URL? { URL(string: urlString) }

    func searchURL(for title: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&?=#"))
        let encoded = title.addingPercentEncoding(withAllowedCharacters: allowed) ?? title
        guard let template = searchURLTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !template.isEmpty else {
            return url
        }
        var normalized = template
            .replacingOccurrences(of: "{query}", with: "{title}")
            .replacingOccurrences(of: "%s", with: "{title}")
        if normalized.contains("{title}") {
            return URL(string: normalized.replacingOccurrences(of: "{title}", with: encoded))
        }
        if normalized.hasSuffix("=") || normalized.hasSuffix("?") || normalized.hasSuffix("&") {
            normalized += "{title}"
            return URL(string: normalized.replacingOccurrences(of: "{title}", with: encoded))
        }
        guard var components = URLComponents(string: normalized) else { return url }
        if components.query == nil {
            components.query = "q=\(encoded)"
        } else {
            components.percentEncodedQuery = (components.percentEncodedQuery ?? "") + "&q=\(encoded)"
        }
        return components.url ?? url
    }
}

private struct RemoteExploreConfig: Codable {
    var version: Int
    var updatedAt: String?
    var movie: [RemoteSite]
    var book: [RemoteSite]

    struct RemoteSite: Codable {
        var name: String
        var url: String
        var searchUrl: String?
    }
}

@Observable
final class ExploreStore {
    var sites: [ExploreSite] = []
    var reachability: [UUID: Bool] = [:]
    var lastPulledAt: Date?
    var isPulling = false
    var isRefreshing = false
    var remoteVersion = 3
    var message: String?
    var lastConfigSourceName: String?

    private let defaultsKey = "bookfilm.explore.sites.v3"
    private let remoteSources = ExploreRemoteSources.load()

    var configSourceLabel: String {
        remoteSources.map(\.name).joined(separator: " / ")
    }

    init() {
        load()
        if sites.isEmpty {
            sites = Self.defaultSites
            lastPulledAt = Date()
            save()
        }
    }

    func replace(with restored: [ExploreSite]) {
        guard !restored.isEmpty else { return }
        sites = restored
        reachability = [:]
        lastPulledAt = Date()
        save()
    }

    func sites(for kind: MediaType) -> [ExploreSite] {
        sites.filter { $0.kind == kind }
    }

    var reachableCount: Int {
        sites.filter { reachability[$0.id] == true }.count
    }

    func isReachable(_ site: ExploreSite) -> Bool? {
        reachability[site.id]
    }

    func addLocalSite(name: String, urlString: String, searchURLTemplate: String?, kind: MediaType) {
        let site = ExploreSite(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
            searchURLTemplate: searchURLTemplate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            kind: kind,
            isLocal: true
        )
        sites.append(site)
        save()
    }

    func updateSite(id: UUID, name: String, urlString: String, searchURLTemplate: String?, kind: MediaType) {
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        sites[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sites[index].urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        sites[index].searchURLTemplate = searchURLTemplate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        sites[index].kind = kind
        reachability[id] = nil
        save()
    }

    func deleteSite(id: UUID) {
        sites.removeAll { $0.id == id }
        reachability[id] = nil
        save()
    }

    func moveSites(media: MediaType, from source: IndexSet, to destination: Int) {
        var mediaSites = sites.filter { $0.kind == media }
        mediaSites.move(fromOffsets: source, toOffset: destination)
        var iterator = mediaSites.makeIterator()
        sites = sites.map { site in
            guard site.kind == media else { return site }
            return iterator.next() ?? site
        }
        save()
    }

    func pull() async {
        guard !isPulling else { return }
        isPulling = true
        message = nil
        defer { isPulling = false }

        for source in remoteSources {
            do {
                guard let url = URL(string: source.url) else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let config = try JSONDecoder().decode(RemoteExploreConfig.self, from: data)
                var updated: [ExploreSite] = sites.filter(\.isLocal)
                for site in config.movie {
                    guard let url = site.url.nilIfEmpty else { continue }
                    updated.append(ExploreSite(name: site.name, urlString: url, searchURLTemplate: site.searchUrl, kind: .movie, isLocal: false))
                }
                for site in config.book {
                    guard let url = site.url.nilIfEmpty else { continue }
                    updated.append(ExploreSite(name: site.name, urlString: url, searchURLTemplate: site.searchUrl, kind: .book, isLocal: false))
                }
                guard !updated.isEmpty else { throw URLError(.cannotParseResponse) }
                sites = updated
                remoteVersion = config.version
                lastPulledAt = Date()
                lastConfigSourceName = source.name
                reachability = [:]
                save()
                message = L10n.Explore.configUpdated(String(describing: updated.count))
                return
            } catch {
                continue
            }
        }
        message = L10n.Explore.pullFailed
    }

    func refresh(timeout: TimeInterval = 15) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        message = nil
        defer { isRefreshing = false }

        let snapshot = sites
        var result: [UUID: Bool] = [:]
        for start in stride(from: 0, to: snapshot.count, by: 4) {
            let end = min(start + 4, snapshot.count)
            let chunk = Array(snapshot[start..<end])
            await withTaskGroup(of: (UUID, Bool).self) { group in
                for site in chunk {
                    group.addTask { [weak self] in
                        let reachable = await self?.check(site, timeout: timeout) ?? false
                        return (site.id, reachable)
                    }
                }
                for await (id, reachable) in group {
                    result[id] = reachable
                }
            }
            reachability.merge(result) { _, new in new }
        }
        message = result.values.allSatisfy { $0 } ? L10n.Explore.allReachable : L10n.Explore.checkDone
    }

    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
        return URLSession(configuration: configuration)
    }()

    private func check(_ site: ExploreSite, timeout: TimeInterval) async -> Bool {
        guard let url = site.url else { return false }
        let started = Date()
        let requestTimeout = min(6, max(2, timeout * 0.6))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await Self.probeSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200..<400).contains(http.statusCode) { return true }
            print("[Explore] URLSession status=\(http.statusCode) url=\(url.absoluteString)")
        } catch {
            print("[Explore] URLSession failed url=\(url.absoluteString) error=\(error.localizedDescription)")
        }
        let remaining = timeout - Date().timeIntervalSince(started)
        guard remaining > 0.5 else { return false }
        return await BrowserProbe.check(url: url, timeout: remaining)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ExploreSite].self, from: data) else {
            return
        }
        sites = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static let defaultSites: [ExploreSite] = [
        ExploreSite(name: "豆瓣电影", urlString: "https://movie.douban.com", searchURLTemplate: "https://movie.douban.com/subject_search?search_text={title}", kind: .movie, isLocal: false),
        ExploreSite(name: "TMDB", urlString: "https://www.themoviedb.org", searchURLTemplate: "https://www.themoviedb.org/search?query={title}", kind: .movie, isLocal: false),
        ExploreSite(name: "爱奇艺", urlString: "https://www.iqiyi.com", searchURLTemplate: "https://so.iqiyi.com/so/q_{title}", kind: .movie, isLocal: false),
        ExploreSite(name: "Letterboxd", urlString: "https://letterboxd.com", searchURLTemplate: "https://letterboxd.com/search/{title}/", kind: .movie, isLocal: true),
        ExploreSite(name: "豆瓣读书", urlString: "https://book.douban.com", searchURLTemplate: "https://book.douban.com/subject_search?search_text={title}", kind: .book, isLocal: false),
        ExploreSite(name: "Goodreads", urlString: "https://www.goodreads.com", searchURLTemplate: "https://www.goodreads.com/search?q={title}", kind: .book, isLocal: false),
        ExploreSite(name: "微信读书", urlString: "https://weread.qq.com", searchURLTemplate: "https://weread.qq.com/web/search/books?keyword={title}", kind: .book, isLocal: false),
        ExploreSite(name: "Open Library", urlString: "https://openlibrary.org", searchURLTemplate: "https://openlibrary.org/search?q={title}", kind: .book, isLocal: true)
    ]
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}


#if canImport(WebKit)
@MainActor
private final class BrowserProbe: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((Bool) -> Void)?
    private var timeoutWork: DispatchWorkItem?

    static func check(url: URL, timeout: TimeInterval) async -> Bool {
        await BrowserProbe().run(url: url, timeout: timeout)
    }

    private func run(url: URL, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self
            view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
            webView = view
            completion = { result in
                continuation.resume(returning: result)
            }
            let work = DispatchWorkItem { [weak self] in self?.finish(false) }
            timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(false)
    }

    private func finish(_ result: Bool) {
        guard let completion else { return }
        self.completion = nil
        timeoutWork?.cancel()
        timeoutWork = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        completion(result)
    }
}
#endif
