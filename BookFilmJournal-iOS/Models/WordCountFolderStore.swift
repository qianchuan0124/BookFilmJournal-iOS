import Foundation
import Observation

struct WordCountFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var bookmark: Data
    var isSelected: Bool = true
}

@Observable
final class WordCountFolderStore {
    var folders: [WordCountFolder] = []

    private let defaultsKey = "bookfilm.wordcount.folders"

    init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([WordCountFolder].self, from: data) else { return }
        folders = decoded
    }

    var selectedCount: Int { folders.filter(\.isSelected).count }

    func add(urls: [URL]) -> [String] {
        var failures: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                folders.append(WordCountFolder(name: url.lastPathComponent, bookmark: bookmark))
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        save()
        return failures
    }

    func remove(id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    func toggle(id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isSelected.toggle()
        save()
    }

    func selectAll(_ selected: Bool) {
        for index in folders.indices { folders[index].isSelected = selected }
        save()
    }

    func resolve(_ folder: WordCountFolder) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: folder.bookmark,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    func allURLs() -> [URL] {
        resolvedURLs(for: folders)
    }

    func selectedURLs() -> [URL] {
        resolvedURLs(for: folders.filter(\.isSelected))
    }

    private func resolvedURLs(for items: [WordCountFolder]) -> [URL] {
        items.compactMap { folder in
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: folder.bookmark,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { return nil }
            return url
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
