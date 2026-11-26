import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
import WebKit
#endif

#if canImport(UIKit)
private final class WebSnapshotCoordinator: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(for webView: WKWebView, html: String, baseURL: URL?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: baseURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                self?.finish(WebSnapshotError.timeout)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.finish(nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

private enum WebSnapshotError: LocalizedError {
    case timeout
    case noImage

    var errorDescription: String? {
        switch self {
        case .timeout: "报告渲染超时"
        case .noImage: "报告截图失败"
        }
    }
}
#endif

@MainActor
enum ReportExportService {
    static let segmentHeight: CGFloat = 12_000

    static func fileName(for query: ReportQuery) -> String {
        let scope: String
        switch query.scope {
        case .month:
            scope = String(format: "%04d-%02d", query.year, query.month)
        case .year:
            scope = "\(query.year)"
        case .custom:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd"
            scope = "\(formatter.string(from: query.startDate))-\(formatter.string(from: query.endDate))"
        case .all:
            scope = "all"
        }
        return "report_\(query.mediaType.rawValue)_\(query.scope.rawValue)_\(scope).html"
    }

    static func writeHTML(query: ReportQuery, records: [MediaRecord]) -> URL? {
        let html = makeHTML(query: query, records: records)
        let directory = reportsDirectory()
        let url = directory.appendingPathComponent(fileName(for: query))
        do {
            try Data(html.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func existingHTML(for query: ReportQuery) -> URL? {
        let url = reportsDirectory().appendingPathComponent(fileName(for: query))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func renderPNGs(from htmlURL: URL, baseName: String) async throws -> [URL] {
        #if canImport(UIKit)
        guard let html = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            throw WebSnapshotError.noImage
        }
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let windowScene else { throw WebSnapshotError.noImage }

        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -10_000, y: 0, width: 1_220, height: 1_200)
        window.windowLevel = .alert + 1
        window.backgroundColor = .white
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1_220, height: 1_200), configuration: configuration)
        controller.view.addSubview(webView)
        let coordinator = WebSnapshotCoordinator()
        try await coordinator.wait(for: webView, html: html, baseURL: htmlURL.deletingLastPathComponent())

        let rawHeight = try await webView.evaluateJavaScript("document.documentElement.scrollHeight")
        let contentHeight = max(1_200, CGFloat((rawHeight as? NSNumber)?.doubleValue ?? 1_200))
        webView.frame = CGRect(x: 0, y: 0, width: 1_220, height: contentHeight)
        webView.layoutIfNeeded()

        let image = try await snapshot(webView: webView, height: contentHeight)
        window.isHidden = true

        guard let cgImage = image.cgImage else { throw WebSnapshotError.noImage }
        let pixelHeight = CGFloat(cgImage.height)
        let pixelWidth = CGFloat(cgImage.width)
        let segmentPixels = segmentHeight * image.scale
        let count = max(1, Int(ceil(pixelHeight / segmentPixels)))
        var urls: [URL] = []
        let directory = reportsDirectory()
        let pngBase = baseName.replacingOccurrences(of: ".html", with: "")
        for index in 0..<count {
            let y = CGFloat(index) * segmentPixels
            let height = min(segmentPixels, pixelHeight - y)
            guard height > 0,
                  let cropped = cgImage.cropping(to: CGRect(x: 0, y: y, width: pixelWidth, height: height)) else {
                continue
            }
            let image = UIImage(cgImage: cropped)
            guard let data = image.pngData() else { continue }
            let suffix = count > 1 ? "-\(index + 1)" : ""
            let url = directory.appendingPathComponent("\(pngBase)\(suffix).png")
            try data.write(to: url, options: .atomic)
            urls.append(url)
        }
        guard !urls.isEmpty else { throw WebSnapshotError.noImage }
        return urls
        #else
        return []
        #endif
    }

    #if canImport(UIKit)
    private static func snapshot(webView: WKWebView, height: CGFloat) async throws -> UIImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 1_220, height: height)
        configuration.afterScreenUpdates = true
        return try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? WebSnapshotError.noImage)
                }
            }
        }
    }
    #endif

    static func makeHTML(query: ReportQuery, records: [MediaRecord]) -> String {
        let dark = query.darkTheme
        let bg = dark ? "#080b11" : "#f3eee3"
        let panel = dark ? "#121722" : "#fffdf8"
        let panel2 = dark ? "#151b27" : "#f7f1e5"
        let line = dark ? "rgba(255,255,255,.08)" : "rgba(43,37,29,.10)"
        let lineSoft = dark ? "rgba(255,255,255,.04)" : "rgba(43,37,29,.06)"
        let text = dark ? "#eae7de" : "#2b251d"
        let muted = dark ? "#8d95a5" : "#8a7e6c"
        let dim = dark ? "#5d6474" : "#a89b87"
        let gold = dark ? "#e5b45f" : "#b57a22"
        let red = dark ? "#df6053" : "#b8483e"
        let teal = dark ? "#55b7a5" : "#2e8775"
        let blue = dark ? "#5f92d8" : "#4c7ed6"
        let purple = dark ? "#9d7ed8" : "#7d62b3"
        let ownerName = L10n.Settings.brandName
        let ownerMark = L10n.Settings.brandMark
        let avatarURL = UserDefaults.standard.string(forKey: "bookfilm.doubanAvatarURL") ?? ""
        let avatarHTML = avatarURL.isEmpty
            ? "<div class='avatar'>\(escape(ownerMark))</div>"
            : "<div class='avatar'><span>\(escape(ownerMark))</span><img src='\(escape(avatarURL))' alt=''></div>"

        let sorted = records.sorted { $0.effectiveDate > $1.effectiveDate }
        let ranked = records.sorted {
            if $0.rating != $1.rating { return $0.rating > $1.rating }
            if $0.comment.count != $1.comment.count { return $0.comment.count > $1.comment.count }
            return $0.effectiveDate > $1.effectiveDate
        }
        let rated = records.filter { $0.rating > 0 }
        let average = rated.isEmpty ? 0 : Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
        let five = records.filter { $0.rating == 5 }.count
        let comments = records.filter { !$0.comment.isEmpty }
        let days = Set(records.map { Calendar.current.startOfDay(for: $0.effectiveDate) }).count
        let months = Set(records.map {
            let components = Calendar.current.dateComponents([.year, .month], from: $0.effectiveDate)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        }).count
        let minutes = records.compactMap(\.durationMinutes).reduce(0, +)
        let durations = records.compactMap(\.durationMinutes)
        let pages = records.compactMap(\.pages).reduce(0, +)
        let words = records.compactMap(\.wordCount).reduce(0, +)
        let noun = query.mediaType.noun

        let period = reportPeriod(query: query, records: records)
        let scopeWord = query.scope == .month ? "本期" : (query.scope == .year ? "本年" : "本范围")
        let periodUnit = query.scope == .month ? "天" : "个月"
        let active = query.scope == .month ? days : months
        let activeLabel = query.scope == .month ? "有记录天数" : "有记录月份"
        let typeCount = Set(records.compactMap { $0.year }).count

        var kpis = ""
        kpis += kpiHTML(label: "记录", value: "\(records.count)", unit: noun, sub: "\(scopeWord)记录")
        kpis += kpiHTML(label: activeLabel, value: "\(active)", unit: periodUnit, sub: query.scope == .month ? "\(days) 个有记录的日子" : "覆盖 \(months) 个月")
        kpis += kpiHTML(label: "五星", value: "\(five)", unit: noun, sub: rated.isEmpty ? "" : String(format: "占已评分 %.0f%%", Double(five) / Double(rated.count) * 100))
        kpis += kpiHTML(label: "平均评分", value: rated.isEmpty ? "—" : String(format: "%.1f", average), unit: "★", sub: "\(rated.count) \(noun)已评分")
        kpis += kpiHTML(label: "短评", value: "\(comments.count)", unit: "条", sub: records.isEmpty ? "" : String(format: "占记录 %.0f%%", Double(comments.count) / Double(records.count) * 100))
        if query.mediaType == .movie {
            kpis += kpiHTML(label: "总片长", value: minutes > 0 ? "\(minutes / 60)" : "—", unit: minutes > 0 ? "小时 \(minutes % 60) 分" : "", sub: "\(records.count) 部合计")
            let averageMinutes = durations.isEmpty ? 0 : Int((Double(minutes) / Double(durations.count)).rounded())
            kpis += kpiHTML(label: "平均片长", value: averageMinutes > 0 ? "\(averageMinutes)" : "—", unit: averageMinutes > 0 ? "分钟" : "", sub: "")
        } else {
            kpis += kpiHTML(label: "总页数", value: pages > 0 ? "\(pages)" : "—", unit: pages > 0 ? "页" : "", sub: "\(records.count) 本合计")
            kpis += kpiHTML(label: "总字数", value: words > 0 ? String(format: "%.1f", Double(words) / 10_000) : "—", unit: words > 0 ? "万字" : "", sub: "\(records.count) 本合计")
        }
        kpis += kpiHTML(label: "年代", value: "\(typeCount)", unit: "个", sub: "按记录年份统计")

        var imageCache: [PosterArt: String] = [:]
        func image(_ art: PosterArt) -> String {
            if let cached = imageCache[art] { return cached }
            let value = posterDataURI(art)
            imageCache[art] = value
            return value
        }

        func statsLine(_ record: MediaRecord) -> String {
            if query.mediaType == .movie {
                guard let minutes = record.durationMinutes, minutes > 0 else { return "时长未设置" }
                let hours = minutes / 60
                let rest = minutes % 60
                if hours > 0 && rest > 0 { return "\(hours) 小时 \(rest) 分" }
                if hours > 0 { return "\(hours) 小时" }
                return "\(rest) 分"
            }
            var parts: [String] = []
            if let words = record.wordCount, words > 0 { parts.append(String(format: "%.1f 万字", Double(words) / 10_000)) }
            if let pages = record.pages, pages > 0 { parts.append("\(pages) 页") }
            return parts.isEmpty ? "字数未统计" : parts.joined(separator: " · ")
        }

        func metaLine(_ record: MediaRecord) -> String {
            [record.displayDate, statsLine(record), stars(record.rating)]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }

        func featuredHTML(_ record: MediaRecord) -> String {
            let tag = record.rating == 5 ? "5 STAR" : (record.rating > 0 ? "\(record.rating) STAR" : "UNRATED")
            let comment = record.comment.isEmpty ? "" : "<p class='featured-comment'>\(escape(short(record.comment, limit: 140)))</p>"
            return """
            <div class="featured-card">
              <span class="featured-tag">\(tag) · 本期最佳</span>
              <img class="featured-poster" src="\(image(record.art))" alt="\(escape(record.title))">
              <h3 class="featured-title">\(escape(record.title))</h3>
              <div class="featured-meta"><span class="stars">\(stars(record.rating))</span><span>\(escape(record.displayDate))</span><span>\(escape(statsLine(record)))</span></div>
              \(comment)
            </div>
            """
        }

        var topRows = ""
        for (index, record) in ranked.prefix(5).enumerated() {
            topRows += """
            <div class="top-row">
              <span class="rank">\(String(format: "%02d", index + 1))</span>
              <img class="top-thumb" src="\(image(record.art))" alt="\(escape(record.title))">
              <div class="top-main"><span class="top-title">\(escape(record.title))</span><span class="top-meta">\(escape(metaLine(record)))</span></div>
              <span class="top-stars">\(stars(record.rating))</span>
            </div>
            """
        }

        func highlightHTML(kind: String, record: MediaRecord?) -> String {
            guard let record else { return "" }
            return """
            <article class="highlight">
              <img src="\(image(record.art))" alt="\(escape(record.title))">
              <div class="highlight-main">
                <span class="highlight-kind">\(escape(kind))</span>
                <h4>\(escape(record.title))</h4>
                <span class="highlight-meta">\(escape(metaLine(record)))</span>
                <p>\(record.comment.isEmpty ? "这一条没有留下短评。" : escape(short(record.comment, limit: 100)))</p>
              </div>
            </article>
            """
        }

        let earliest = sorted.min { $0.effectiveDate < $1.effectiveDate }
        let latest = sorted.max { $0.effectiveDate < $1.effectiveDate }
        let longest = comments.max { $0.comment.count < $1.comment.count }
        let highlightLabels: (String, String, String)
        switch query.scope {
        case .month: highlightLabels = ("本期首看", "本期收官", "最长短评")
        case .year: highlightLabels = ("年度首看", "年度收官", "最长短评")
        default: highlightLabels = ("首次记录", "最近记录", "最长短评")
        }
        let highlights = highlightHTML(kind: highlightLabels.0, record: earliest)
            + highlightHTML(kind: highlightLabels.1, record: latest)
            + highlightHTML(kind: highlightLabels.2, record: longest)

        var wall = ""
        if ranked.count >= 5 {
            var tiles = ""
            for record in ranked.prefix(12) {
                tiles += "<div class='poster'><img src='\(image(record.art))' alt='\(escape(record.title))'><div class='poster-caption'>\(escape(record.title))<small>\(stars(record.rating))</small></div></div>"
            }
            wall = """
            <section class="section">
              <div class="section-head"><h3>整合海报</h3><span class="en">Poster</span><span class="count">\(records.count) \(noun)</span></div>
              <div class="poster-grid">\(tiles)</div>
            </section>
            """
        }

        var calendar = ""
        if query.scope == .month {
            let calendarValue = Calendar.current
            let monthDate = calendarValue.date(from: DateComponents(year: query.year, month: query.month, day: 1)) ?? Date()
            let dayRange = calendarValue.range(of: .day, in: .month, for: monthDate) ?? 1..<31
            let firstWeekday = (calendarValue.component(.weekday, from: monthDate) + 5) % 7
            let grouped = Dictionary(grouping: records) { calendarValue.component(.day, from: $0.effectiveDate) }
            var cells = ""
            for index in 0..<firstWeekday {
                cells += "<div class='cal-cell is-blank'></div>"
            }
            for day in dayRange {
                let dayItems = (grouped[day] ?? []).sorted { $0.rating > $1.rating }
                let column = (firstWeekday + day - 1) % 7
                let weekend = column >= 5
                if let first = dayItems.first {
                    cells += "<div class='cal-cell has-items\(weekend ? " is-weekend" : "")'><span class='cal-day'>\(day)</span><div class='cal-strip' style='--n:1'><img src='\(image(first.art))' alt=''></div></div>"
                } else {
                    cells += "<div class='cal-cell is-quiet\(weekend ? " is-weekend" : "")'><span class='cal-day'>\(day)</span></div>"
                }
            }
            var weekdays = ""
            for value in ["一", "二", "三", "四", "五", "六", "日"] { weekdays += "<div>\(value)</div>" }
            calendar = """
            <section class="section">
              <div class="section-head"><h3>\(query.mediaType.label)日历</h3><span class="en">Monthly</span><span class="count">\(records.count) \(noun)</span></div>
              <div class="calendar-card">
                <div class="cal-weekhead">\(weekdays)</div>
                <div class="cal-grid">\(cells)</div>
              </div>
            </section>
            """
        } else {
            let calendarValue = Calendar.current
            var byYear: [Int: [MediaRecord]] = [:]
            for record in records {
                let year = calendarValue.component(.year, from: record.effectiveDate)
                byYear[year, default: []].append(record)
            }
            var rows = ""
            for year in byYear.keys.sorted(by: >) {
                let yearItems = byYear[year] ?? []
                var cells = ""
                for month in 1...12 {
                    let monthItems = yearItems.filter { calendarValue.component(.month, from: $0.effectiveDate) == month }
                    if let first = monthItems.first {
                        cells += "<div class='year-month'><span class='ym-month'>\(month) 月</span><span class='ym-count'>\(monthItems.count)</span><div class='ym-thumbs'><img src='\(image(first.art))' alt=''></div></div>"
                    } else {
                        cells += "<div class='year-month is-quiet'><span class='ym-month'>\(month) 月</span></div>"
                    }
                }
                rows += "<div class='year-row'><div class='year-label'><b>\(year)</b><span>\(yearItems.count) \(noun)</span></div>\(cells)</div>"
            }
            var heads = "<span>年份</span>"
            for month in 1...12 { heads += "<span>\(month)</span>" }
            calendar = """
            <section class="section">
              <div class="section-head"><h3>\(query.mediaType.label)月历</h3><span class="en">Year Calendar</span><span class="count">\(records.count) \(noun)</span></div>
              <div class="years-scroll"><div class="years-calendar"><div class="years-head">\(heads)</div>\(rows)</div></div>
            </section>
            """
        }

        var decades = ""
        var decadeCounts: [Int: Int] = [:]
        for record in records {
            guard let raw = record.year, let year = Int(raw) else { continue }
            decadeCounts[(year / 10) * 10, default: 0] += 1
        }
        if !decadeCounts.isEmpty {
            let total = decadeCounts.values.reduce(0, +)
            var segments = ""
            var legend = ""
            for decade in decadeCounts.keys.sorted(by: >) {
                let count = decadeCounts[decade] ?? 0
                let className = decade >= 2020 ? "d2020" : (decade >= 2010 ? "d2010" : (decade >= 2000 ? "d2000" : (decade >= 1990 ? "d1990" : (decade >= 1980 ? "d1980" : "d1970"))))
                segments += "<div class='decade-seg \(className)' style='flex:\(count)'><em>\(count >= 2 ? "\(decade)s" : "")</em></div>"
                legend += "<span class='decade-item'><i class='decade-dot \(className)'></i>\(decade)s <b>\(count)</b></span>"
            }
            decades = """
            <section class="prefs">
              <div class="prefs-block"><h3>年代构成<span class="en">Decades</span></h3><div class="decade-bar">\(segments)</div><div class="decade-legend">\(legend)</div><p class="prefs-note">共 \(total) 条带年份的记录。</p></div>
            </section>
            """
        }

        var quoteCards = ""
        for record in comments.prefix(6) {
            quoteCards += """
            <article class="quote-card">
              <span class="quote-mark">“</span>
              <p class="quote-text">\(escape(short(record.comment, limit: 180)))</p>
              <div class="quote-foot"><span class="quote-source">\(escape(record.title))</span><span class="quote-date">\(escape(record.displayDate))</span><span class="quote-stars">\(stars(record.rating))</span></div>
            </article>
            """
        }
        let quotes = quoteCards.isEmpty ? "<p class='panel-empty'>这个范围还没有短评。</p>" : "<div class='quotes-grid'>\(quoteCards)</div>"

        let empty = records.isEmpty ? "<div class='empty'>这个范围还没有记录</div>" : ""

        return """
        <!doctype html>
        <html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>\(escape(period.sub))</title>
        <style>
        :root { --bg:\(bg); --panel:\(panel); --panel2:\(panel2); --line:\(line); --line-soft:\(lineSoft); --text:\(text); --muted:\(muted); --dim:\(dim); --gold:\(gold); --red:\(red); --teal:\(teal); --blue:\(blue); --purple:\(purple); }
        * { box-sizing:border-box; }
        body { margin:0; color:var(--text); line-height:1.55; background:radial-gradient(900px 420px at 8% -6%, rgba(229,180,95,.10) 0%, transparent 55%), radial-gradient(760px 380px at 92% -4%, rgba(223,96,83,.09) 0%, transparent 55%), radial-gradient(1000px 600px at 50% 120%, rgba(85,183,165,.06) 0%, transparent 60%), var(--bg); font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','PingFang SC','Hiragino Sans GB','Microsoft YaHei',sans-serif; }
        a { color:inherit; text-decoration:none; } img { display:block; }
        .wrap { max-width:1180px; margin:0 auto; padding:0 24px 64px; }
        .hero { display:flex; justify-content:space-between; align-items:flex-end; gap:24px; padding:44px 0 26px; border-bottom:1px solid var(--line); }
        .brand { display:flex; align-items:center; gap:14px; }
        .avatar { position:relative; width:48px; height:48px; border-radius:50%; display:flex; align-items:center; justify-content:center; overflow:hidden; font-family:Georgia,serif; font-size:22px; color:var(--gold); background:linear-gradient(145deg, rgba(229,180,95,.22), rgba(223,96,83,.16)); border:1px solid rgba(229,180,95,.45); }
        .avatar span { position:relative; z-index:1; }
        .avatar img { position:absolute; inset:0; width:100%; height:100%; object-fit:cover; }
        .brand-name { font-size:16px; font-weight:600; }
        .brand-line { font-size:10px; letter-spacing:.22em; color:var(--gold); text-transform:uppercase; }
        .period-block { text-align:right; }
        .big-period { line-height:.8; letter-spacing:-.045em; font-weight:800; font-size:clamp(44px,8vw,104px); color:var(--gold); font-variant-numeric:tabular-nums; }
        .period-sub { margin:10px 0 0; color:var(--muted); font-size:12px; }
        .kpis { display:grid; grid-template-columns:repeat(4,1fr); border-bottom:1px solid var(--line); }
        .kpi { padding:18px 22px 20px; border-left:1px solid var(--line); }
        .kpi:nth-child(4n+1) { border-left:none; } .kpi:nth-child(n+5) { border-top:1px solid var(--line); }
        .kpi-label { display:block; font-size:10px; letter-spacing:.16em; color:var(--dim); text-transform:uppercase; }
        .kpi-value { display:block; margin-top:6px; font-size:23px; font-weight:700; font-variant-numeric:tabular-nums; }
        .kpi-value small { font-size:11px; color:var(--muted); font-weight:400; margin-left:3px; }
        .kpi-sub { display:block; margin-top:3px; font-size:11px; color:var(--dim); }
        .feature { display:grid; grid-template-columns:300px 1fr; gap:20px; margin-top:28px; align-items:stretch; }
        .top-panel { display:flex; flex-direction:column; background:var(--panel); border:1px solid var(--line); border-radius:16px; padding:18px 20px; }
        .top-list { flex:1; display:flex; flex-direction:column; justify-content:space-evenly; }
        .panel-head { display:flex; align-items:baseline; gap:10px; margin-bottom:6px; }
        .panel-head h3 { margin:0; font-size:15px; } .panel-head .en { font-size:10px; letter-spacing:.2em; color:var(--dim); text-transform:uppercase; }
        .featured-card { position:relative; display:flex; flex-direction:column; gap:9px; padding:15px; border:1px solid rgba(229,180,95,.32); border-radius:16px; background:linear-gradient(180deg, rgba(229,180,95,.08), rgba(18,23,34,.9) 46%); }
        .featured-tag { position:absolute; top:25px; left:25px; z-index:2; font-size:10px; letter-spacing:.14em; color:var(--gold); background:rgba(8,11,17,.82); border:1px solid rgba(229,180,95,.6); border-radius:4px; padding:3px 7px; text-transform:uppercase; }
        .featured-poster { width:100%; aspect-ratio:2/3; object-fit:contain; background:rgba(255,255,255,.035); border-radius:10px; }
        .featured-title { margin:2px 0 0; font-size:16px; font-weight:650; line-height:1.4; }
        .featured-meta { display:flex; gap:8px; flex-wrap:wrap; align-items:center; font-size:11px; color:var(--muted); }
        .featured-comment { margin:3px 0 0; font-size:11.5px; color:var(--muted); line-height:1.65; display:-webkit-box; -webkit-line-clamp:4; -webkit-box-orient:vertical; overflow:hidden; }
        .top-row { display:grid; grid-template-columns:34px 38px minmax(0,1fr) auto; gap:12px; align-items:center; padding:11px 0; border-top:1px solid var(--line-soft); }
        .top-row:first-child { border-top:none; }
        .rank { font-size:19px; font-weight:800; color:var(--gold); font-variant-numeric:tabular-nums; }
        .top-thumb { width:38px; height:54px; object-fit:contain; background:rgba(255,255,255,.035); border-radius:5px; }
        .top-main { min-width:0; display:flex; flex-direction:column; gap:3px; }
        .top-title { font-size:13px; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .top-meta { font-size:11px; color:var(--muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .top-stars { font-size:12px; white-space:nowrap; }
        .stars { color:var(--gold); }
        .highlights { display:grid; grid-template-columns:repeat(3,1fr); gap:14px; margin-top:16px; }
        .highlight { display:grid; grid-template-columns:74px minmax(0,1fr); gap:12px; padding:14px; background:var(--panel); border:1px solid var(--line); border-radius:14px; }
        .highlight img { width:74px; height:106px; object-fit:contain; background:rgba(255,255,255,.035); border-radius:7px; }
        .highlight-main { min-width:0; display:flex; flex-direction:column; gap:4px; }
        .highlight-kind { font-size:9.5px; letter-spacing:.15em; color:var(--gold); text-transform:uppercase; }
        .highlight h4 { margin:1px 0; font-size:13px; line-height:1.35; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .highlight-meta { font-size:10.5px; color:var(--muted); }
        .highlight p { margin:3px 0 0; font-size:11px; line-height:1.55; color:var(--muted); display:-webkit-box; -webkit-line-clamp:3; -webkit-box-orient:vertical; overflow:hidden; }
        .section { margin-top:34px; }
        .section-head { display:flex; align-items:baseline; gap:10px; margin-bottom:14px; }
        .section-head::before { content:''; width:7px; height:7px; border-radius:2px; background:var(--gold); display:inline-block; }
        .section-head h3 { margin:0; font-size:19px; font-weight:700; }
        .section-head .en { font-size:10px; letter-spacing:.2em; color:var(--dim); text-transform:uppercase; }
        .section-head .count { margin-left:auto; font-size:11px; color:var(--muted); }
        .poster-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(82px,1fr)); gap:10px; }
        .poster { position:relative; border-radius:8px; overflow:hidden; border:1px solid var(--line); background:rgba(255,255,255,.035); }
        .poster img { width:100%; aspect-ratio:2/3; object-fit:contain; }
        .poster-caption { position:absolute; inset:auto 0 0; padding:22px 6px 6px; font-size:9.5px; line-height:1.35; background:linear-gradient(transparent, rgba(5,7,11,.94)); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .poster-caption small { display:block; color:var(--muted); font-size:8.5px; }
        .calendar-card { background:var(--panel); border:1px solid var(--line); border-radius:16px; padding:18px; }
        .cal-weekhead { display:grid; grid-template-columns:repeat(7,1fr); gap:8px; margin-bottom:8px; font-size:10px; color:var(--dim); text-align:center; }
        .cal-grid { display:grid; grid-template-columns:repeat(7,1fr); gap:8px; }
        .cal-cell { position:relative; min-height:68px; overflow:hidden; border:1px solid var(--line); border-radius:9px; background:rgba(255,255,255,.015); }
        .cal-cell.is-weekend { background:rgba(223,96,83,.045); border-color:rgba(223,96,83,.14); }
        .cal-cell.is-blank { border-color:transparent; background:transparent; }
        .cal-cell.is-quiet { padding:6px; } .cal-cell.is-quiet .cal-day { position:absolute; top:3px; right:5px; left:auto; color:var(--dim); text-shadow:none; }
        .cal-day { position:absolute; top:3px; right:5px; left:auto; z-index:3; font-size:9px; color:#e4e1d8; opacity:.55; text-shadow:0 1px 4px rgba(0,0,0,.85); }
        .cal-cell.has-items .cal-day { padding:0; background:none; }
        .cal-strip { position:absolute; inset:0; display:grid; grid-template-columns:repeat(var(--n),1fr); gap:1px; }
        .cal-strip img { width:100%; height:100%; object-fit:cover; opacity:.92; }
        .cal-cell.has-items::after { content:''; position:absolute; inset:0; z-index:1; pointer-events:none; background:linear-gradient(180deg, rgba(5,7,11,.6), transparent 42%, transparent 68%, rgba(5,7,11,.3)); }
        .cal-count, .ym-count { display:none; }
        .years-scroll { overflow-x:auto; }
        .years-calendar { min-width:720px; background:var(--panel); border:1px solid var(--line); border-radius:16px; padding:14px 18px; }
        .years-head, .year-row { display:grid; grid-template-columns:88px repeat(12,minmax(0,1fr)); gap:6px; }
        .years-head { padding:4px 0 8px; border-bottom:1px solid var(--line-soft); font-size:9.5px; color:var(--dim); text-align:center; }
        .years-head span:first-child { text-align:left; }
        .year-row { padding:8px 0; border-top:1px solid var(--line-soft); }
        .year-label { display:flex; flex-direction:column; justify-content:center; }
        .year-label b { font-size:15px; color:var(--gold); } .year-label span { font-size:9.5px; color:var(--muted); }
        .year-month { position:relative; min-height:76px; overflow:hidden; padding:5px; border:1px solid var(--line-soft); border-radius:7px; background:rgba(255,255,255,.015); }
        .year-month.is-quiet { color:var(--dim); }
        .ym-month { font-size:9.5px; color:var(--muted); } .ym-count { position:absolute; top:5px; right:6px; font-size:9px; color:var(--gold); }
        .ym-thumbs { position:absolute; left:5px; right:5px; bottom:5px; display:flex; gap:2px; }
        .ym-thumbs img { width:20px; height:28px; object-fit:cover; border-radius:2px; opacity:.9; }
        .prefs { margin-top:34px; padding:22px 0 24px; border-top:1px solid var(--line); border-bottom:1px solid var(--line); }
        .prefs-block h3 { margin:0 0 12px; font-size:15px; font-weight:600; }
        .prefs-block h3 .en { margin-left:8px; font-size:9.5px; letter-spacing:.18em; color:var(--dim); text-transform:uppercase; }
        .decade-bar { display:flex; height:24px; border-radius:6px; overflow:hidden; background:rgba(255,255,255,.05); margin-bottom:10px; }
        .decade-seg { display:flex; align-items:center; justify-content:center; height:100%; min-width:0; }
        .decade-seg em { font-style:normal; font-size:10px; font-weight:600; color:rgba(8,11,17,.82); }
        .decade-legend { display:flex; flex-wrap:wrap; gap:6px 14px; }
        .decade-item { display:flex; align-items:center; gap:5px; font-size:11px; color:var(--muted); }
        .decade-item b { color:var(--text); font-weight:600; }
        .decade-dot { width:8px; height:8px; border-radius:2px; display:inline-block; flex:none; }
        .d2020 { background:var(--gold); } .d2010 { background:#d98a4a; } .d2000 { background:var(--purple); } .d1990 { background:var(--blue); } .d1980 { background:var(--teal); } .d1970 { background:#6b7a99; }
        .prefs-note { margin:10px 0 0; font-size:10.5px; color:var(--dim); line-height:1.6; }
        .quotes-grid { display:grid; grid-template-columns:repeat(3,1fr); gap:14px; }
        .quote-card { display:flex; flex-direction:column; gap:9px; padding:16px; background:var(--panel); border:1px solid var(--line); border-radius:14px; }
        .quote-mark { font-family:Georgia,serif; font-size:34px; line-height:.6; color:var(--gold); opacity:.55; }
        .quote-text { margin:0; font-size:11.5px; line-height:1.7; color:var(--muted); display:-webkit-box; -webkit-line-clamp:6; -webkit-box-orient:vertical; overflow:hidden; }
        .quote-foot { display:grid; grid-template-columns:minmax(0,1fr) auto auto; align-items:center; gap:6px; margin-top:auto; padding-top:8px; border-top:1px solid var(--line-soft); font-size:10px; color:var(--muted); }
        .quote-source { min-width:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .empty { color:var(--muted); font-size:13px; padding:36px 0; text-align:center; }
        footer { margin-top:44px; padding-top:16px; border-top:1px solid var(--line); font-size:10px; color:var(--dim); display:flex; justify-content:space-between; gap:16px; flex-wrap:wrap; }
        @media (max-width:960px) {
          .kpis { grid-template-columns:repeat(2,1fr); } .kpi:nth-child(2n+1){border-left:none;} .kpi:nth-child(n+3){border-top:1px solid var(--line);}
          .feature { grid-template-columns:260px 1fr; } .highlights, .quotes-grid { grid-template-columns:1fr 1fr; }
        }
        @media (max-width:720px) {
          .wrap { padding:0 14px 48px; } .hero { flex-direction:column; align-items:flex-start; padding-top:30px; } .period-block { text-align:left; }
          .feature { grid-template-columns:1fr; } .featured-card { max-width:340px; }
          .highlights, .quotes-grid { grid-template-columns:1fr; } .poster-grid { grid-template-columns:repeat(4,1fr); gap:7px; }
        }
        </style></head>
        <body><div class="wrap">
        <header class="hero">
          <div class="brand">\(avatarHTML)<div><div class="brand-name">\(escape(ownerName))</div><div class="brand-line">PRIVATE ARCHIVE · REPORT</div></div></div>
          <div class="period-block"><div class="big-period">\(escape(period.big))</div></div>
        </header>
        <section class="kpis">\(kpis)</section>
        \(empty)
        <section class="feature">
          \(ranked.first.map { featuredHTML($0) } ?? "<p class='panel-empty'>暂无记录</p>")
          <div class="top-panel"><div class="panel-head"><h3>TOP 5</h3><span class="en">Top Rated</span></div><div class="top-list">\(topRows)</div></div>
        </section>
        <section class="highlights">\(highlights)</section>
        \(wall)
        \(calendar)
        \(decades)
        <section class="section"><div class="section-head"><h3>短评摘录</h3><span class="en">Notes</span><span class="count">\(comments.count) 条短评</span></div>\(quotes)</section>
        <footer><span>数据来自「书影记录」\(escape(query.mediaType.label))记录 · 共 \(records.count) \(noun)</span><span>\(escape(dateString(Date())))</span></footer>
        </div></body></html>
        """
    }

    private static func reportPeriod(query: ReportQuery, records: [MediaRecord]) -> (big: String, sub: String) {
        let noun = query.mediaType.noun
        switch query.scope {
        case .month:
            return (String(format: "%04d.%02d", query.year, query.month), "\(query.year) 年 \(query.month) 月 · \(records.count) \(noun)\(query.mediaType.label)记录")
        case .year:
            return ("\(query.year)", "\(query.year) 年 · \(records.count) \(noun)\(query.mediaType.label)记录")
        case .custom:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy.MM"
            return ("\(formatter.string(from: query.startDate))–\(formatter.string(from: query.endDate))", "\(dateString(query.startDate)) — \(dateString(query.endDate)) · 自定义范围 · \(records.count) \(noun)")
        case .all:
            let years = records.map { Calendar.current.component(.year, from: $0.effectiveDate) }
            guard let newest = years.max(), let oldest = years.min() else { return ("ALL", "全部记录 · 0 \(noun)") }
            let span = newest == oldest ? "\(newest)" : "\(oldest) — \(newest)"
            return ("ALL", "\(span) · 全部记录 · \(records.count) \(noun)")
        }
    }

    private static func kpiHTML(label: String, value: String, unit: String, sub: String) -> String {
        let unitHTML = unit.isEmpty ? "" : "<small>\(escape(unit))</small>"
        let subHTML = sub.isEmpty ? "" : "<span class='kpi-sub'>\(escape(sub))</span>"
        return "<div class='kpi'><span class='kpi-label'>\(escape(label))</span><span class='kpi-value'>\(escape(value))\(unitHTML)</span>\(subHTML)</div>"
    }

    private static func short(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "…"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: date)
    }

    private static func stars(_ rating: Int) -> String {
        String(repeating: "★", count: max(0, min(5, rating))) + String(repeating: "☆", count: max(0, 5 - rating))
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func reportsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("BookFilmJournal", isDirectory: true)
            .appendingPathComponent("Reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func posterDataURI(_ art: PosterArt) -> String {
        #if canImport(UIKit)
        let renderer = ImageRenderer(content: PosterArtwork(art: art).frame(width: 240, height: 360))
        renderer.scale = 1.5
        guard let image = renderer.uiImage, let data = image.pngData() else { return "" }
        return "data:image/png;base64,\(data.base64EncodedString())"
        #else
        return ""
        #endif
    }
}
