import Foundation

struct ExploreRemoteSource: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let url: String
}

struct ExploreRemoteSourcesConfig: Codable {
    let sources: [ExploreRemoteSource]
}

enum ExploreRemoteSources {
    static let fallback: [ExploreRemoteSource] = [
        ExploreRemoteSource(
            id: "github",
            name: "GitHub",
            description: "优先从 GitHub 拉取远端站点配置。",
            url: "https://raw.githubusercontent.com/catnine/bookfilm-sites/main/sites.json"
        ),
        ExploreRemoteSource(
            id: "gitee",
            name: "Gitee",
            description: "GitHub 拉取失败时回退到 Gitee 镜像。",
            url: "https://gitee.com/catnine/bookfilm-sites/raw/main/sites.json"
        )
    ]

    static func load() -> [ExploreRemoteSource] {
        guard let url = Bundle.main.url(forResource: "ExploreSources", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ExploreRemoteSourcesConfig.self, from: data),
              !config.sources.isEmpty
        else {
            return fallback
        }
        return config.sources
    }
}
