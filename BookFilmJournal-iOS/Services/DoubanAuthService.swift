import Foundation

enum DoubanAuthState: Equatable {
    case noCookie
    case checking
    case valid
    case expired
    case unknown

    var label: String {
        switch self {
        case .noCookie: L10n.Auth.notLoggedIn
        case .checking: L10n.Auth.checking
        case .valid: L10n.Auth.loggedIn
        case .expired: L10n.Auth.expired
        case .unknown: L10n.Auth.unknown
        }
    }
}

enum DoubanAuthService {
    static func validate(cookie: String?, userID: String) async -> DoubanAuthState {
        guard let cookie, !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noCookie
        }
        let cookieValue = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedID = DoubanSyncService.userID(fromCookie: cookieValue)
        let suppliedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = detectedID ?? (suppliedID == "catnine" ? nil : suppliedID)

        if let id, !id.isEmpty {
            let owned = await checkOwnedDoulists(cookie: cookieValue, userID: id)
            if owned == .valid || owned == .expired {
                return owned
            }
        }
        return await checkMine(cookie: cookieValue)
    }

    private static func checkOwnedDoulists(cookie: String, userID: String) async -> DoubanAuthState {
        guard let encoded = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://m.douban.com/rexxar/api/v2/user/\(encoded)/owned_doulists?start=0&count=1&ck=&for_mobile=1") else {
            return .unknown
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unknown }
            switch http.statusCode {
            case 200..<300: return .valid
            case 401, 403: return .expired
            case 404: return .unknown
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    private static func checkMine(cookie: String) async -> DoubanAuthState {
        guard let url = URL(string: "https://m.douban.com/mine/") else { return .unknown }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unknown }
            let finalURL = http.url?.absoluteString.lowercased() ?? ""
            if (200..<300).contains(http.statusCode),
               !finalURL.contains("login"),
               !finalURL.contains("accounts.douban.com") {
                return .valid
            }
            if http.statusCode == 401 || http.statusCode == 403 || finalURL.contains("login") {
                return .expired
            }
            return .unknown
        } catch {
            return .unknown
        }
    }}
