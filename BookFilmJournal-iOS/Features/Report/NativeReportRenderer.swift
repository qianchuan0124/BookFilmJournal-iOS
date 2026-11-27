import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum NativeReportRenderer {
    static let pageWidth: CGFloat = 390
    static let renderScale: CGFloat = 3
    static let maxExportBytes = 100 * 1024 * 1024
    static let maxPosterWallItems = 80
    static let reportFormatVersion = 22

    @MainActor
    static func render(query: ReportQuery, records: [MediaRecord], scale: CGFloat = renderScale) async -> UIImage? {
        #if canImport(UIKit)
        let avatar = await loadAvatarImage()
        let upper = NativeReportView(query: query, records: records, avatar: avatar, part: .upper)
            .frame(width: pageWidth)
            .fixedSize(horizontal: false, vertical: true)
        let lower = NativeReportView(query: query, records: records, avatar: avatar, part: .lower)
            .frame(width: pageWidth)
            .fixedSize(horizontal: false, vertical: true)

        let upperProbe = ImageRenderer(content: upper)
        upperProbe.scale = 1
        upperProbe.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        let lowerProbe = ImageRenderer(content: lower)
        lowerProbe.scale = 1
        lowerProbe.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        guard let upperHeight = upperProbe.uiImage?.size.height,
              let lowerHeight = lowerProbe.uiImage?.size.height,
              upperHeight > 0, lowerHeight > 0 else { return nil }
        let safeScale = max(1, min(scale, 8_000 / max(upperHeight, lowerHeight)))

        let upperRenderer = ImageRenderer(content: upper)
        upperRenderer.scale = safeScale
        upperRenderer.isOpaque = true
        upperRenderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        let lowerRenderer = ImageRenderer(content: lower)
        lowerRenderer.scale = safeScale
        lowerRenderer.isOpaque = true
        lowerRenderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        guard let upperImage = upperRenderer.uiImage,
              let lowerImage = lowerRenderer.uiImage else { return nil }
        return combine([upperImage, lowerImage], scale: safeScale)
        #else
        return nil
        #endif
    }

    @MainActor
    private static func combine(_ tiles: [UIImage], scale: CGFloat) -> UIImage? {
        #if canImport(UIKit)
        let pixelWidth = Int(ceil(pageWidth * scale))
        let totalHeight = tiles.reduce(0) { $0 + Int(ceil($1.size.height * scale)) }
        guard totalHeight > 0,
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: totalHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: totalHeight))
        var y = totalHeight
        for tile in tiles {
            guard let cgImage = tile.cgImage else { continue }
            let height = Int(ceil(tile.size.height * scale))
            y -= height
            context.draw(cgImage, in: CGRect(x: 0, y: y, width: pixelWidth, height: height))
        }
        guard let combined = context.makeImage() else { return nil }
        return UIImage(cgImage: combined)
        #else
        return nil
        #endif
    }

    @MainActor
    private static var avatarCache: (url: String, image: UIImage)?

    @MainActor
    private static func loadAvatarImage() async -> UIImage? {
        let value = UserDefaults.standard.string(forKey: "bookfilm.doubanAvatarURL")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty, let url = URL(string: value) else { return nil }
        if let cached = avatarCache, cached.url == value { return cached.image }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: data) else { return nil }
        avatarCache = (value, image)
        return image
    }

    @MainActor
    static func savePNG(_ image: UIImage, query: ReportQuery) -> URL? {
        #if canImport(UIKit)
        guard let data = image.pngData(), data.count <= maxExportBytes else { return nil }
        let directory = reportsDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(fileName(for: query))
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(reportFormatVersion, forKey: versionKey(for: query))
            return url
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    static func fileName(for query: ReportQuery) -> String {
        let title = query.title
            .replacingOccurrences(of: "/", with: "／")
            .replacingOccurrences(of: ":", with: "：")
            .replacingOccurrences(of: "?", with: "？")
            .replacingOccurrences(of: "*", with: "＊")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(title.isEmpty ? "书影记录报告" : title).png"
    }

    static func existingURL(for query: ReportQuery) -> URL? {
        let url = reportsDirectory().appendingPathComponent(fileName(for: query))
        guard FileManager.default.fileExists(atPath: url.path),
              UserDefaults.standard.integer(forKey: versionKey(for: query)) == reportFormatVersion else {
            return nil
        }
        return url
    }

    private static func versionKey(for query: ReportQuery) -> String {
        "bookfilm.report.format.\(fileName(for: query))"
    }

    private static func reportsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BookFilmJournal", isDirectory: true)
            .appendingPathComponent("Reports", isDirectory: true)
    }
}

private struct ReportPalette {
    let dark: Bool
    var bg: Color { Color(hex: dark ? 0x080B11 : 0xF3EEE3) }
    var panel: Color { Color(hex: dark ? 0x121722 : 0xFFFDF8) }
    var panel2: Color { Color(hex: dark ? 0x151B27 : 0xF7F1E5) }
    var line: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.11) }
    var lineSoft: Color { dark ? Color.white.opacity(0.04) : Color.black.opacity(0.06) }
    var text: Color { Color(hex: dark ? 0xEAE7DE : 0x2B251D) }
    var muted: Color { Color(hex: dark ? 0x8D95A5 : 0x8A7E6C) }
    var dim: Color { Color(hex: dark ? 0x5D6474 : 0xA89B87) }
    var gold: Color { Color(hex: dark ? 0xE5B45F : 0xB57A22) }
    var avatarTop: Color { Color(hex: 0xF4D083) }
    var avatarBottom: Color { Color(hex: 0xBC7C1D) }
    var red: Color { Color(hex: dark ? 0xDF6053 : 0xB8483E) }
    var teal: Color { Color(hex: dark ? 0x55B7A5 : 0x2E8775) }
    var blue: Color { Color(hex: dark ? 0x5F92D8 : 0x4C7ED6) }
    var purple: Color { Color(hex: dark ? 0x9D7ED8 : 0x7D62B3) }
}

private enum NativeReportPart {
    case full, upper, lower
}

private struct NativeReportView: View {
    let query: ReportQuery
    let records: [MediaRecord]
    var avatar: UIImage? = nil
    var part: NativeReportPart = .full

    private var p: ReportPalette { ReportPalette(dark: query.darkTheme) }
    private var sorted: [MediaRecord] { records.sorted { $0.effectiveDate > $1.effectiveDate } }
    private var ranked: [MediaRecord] { records.sorted { lhs, rhs in
        if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
        if lhs.comment.count != rhs.comment.count { return lhs.comment.count > rhs.comment.count }
        return lhs.effectiveDate > rhs.effectiveDate
    } }
    private var comments: [MediaRecord] { sorted.filter { !$0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var calendarDays: Int {
        let set = Set(records.map { Calendar.current.startOfDay(for: $0.effectiveDate) })
        return set.count
    }
    private var periodDays: Int {
        let calendar = Calendar.current
        let dates: (Date, Date)?
        if query.scope == .all {
            guard let first = records.map(\.effectiveDate).min(),
                  let last = records.map(\.effectiveDate).max() else { return 1 }
            dates = (first, last)
        } else {
            dates = (query.dateRange.lowerBound, query.dateRange.upperBound)
        }
        guard let dates else { return 1 }
        let start = calendar.startOfDay(for: dates.0)
        let end = calendar.startOfDay(for: dates.1)
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }
    private var averageRating: Double {
        let rated = records.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
    }
    private var fiveStars: Int { records.filter { $0.rating == 5 }.count }
    private var ratedCount: Int { records.filter { $0.rating > 0 }.count }
    private var totalMinutes: Int { records.compactMap(\.durationMinutes).filter { $0 > 0 }.reduce(0, +) }
    private var averageMinutes: Int {
        let values = records.compactMap(\.durationMinutes).filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
    private var totalPages: Int { records.compactMap(\.pages).filter { $0 > 0 }.reduce(0, +) }
    private var totalWords: Int { records.compactMap(\.wordCount).filter { $0 > 0 }.reduce(0, +) }
    private var publicationYears: Set<Int> {
        Set(records.compactMap(publicationYear))
    }
    private var noun: String { query.mediaType.noun }
    private var typeLabel: String { query.mediaType.label }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if part != .lower {
                header
                kpiSection
                featuredSection
                topSection
                highlightSection
                posterSection
            }
            if part != .upper {
                calendarSection
                prefsSection
                quoteSection
                footer
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, part == .lower ? 0 : 14)
        .padding(.bottom, part == .upper ? 0 : 28)
        .background(p.bg)
        .foregroundStyle(p.text)
        .environment(\.colorScheme, query.darkTheme ? .dark : .light)
    }

    private var periodTitle: String {
        switch query.scope {
        case .month:
            return String(format: "%04d.%02d", query.year, query.month)
        case .year:
            return "\(query.year)"
        case .custom:
            let calendar = Calendar.current
            let start = calendar.component(.year, from: query.startDate)
            let end = calendar.component(.year, from: query.endDate)
            return start == end ? "\(start)" : "\(start)–\(end)"
        case .all:
            let years = records.map { Calendar.current.component(.year, from: $0.effectiveDate) }
            guard let newest = years.max(), let oldest = years.min() else { return "ALL" }
            return newest == oldest ? "\(newest)" : "\(oldest)–\(newest)"
        }
    }

    private var periodSub: String {
        switch query.scope {
        case .month:
            return "\(query.year) 年 \(query.month) 月 · \(records.count) \(noun)\(typeLabel)记录"
        case .year:
            return "\(query.year) 年 · \(records.count) \(noun)\(typeLabel)记录"
        case .custom:
            return "\(periodTitle) 年 · 自定义年份 · \(records.count) \(noun)"
        case .all:
            return "全部记录 · \(records.count) \(noun)"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [p.avatarTop, p.avatarBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let avatar {
                        Image(uiImage: avatar)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(L10n.Settings.brandMark)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(Color(hex: 0x241804))
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Settings.brandName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                    Text("书影记录 · REPORT")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(p.gold)
                }
                Spacer(minLength: 0)
            }

            Text(periodTitle)
                .font(.custom("Georgia", size: 54).weight(.bold))
                .tracking(-2.9)
                .foregroundStyle(p.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 0)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
    }

    private var kpiSection: some View {
        let items = kpiItems
        let rows = (items.count + 1) / 2
        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        Group {
                            if index < items.count {
                                let item = items[index]
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.label.uppercased())
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .tracking(0.4)
                                        .foregroundStyle(p.dim)
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text(item.value)
                                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                                            .foregroundStyle(p.text)
                                        if !item.unit.isEmpty {
                                            Text(item.unit)
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(p.muted)
                                        }
                                    }
                                    Text(item.sub)
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(p.dim.opacity(0.85))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(p.line).frame(width: 1).offset(x: 179)
                }
                .overlay(alignment: .top) {
                    if row > 0 {
                        Rectangle().fill(p.lineSoft).frame(height: 1)
                    }
                }
            }
        }
        .background(p.panel)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(p.line, lineWidth: 1))
        .padding(.top, 18)
    }

    private var kpiItems: [KPIItem] {
        var items: [KPIItem] = [
            KPIItem(label: "记录", value: "\(records.count)", unit: noun, sub: "\(scopeWord)记录"),
            KPIItem(label: "有记录", value: "\(calendarDays)", unit: "天", sub: "占 \(periodDays) 天"),
            KPIItem(label: "五星", value: "\(fiveStars)", unit: noun, sub: ratedCount == 0 ? "" : "占已评分 \(Int(Double(fiveStars) / Double(ratedCount) * 100))%"),
            KPIItem(label: "平均评分", value: ratedCount == 0 ? "—" : String(format: "%.1f", averageRating), unit: "★", sub: "\(ratedCount) \(noun)已评分"),
            KPIItem(label: "短评", value: "\(comments.count)", unit: "条", sub: records.isEmpty ? "" : "占记录 \(Int(Double(comments.count) / Double(records.count) * 100))%")
        ]
        if query.mediaType == .movie {
            items.append(KPIItem(label: "总片长", value: totalMinutes > 0 ? "\(totalMinutes / 60)" : "—", unit: totalMinutes > 0 ? "小时 \(totalMinutes % 60) 分" : "", sub: "\(records.count) 部合计"))
            items.append(KPIItem(label: "类型", value: "\(typeCounts.count)", unit: "类", sub: "按电影类型统计"))
        } else {
            items.append(KPIItem(label: "总页数", value: totalPages > 0 ? "\(totalPages)" : "—", unit: totalPages > 0 ? "页" : "", sub: totalPages > 0 ? "平均每天 \(Int(Double(totalPages) / Double(periodDays))) 页" : ""))
            items.append(KPIItem(label: "总字数", value: totalWords > 0 ? String(format: "%.1f", Double(totalWords) / 10_000) : "—", unit: totalWords > 0 ? "万字" : "", sub: totalWords > 0 ? "平均每天 \(Int(Double(totalWords) / Double(periodDays))) 字" : ""))
        }
        if query.mediaType == .book {
            items.append(KPIItem(label: "类型", value: "\(typeCounts.count)", unit: "类", sub: "按书籍分类统计"))
        } else {
            items.append(KPIItem(label: "年代", value: "\(publicationYears.count)", unit: "个", sub: "按上映年份统计"))
        }
        return items
    }

    private var scopeWord: String {
        switch query.scope {
        case .month: "本期"
        case .year: "本年"
        case .custom: "本范围"
        case .all: "全部"
        }
    }

    private var featuredSection: some View {
        Group {
            if let featured = ranked.first {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center) {
                        Text("5 STAR · 本期最佳")
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(p.gold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(p.gold.opacity(0.45), lineWidth: 1))
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 12) {
                        cover(featured, width: 112, height: 168, radius: 8)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(featured.title)
                                .font(.system(size: 20, weight: .semibold, design: query.darkTheme ? .default : .serif))
                                .foregroundStyle(p.text)
                                .lineLimit(2)
                            metaLine(featured)
                            if !featured.comment.isEmpty {
                                Text(featured.comment)
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.muted)
                                    .lineSpacing(4)
                                    .lineLimit(4)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .background(
                    LinearGradient(colors: [p.panel2, p.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(p.gold.opacity(0.28), lineWidth: 1))
                .padding(.top, 20)
            }
        }
    }

    private var topSection: some View {
        Group {
            if !ranked.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("TOP 5", en: "Top Rated", count: "\(min(5, records.count)) \(noun)")
                        .padding(.bottom, 5)
                    ForEach(Array(ranked.prefix(5).enumerated()), id: \.element.id) { index, record in
                        HStack(spacing: 9) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(index == 0 ? p.gold : p.dim)
                                .frame(width: 25, alignment: .leading)
                            cover(record, width: 34, height: 51, radius: 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(p.text)
                                    .lineLimit(1)
                                Text("\(DateFormatter.recordDate.string(from: record.effectiveDate)) · \(record.statsText) · \(stars(record.rating))")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(p.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .bottom) { Rectangle().fill(p.lineSoft).frame(height: 1) }
                    }
                }
                .padding(12)
                .background(p.panel)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(p.line, lineWidth: 1))
                .padding(.top, 10)
            }
        }
    }

    private var highlightSection: some View {
        Group {
            if records.count >= 3 {
                VStack(alignment: .leading, spacing: 9) {
                    sectionHeader("影记片段", en: "Highlights", count: nil)
                        .padding(.top, 26)
                    VStack(spacing: 7) {
                        if let earliest = sorted.last {
                            highlightCard("首次记录", record: earliest)
                        }
                        if let latest = sorted.first {
                            highlightCard("最近记录", record: latest)
                        }
                        if let longest = comments.max(by: { $0.comment.count < $1.comment.count }) {
                            highlightCard("最长短评", record: longest)
                        }
                    }
                }
            }
        }
    }

    private func highlightCard(_ kind: String, record: MediaRecord) -> some View {
        HStack(alignment: .top, spacing: 7) {
            cover(record, width: 48, height: 72, radius: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.uppercased())
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(p.gold)
                Text(record.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(p.text)
                    .lineLimit(2)
                Text(record.comment.isEmpty ? record.statsText : record.comment)
                    .font(.system(size: 8.5))
                    .foregroundStyle(p.muted)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(p.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.line, lineWidth: 1))
    }

    private var posterDisplay: [MediaRecord] {
        Array(ranked.prefix(NativeReportRenderer.maxPosterWallItems))
    }

    private var posterSection: some View {
        Group {
            if posterDisplay.count >= 5 {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(
                        "海报墙",
                        en: "Poster",
                        count: posterDisplay.count < records.count
                            ? "\(posterDisplay.count) / \(records.count) \(noun)"
                            : "\(posterDisplay.count) \(noun)"
                    )
                    .padding(.top, 26)
                    posterWall
                }
            }
        }
    }

    private var posterWall: some View {
        let display = posterDisplay
        let columns = display.count <= 18 ? 5 : (display.count <= 40 ? 7 : 9)
        let tileHeight: CGFloat = columns == 5 ? 100 : (columns == 7 ? 74 : 56)
        let rows = max(6, Int(ceil(Double(display.count + 11) / Double(columns))))
        let tileWidth: CGFloat = 358 / CGFloat(columns)
        var occupied = Set<Int>()
        var slots: [PosterSlot] = []

        func isFree(_ row: Int, _ col: Int, _ rowSpan: Int, _ colSpan: Int) -> Bool {
            guard row >= 0, col >= 0, row + rowSpan <= rows, col + colSpan <= columns else { return false }
            for rowOffset in 0..<rowSpan {
                for colOffset in 0..<colSpan where occupied.contains((row + rowOffset) * columns + col + colOffset) {
                    return false
                }
            }
            return true
        }

        func mark(_ row: Int, _ col: Int, _ rowSpan: Int, _ colSpan: Int) {
            for rowOffset in 0..<rowSpan {
                for colOffset in 0..<colSpan {
                    occupied.insert((row + rowOffset) * columns + col + colOffset)
                }
            }
        }

        let heroRow = max(0, (rows - 3) / 2)
        let heroCol = max(0, (columns - 3) / 2)
        mark(heroRow, heroCol, 3, 3)
        slots.append(PosterSlot(row: heroRow, col: heroCol, rowSpan: 3, colSpan: 3))

        let centerRow = Double(rows) / 2
        let centerCol = Double(columns) / 2
        var largeCandidate: (row: Int, col: Int, distance: Double)?
        for row in 0..<max(0, rows - 1) {
            for col in 0...max(0, columns - 2) where isFree(row, col, 2, 2) {
                let distance = pow(Double(row) + 1 - centerRow, 2) + pow(Double(col) + 1 - centerCol, 2)
                if largeCandidate == nil || distance < largeCandidate!.distance {
                    largeCandidate = (row, col, distance)
                }
            }
        }
        if let large = largeCandidate {
            mark(large.row, large.col, 2, 2)
            slots.append(PosterSlot(row: large.row, col: large.col, rowSpan: 2, colSpan: 2))
        }
        for row in 0..<rows {
            for col in 0..<columns where !occupied.contains(row * columns + col) {
                slots.append(PosterSlot(row: row, col: col, rowSpan: 1, colSpan: 1))
            }
        }

        var filled = display
        var fillIndex = 0
        while filled.count < slots.count, !display.isEmpty {
            filled.append(display[fillIndex % display.count])
            fillIndex += 1
        }

        return ZStack(alignment: .topLeading) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                if index < filled.count {
                    cover(filled[index], width: CGFloat(slot.colSpan) * tileWidth, height: CGFloat(slot.rowSpan) * tileHeight, radius: 0)
                        .frame(width: CGFloat(slot.colSpan) * tileWidth, height: CGFloat(slot.rowSpan) * tileHeight)
                        .offset(x: CGFloat(slot.col) * tileWidth, y: CGFloat(slot.row) * tileHeight)
                }
            }
        }
        .frame(width: 358, height: CGFloat(rows) * tileHeight, alignment: .topLeading)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var calendarSection: some View {
        let calendar = Calendar.current
        let years = Set(records.map { calendar.component(.year, from: $0.effectiveDate) })
        let span = (years.max() ?? 0) - (years.min() ?? 0) + 1
        let useYearRows = query.scope != .month && span > 2
        return VStack(alignment: .leading, spacing: 9) {
            if query.scope == .month {
                sectionHeader("\(typeLabel)日历", en: "Monthly", count: "\(records.count) \(noun)")
                    .padding(.top, 26)
                monthCalendar
            } else {
                sectionHeader("\(typeLabel)年历", en: useYearRows ? "Years" : "Year Calendar", count: "\(records.count) \(noun)")
                    .padding(.top, 26)
                if useYearRows {
                    multiYearCalendar
                } else {
                    yearCalendar
                }
            }
        }
    }

    private var multiYearCalendar: some View {
        let calendar = Calendar.current
        let years = Set(records.map { calendar.component(.year, from: $0.effectiveDate) })
            .sorted(by: >)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Text("年份")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(p.dim)
                    .frame(width: 46, alignment: .leading)
                ForEach(1...12, id: \.self) { month in
                    Text(verbatim: "\(month)月")
                        .font(.system(size: 6.2))
                        .foregroundStyle(p.dim)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) { Rectangle().fill(p.lineSoft).frame(height: 1) }

            ForEach(years, id: \.self) { year in
                let yearRecords = records.filter { calendar.component(.year, from: $0.effectiveDate) == year }
                HStack(spacing: 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(year)")
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundStyle(p.gold)
                        Text("\(yearRecords.count) \(noun)")
                            .font(.system(size: 7.5))
                            .foregroundStyle(p.muted)
                    }
                    .frame(width: 46, alignment: .leading)
                    ForEach(1...12, id: \.self) { month in
                        let monthRecords = yearRecords.filter {
                            calendar.component(.month, from: $0.effectiveDate) == month
                        }.sorted { $0.rating > $1.rating }
                        VStack(alignment: .leading, spacing: 2) {
                            if !monthRecords.isEmpty {
                                ZStack(alignment: .topLeading) {
                                    Text(verbatim: "\(month)月")
                                        .font(.system(size: 6.2))
                                        .foregroundStyle(p.dim)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Text(verbatim: "\(monthRecords.count)")
                                        .font(.system(size: 6.2, weight: .medium))
                                        .foregroundStyle(p.gold)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: -1) {
                                    ForEach(Array(monthRecords.prefix(3).enumerated()), id: \.offset) { _, record in
                                        cover(record, width: 8, height: 12, radius: 1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 12)
                                .clipped()
                            }
                        }
                        .padding(3)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                        .background(p.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.lineSoft, lineWidth: 1))
                    }
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(p.lineSoft).frame(height: 1) }
            }
        }
        .padding(9)
        .background(p.panel)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(p.line, lineWidth: 1))
    }

    private var monthCalendar: some View {
        let calendar = Calendar.current
        let monthDate = calendar.date(from: DateComponents(year: query.year, month: query.month, day: 1)) ?? Date()
        let days = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        let first = (calendar.component(.weekday, from: monthDate) + 5) % 7
        let grouped = Dictionary(grouping: records) { calendar.component(.day, from: $0.effectiveDate) }
        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0)
                        .font(.system(size: 8.5))
                        .foregroundStyle(p.dim)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(0..<(first + days), id: \.self) { index in
                    if index < first {
                        Color.clear.frame(height: 47)
                    } else {
                        let day = index - first + 1
                        let item = grouped[day]?.sorted { $0.rating > $1.rating }.first
                        ZStack(alignment: .topLeading) {
                            if let item {
                                cover(item, width: nil, height: 47, radius: 5)
                            } else {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(p.panel)
                            }
                            Text("\(day)")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(item == nil ? p.dim : .white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(item == nil ? Color.clear : Color.black.opacity(0.68))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .frame(height: 47)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .padding(9)
        .background(p.panel)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(p.line, lineWidth: 1))
    }

    private var yearCalendar: some View {
        let calendar = Calendar.current
        let years = Dictionary(grouping: records) { calendar.component(.year, from: $0.effectiveDate) }
            .keys.sorted(by: >)
        return VStack(alignment: .leading, spacing: 10) {
            if years.isEmpty {
                Text("暂无可排布日期。")
                    .font(.system(size: 11))
                    .foregroundStyle(p.muted)
            } else {
                ForEach(years, id: \.self) { year in
                    yearBlock(year: year, records: records.filter {
                        calendar.component(.year, from: $0.effectiveDate) == year
                    })
                }
            }
        }
    }

    private func yearBlock(year: Int, records: [MediaRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(year)")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(p.gold)
                Text("年")
                    .font(.system(size: 9))
                    .foregroundStyle(p.muted)
                Spacer()
                Text("\(records.count) 条")
                    .font(.system(size: 9))
                    .foregroundStyle(p.dim)
            }
            ForEach(0..<4, id: \.self) { row in
                HStack(alignment: .top, spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        let month = row * 3 + column + 1
                        miniMonth(year: year, month: month, records: records)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(9)
        .background(p.panel)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(p.line, lineWidth: 1))
    }

    private func miniMonth(year: Int, month: Int, records: [MediaRecord]) -> some View {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let first = (calendar.component(.weekday, from: date) + 5) % 7
        let weeks = Int(ceil(Double(first + days) / 7.0))
        let grouped = Dictionary(grouping: records.filter { calendar.component(.month, from: $0.effectiveDate) == month }) {
            calendar.component(.day, from: $0.effectiveDate)
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(month) 月")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(p.muted)
            HStack(spacing: 1) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0)
                        .font(.system(size: 4.5))
                        .foregroundStyle(p.dim)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<weeks, id: \.self) { week in
                HStack(spacing: 1) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = week * 7 + column
                        let day = index - first + 1
                        if index >= first, day >= 1, day <= days {
                            let item = grouped[day]?.first
                            ZStack(alignment: .topLeading) {
                                Group {
                                    if let item {
                                        cover(item, width: nil, height: 10, radius: 2)
                                    } else {
                                        RoundedRectangle(cornerRadius: 2).fill(p.panel2)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                Text(verbatim: "\(day)")
                                    .font(.system(size: 4.0, weight: .medium))
                                    .foregroundStyle(item == nil ? p.dim : .white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.35)
                                    .allowsTightening(true)
                                    .padding(.horizontal, 1)
                                    .padding(.vertical, 0.5)
                                    .background(item == nil ? Color.clear : Color.black.opacity(0.58))
                                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .zIndex(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 10)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 10)
                        }
                    }
                }
            }
        }
    }

    private var prefsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Rectangle().fill(p.line).frame(height: 1)
                .padding(.top, 26)
            sectionHeader("类型偏好", en: "Categories", count: nil)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Array(typeCounts.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        Circle().fill(p.gold).frame(width: 4, height: 4)
                        Text(item.0)
                            .font(.system(size: 9.5))
                            .foregroundStyle(p.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(item.1)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(p.gold)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(p.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }

            decadeSection
        }
    }

    private var typeCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for record in records {
            for tag in typeTags(record) {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
    }

    private var decadeSection: some View {
        yearDecadeSection
    }

    private var yearDecadeSection: some View {
        var counts: [Int: Int] = [:]
        for record in records {
            guard let year = publicationYear(record) else { continue }
            counts[(year / 10) * 10, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        let decades = counts.keys.sorted(by: >)
        return VStack(alignment: .leading, spacing: 7) {
            Text("年代构成")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(p.muted)
            if decades.isEmpty {
                Text("暂无可统计年代")
                    .font(.system(size: 9))
                    .foregroundStyle(p.dim)
            } else {
                HStack(spacing: 1) {
                    ForEach(Array(decades.enumerated()), id: \.element) { index, decade in
                        let fraction = total > 0 ? CGFloat(counts[decade] ?? 0) / CGFloat(total) : 0
                        let width = max(4, 358 * fraction)
                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(decadeColor(index))
                            if fraction >= 0.10 {
                                Text(verbatim: "\(decade)s")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(p.dark ? Color.white.opacity(0.92) : Color.black.opacity(0.75))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                        }
                        .frame(width: width, height: 15)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                HStack(spacing: 7) {
                    ForEach(Array(decades.enumerated()), id: \.element) { index, decade in
                        HStack(spacing: 3) {
                            Circle().fill(decadeColor(index)).frame(width: 4, height: 4)
                            Text(verbatim: "\(decade)s")
                                .font(.system(size: 7.5))
                                .foregroundStyle(p.dim)
                        }
                    }
                }
                Text("按上映年份统计 · 共 \(decades.count) 个年代")
                    .font(.system(size: 7.5))
                    .foregroundStyle(p.dim)
            }
        }
    }

    private var quoteSection: some View {
        Group {
            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("短评精选", en: "Notes", count: "\(comments.count) 条")
                        .padding(.top, 26)
                    VStack(spacing: 7) {
                        ForEach(Array(comments.sorted {
                            if $0.comment.count != $1.comment.count { return $0.comment.count > $1.comment.count }
                            return $0.rating > $1.rating
                        }.prefix(5)), id: \.id) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 7) {
                                    Text("“")
                                        .font(.system(size: 22, weight: .bold, design: .serif))
                                        .foregroundStyle(p.gold.opacity(0.6))
                                        .frame(width: 12, alignment: .topLeading)
                                    Text(record.comment)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(p.muted)
                                        .lineSpacing(2)
                                        .lineLimit(4)
                                    Spacer(minLength: 0)
                                }
                                HStack(spacing: 5) {
                                    Text(record.title)
                                        .font(.system(size: 8.5, weight: .medium))
                                        .foregroundStyle(p.dim)
                                        .lineLimit(1)
                                    Text("·")
                                        .foregroundStyle(p.dim)
                                    Text(DateFormatter.recordDate.string(from: record.effectiveDate))
                                        .font(.system(size: 8))
                                        .foregroundStyle(p.dim)
                                    Spacer(minLength: 0)
                                    Text(stars(record.rating))
                                        .font(.system(size: 8))
                                        .foregroundStyle(p.gold)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                            .background(p.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(p.line, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("数据来自本地记录 · 标记日期为本地生效时间 · 报告由书影记录生成")
                .font(.system(size: 8))
                .foregroundStyle(p.dim)
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
    }

    private func sectionHeader(_ title: String, en: String, count: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(p.gold).frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 17, weight: .bold, design: query.darkTheme ? .default : .serif))
                .foregroundStyle(p.text)
            Text(en.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(p.dim)
            Spacer(minLength: 0)
            if let count {
                Text(count)
                    .font(.system(size: 8.5))
                    .foregroundStyle(p.muted)
            }
        }
    }

    private func sectionTitle(_ title: String, en: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.text)
            Text(en.uppercased())
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(1)
                .foregroundStyle(p.dim)
        }
    }

    private func metaLine(_ record: MediaRecord) -> some View {
        Text("\(stars(record.rating))  \(DateFormatter.recordDate.string(from: record.effectiveDate))  \(record.statsText)")
            .font(.system(size: 8.5))
            .foregroundStyle(p.muted)
            .lineLimit(1)
    }

    private func metaText(_ record: MediaRecord) -> String {
        if record.mediaType == .movie {
            return record.durationMinutes.map { "\($0 / 60)h\($0 % 60)m" } ?? "—"
        }
        return record.pages.map { "\($0)页" } ?? "—"
    }

    private func stars(_ rating: Int) -> String {
        String(repeating: "★", count: max(0, min(5, rating))) + String(repeating: "☆", count: max(0, 5 - rating))
    }

    private func cover(_ record: MediaRecord, width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let key = record.coverLocalKey, let image = CoverStore.cachedImage(for: key) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                PosterArtwork(art: record.art)
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .clipped()
    }

    private func typeTags(_ record: MediaRecord) -> [String] {
        if record.mediaType == .book {
            let overrides: [String: String] = [
                "金赛性学报告": "医学健康", "1007天的战争": "历史",
                "小狗钱钱2": "经济理财", "小狗钱钱": "经济理财", "领袖们": "传记",
                "巴菲特致股东的信 (第4版)": "经济理财", "菊与刀": "社会科学",
                "社会契约论": "政治哲学", "黑天鹅": "经济理财",
                "三体Ⅲ": "科幻", "三体Ⅱ": "科幻", "三体": "科幻", "三体全集": "科幻",
                "神们自己": "科幻", "全频带阻塞干扰": "科幻", "球状闪电": "科幻",
                "银河帝国：基地七部曲": "科幻", "永恒的终结": "科幻",
                "神秘岛": "科幻", "海底两万里": "科幻",
                "货币金融学（第十三版）": "经济理财",
                "聪明的投资者（第4版注疏点评版）": "经济理财", "聪明的投资者": "经济理财",
                "经济学原理（第5版）": "经济理财", "经济学原理": "经济理财", "经济学原理（上下）": "经济理财",
                "叫魂": "历史", "中国历代政治得失": "历史", "筚路维艰": "历史",
                "翦商": "历史", "万历十五年": "历史", "明朝那些事儿（1-9）": "历史", "人类简史": "历史",
                "倚天屠龙记": "武侠", "射雕英雄传": "武侠", "笑傲江湖（全四册）": "武侠",
                "冰与火之歌": "奇幻", "诡秘之主 1": "奇幻", "道诡异仙": "奇幻",
                "白夜行": "推理悬疑", "恶意": "推理悬疑",
                "被讨厌的勇气": "心理学", "刻意练习": "心理学", "认知觉醒（百万册精装纪念版）": "心理学",
                "亲密关系（第6版）": "心理学", "人性的弱点": "心理学",
                "风光摄影后期基础": "摄影艺术", "摄影笔记": "摄影艺术",
                "娱乐至死": "社会科学", "生育制度": "社会科学",
                "君主论": "政治哲学",
                "富爸爸，穷爸爸": "经济理财", "国富论": "经济理财", "置身事内": "经济理财"
            ]
            let candidates = [
                record.title,
                record.title.components(separatedBy: "：").first ?? record.title,
                record.title.components(separatedBy: ":").first ?? record.title,
                record.title.components(separatedBy: "（").first ?? record.title,
                record.title.components(separatedBy: "(").first ?? record.title,
                record.title.components(separatedBy: " / ").first ?? record.title
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for candidate in candidates {
                if let category = overrides[candidate] { return [category] }
            }
            return ["文学小说"]
        }
        var result: [String] = []
        let genres: Set<String> = [
            "剧情", "喜剧", "动作", "爱情", "科幻", "动画", "悬疑", "惊悚", "恐怖", "犯罪",
            "传记", "历史", "战争", "奇幻", "冒险", "家庭", "纪录片", "音乐", "运动"
        ]
        for part in record.intro.split(separator: "/") {
            for word in part.split(whereSeparator: { $0 == " " || $0 == "、" || $0 == "," || $0 == "，" }) {
                let tag = String(word)
                if genres.contains(tag), !result.contains(tag) {
                    result.append(tag)
                }
            }
        }
        return result
    }

    private func publicationYear(_ record: MediaRecord) -> Int? {
        if let value = record.year, let year = Int(value.prefix(4)), year > 1800 {
            return year
        }
        guard let range = record.intro.range(of: "\\b(18|19|20)\\d{2}\\b", options: .regularExpression),
              let year = Int(record.intro[range]) else { return nil }
        return year
    }


    private func decadeColor(_ index: Int) -> Color {
        let fixed: [Color] = [
            p.gold,
            p.red,
            p.teal,
            p.blue,
            p.purple,
            Color(hex: p.dark ? 0xD98A4A : 0xB86A2F)
        ]
        if index < fixed.count { return fixed[index] }
        return Color(
            hue: (Double(index) * 0.618).truncatingRemainder(dividingBy: 1),
            saturation: p.dark ? 0.58 : 0.62,
            brightness: p.dark ? 0.82 : 0.62
        )
    }
}

private struct PosterSlot {
    let row: Int
    let col: Int
    let rowSpan: Int
    let colSpan: Int
}

private struct KPIItem {
    let label: String
    let value: String
    let unit: String
    let sub: String
}
