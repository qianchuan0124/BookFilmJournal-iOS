import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum CoverStore {
    private static let directoryName = "Covers"

    static func localURL(for key: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("BookFilmJournal", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent(safe.isEmpty ? "cover-\(key.hashValue)" : safe)
            .appendingPathExtension("jpg")
    }

    static func hasCover(for key: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: key).path)
    }

    static func version(for key: String) -> String {
        let url = localURL(for: key)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return "0"
        }
        let stamp = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(stamp)-\(values.fileSize ?? 0)"
    }

    static func removeCover(for key: String) {
        try? FileManager.default.removeItem(at: localURL(for: key))
    }

    static func removeAllCovers() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("BookFilmJournal", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    static func linkKey(for subjectID: String) -> String { "\(subjectID)-link" }

    static func fetchImageData(urlString: String) async -> Data? {
        guard !urlString.isEmpty else { return nil }
        for candidate in mirrorURLs(urlString) {
            guard let url = URL(string: candidate) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      !data.isEmpty else { continue }
                #if canImport(UIKit)
                guard UIImage(data: data) != nil else { continue }
                #endif
                return data
            } catch {
                continue
            }
        }
        return nil
    }

    static func download(urlString: String, key: String, overwrite: Bool = false) async -> Bool {
        guard !urlString.isEmpty else { return false }
        if !overwrite, hasCover(for: key) { return true }
        guard let data = await fetchImageData(urlString: urlString) else { return false }
        return write(data: data, key: key)
    }

    static func write(data: Data, key: String) -> Bool {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return false }
        let maxSide: CGFloat = 720
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let output = normalized.jpegData(compressionQuality: 0.86) else { return false }
        #else
        let output = data
        #endif
        do {
            try output.write(to: localURL(for: key), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func base64(for key: String) -> String? {
        guard let data = try? Data(contentsOf: localURL(for: key)) else { return nil }
        return data.base64EncodedString()
    }

    static func writeBase64(_ base64: String, key: String) -> Bool {
        guard let data = Data(base64Encoded: base64) else { return false }
        return write(data: data, key: key)
    }

    static func fingerprint(for key: String) -> String? {
        guard let data = try? Data(contentsOf: localURL(for: key)) else { return nil }
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return "\(data.count)"
        #endif
    }

    #if canImport(UIKit)
    static func cachedImage(for key: String) -> UIImage? {
        UIImage(contentsOfFile: localURL(for: key).path)
    }
    #endif

    static func download(records: [MediaRecord], mediaTypes: Set<MediaType>, progress: ((Int, Int) -> Void)? = nil) async {
        let candidates = records.filter {
            mediaTypes.contains($0.mediaType) &&
            !$0.isDeleted &&
            $0.localCover != true &&
            !($0.coverURL ?? "").isEmpty &&
            !hasCover(for: $0.subjectID)
        }
        guard !candidates.isEmpty else { return }
        var completed = 0
        let total = candidates.count
        for start in stride(from: 0, to: candidates.count, by: 4) {
            let end = min(start + 4, candidates.count)
            await withTaskGroup(of: Void.self) { group in
                for record in candidates[start..<end] {
                    group.addTask {
                        _ = await download(urlString: record.coverURL ?? "", key: record.subjectID)
                    }
                }
                await group.waitForAll()
            }
            completed += end - start
            progress?(completed, total)
        }
    }

    static func download(doulistItems: [DoulistItem], progress: ((Int, Int) -> Void)? = nil) async {
        let candidates = doulistItems.filter {
            !($0.coverURL ?? "").isEmpty && !hasCover(for: $0.subjectID)
        }
        guard !candidates.isEmpty else { return }
        var completed = 0
        let total = candidates.count
        for start in stride(from: 0, to: candidates.count, by: 4) {
            let end = min(start + 4, candidates.count)
            await withTaskGroup(of: Void.self) { group in
                for item in candidates[start..<end] {
                    group.addTask {
                        _ = await download(urlString: item.coverURL ?? "", key: item.subjectID)
                    }
                }
                await group.waitForAll()
            }
            completed += end - start
            progress?(completed, total)
        }
    }

    private static func mirrorURLs(_ value: String) -> [String] {
        guard var components = URLComponents(string: value) else { return [value] }
        let hosts = ["img3.doubanio.com", "img1.doubanio.com", "img2.doubanio.com", "img9.doubanio.com"]
        var result = [value]
        for host in hosts where host != components.host {
            components.host = host
            if let candidate = components.string, !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }
}
