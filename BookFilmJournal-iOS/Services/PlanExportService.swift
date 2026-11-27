import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum PlanExportService {
    static func makePNG(folder: PlanFolder, items: [PlanItem]) -> URL? {
        #if canImport(UIKit)
        let canvas = PlanExportCanvas(folder: folder, items: items)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("BookFilmJournal", isDirectory: true)
            .appendingPathComponent("Reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeTitle = folder.title
            .replacingOccurrences(of: "/", with: "／")
            .replacingOccurrences(of: ":", with: "：")
            .replacingOccurrences(of: "?", with: "？")
            .replacingOccurrences(of: "*", with: "＊")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = directory.appendingPathComponent("\(safeTitle.isEmpty ? "书影记录海报" : safeTitle).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

#if canImport(UIKit)
private struct PlanExportCanvas: View {
    let folder: PlanFolder
    let items: [PlanItem]

    private var readCount: Int { items.filter(\.isRead).count }
    private var progress: Double {
        items.isEmpty ? 0 : Double(readCount) / Double(items.count)
    }
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.Plan.exportTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.reportGold)
                        .tracking(2)
                    Text(folder.title)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Theme.reportText)
                        .lineLimit(2)
                    if !folder.note.isEmpty {
                        Text(folder.note)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.reportMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.reportGold)
                    Text("\(folder.mediaType.doneLabel) \(readCount) / \(items.count) \(folder.mediaType.noun)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.reportMuted)
                }
            }
            .padding(22)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.reportLine)
                    Capsule().fill(Theme.reportGold).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.reportMuted)
                            .frame(width: 22, alignment: .leading)
                        PosterArtwork(art: item.art)
                            .frame(width: 52, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.reportText)
                                .lineLimit(1)
                            Text(item.statsText.isEmpty ? folder.mediaType.recordTitle : item.statsText)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.reportMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.readStatusLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(item.isRead ? Theme.read : Theme.reportMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.isRead ? Theme.readSoft : Theme.reportLine)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(index.isMultiple(of: 2) ? Theme.reportCard : Theme.reportBG)
                }
            }

            HStack {
                Text(L10n.Plan.exportSource(folder.mediaType.label))
                Spacer()
                Text(dateText)
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.reportMuted)
            .padding(22)
        }
        .frame(width: 760)
        .background(Theme.reportBG)
    }
}
#endif
