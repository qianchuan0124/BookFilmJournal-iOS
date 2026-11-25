import Foundation

struct DoubanProfile {
    let name: String?
    let avatarURL: String?
}

enum DoubanProfileService {
    static func fetch(userID: String, cookie: String?) async -> DoubanProfile? {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://m.douban.com/rexxar/api/v2/user/\(encoded)?ck=&for_mobile=1")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return nil }
            let user = object["user"] as? [String: Any] ?? object
            let avatar = ["large_avatar", "avatar_large", "avatar", "avatar_url"]
                .compactMap { user[$0] as? String }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let name = user["name"] as? String
            guard avatar != nil else { return nil }
            return DoubanProfile(name: name, avatarURL: avatar)
        } catch {
            return nil
        }
    }
}
