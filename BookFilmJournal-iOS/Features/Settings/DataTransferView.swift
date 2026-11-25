import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct DataTransferView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var excelURL: URL?
    @State private var showImport = false
    @State private var importSummary = ""
    @State private var importFailures: [String] = []
    @State private var toast: String?

    var body: some View {
        PageScaffold {
            NavHeader(title: L10n.Settings.dataTransfer, backLabel: L10n.Tab.settings, trailing: AnyView(
                Image(systemName: "tablecells")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.gold)
            ))
            .padding(.horizontal, 0)
        } content: {
            VStack(spacing: 14) {
                exportCard
                importCard

                if !importSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(importSummary)
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.text)
                        ForEach(importFailures.prefix(6), id: \.self) { line in
                            Text(line)
                                .font(.appCaption)
                                .foregroundStyle(Theme.danger)
                        }
                        if importFailures.count > 6 {
                            Text(L10n.Data.extraUnimported(String(describing: importFailures.count - 6)))
                                .font(.appCaption)
                                .foregroundStyle(Theme.text3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }

                Text(L10n.Data.exportFormatHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text4)
                    .lineSpacing(3)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
        }
        .toast(message: $toast)
        .fileImporter(isPresented: $showImport, allowedContentTypes: importTypes) { result in
            switch result {
            case .success(let url):
                importFile(url)
            case .failure(let error):
                importSummary = L10n.Data.importFailed
                importFailures = [error.localizedDescription]
            }
        }
    }

    private var exportCard: some View {
        dataCard(
            icon: "square.and.arrow.up",
            color: Color(hex: 0x4C7ED6),
            title: L10n.Data.exportExcelCSV,
            desc: L10n.Data.exportFormatSubtitle
        ) {
            if let excelURL {
                ShareLink(item: excelURL) {
                    Label(L10n.Data.shareExcel, systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x241804))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            LinearGradient(colors: [Color(hex: 0xF4D083), Color(hex: 0xBC7C1D)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button {
                    self.excelURL = ExcelExportService.makeWorkbook(store: store)
                    if excelURL == nil { toast = L10n.Data.generateExcelFailed }
                } label: {
                    Text(L10n.Data.regenerateExcel)
                        .font(.appCaption)
                        .foregroundStyle(Theme.gold)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    excelURL = ExcelExportService.makeWorkbook(store: store)
                    if excelURL == nil { toast = L10n.Data.generateExcelFailed }
                } label: {
                    Label(L10n.Data.generateExcelCount(String(describing: store.activeRecords().count)), systemImage: "tablecells")
                }
                .buttonStyle(GoldButtonStyle(height: 44, radius: 12, font: .system(size: 15, weight: .semibold)))
            }

            HStack(spacing: 10) {
                Button {
                    exportURL = makeCSV()
                    if exportURL == nil { toast = L10n.Data.generateCSVFailed }
                } label: {
                    Text(L10n.Data.generateCSV)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                }
                .buttonStyle(.plain)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Text(L10n.Data.shareCSV)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                    }
                }
            }
        }
    }

    private var importCard: some View {
        dataCard(
            icon: "square.and.arrow.down",
            color: Theme.teal,
            title: L10n.Data.importFromCSV,
            desc: L10n.Data.importFormatHint
        ) {
            Button {
                showImport = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Theme.text3)
                    Text(L10n.Data.chooseFile)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.subtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func dataCard<Content: View>(
        icon: String,
        color: Color,
        title: String,
        desc: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)
                    Text(desc)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        return types
    }

    private func importFile(_ url: URL) {
        if url.pathExtension.lowercased() == "xlsx" {
            importXLSX(url)
        } else {
            importCSV(url)
        }
    }

    private func importXLSX(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importSummary = L10n.Data.readFailed
            importFailures = []
            toast = L10n.Data.importFailedMessage
            return
        }
        let result = ExcelImportService.importWorkbook(data, into: store)
        importSummary = result.detail.isEmpty ? result.summary : "\(result.summary) · \(result.detail)"
        importFailures = result.failures
        toast = result.failures.isEmpty ? L10n.Data.importComplete : L10n.Data.partialImport
    }

    // MARK: - Export

    private func makeCSV() -> URL? {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"

        var csv = "类型,状态,豆瓣ID,标题,链接,评分,豆瓣标记日期,本地生效日期,本地已调整,短评,简介,时长,页数,字数,年份,来源\n"
        let records = store.activeRecords().sorted { $0.effectiveDate > $1.effectiveDate }
        for record in records {
            let status: String
            switch (record.mediaType, record.status) {
            case (.movie, .done): status = L10n.Data.watched
            case (.movie, .wish): status = L10n.Data.wishToWatch
            case (.book, .done): status = L10n.Data.readDone
            case (.book, .wish): status = L10n.Data.wishToRead
            }
            let row: [String] = [
                record.mediaType.rawValue,
                status,
                record.subjectID,
                record.title,
                record.doubanURL ?? "",
                "\(record.rating)",
                day.string(from: record.markedDate),
                day.string(from: record.effectiveDate),
                record.isLocalEdited ? L10n.Data.yes : L10n.Data.no,
                record.comment,
                record.intro,
                record.durationMinutes.map(String.init) ?? "",
                record.pages.map(String.init) ?? "",
                record.wordCount.map(String.init) ?? "",
                record.year ?? "",
                record.isLocalEdited ? "local" : "douban"
            ]
            csv += row.map(csvEscape).joined(separator: ",") + "\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(L10n.Data.csvFilename)
        do {
            let data = Data(("\u{FEFF}" + csv).utf8)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Import

    private func importCSV(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030) else {
            importSummary = L10n.Data.readFailed
            importFailures = [L10n.Data.invalidTextEncoding]
            toast = L10n.Data.importFailedMessage
            return
        }
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let rows = parseCSV(text)
        guard rows.count > 1 else {
            importSummary = L10n.Data.noRecords
            importFailures = []
            toast = L10n.Data.importFailedMessage
            return
        }

        let header = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        func index(_ names: [String]) -> Int? {
            names.compactMap { header.firstIndex(of: $0) }.first
        }
        guard let titleIndex = index([L10n.Data.title, L10n.Data.movieTitle, L10n.Data.bookTitle]) else {
            importSummary = L10n.Data.missingTitle
            importFailures = []
            toast = L10n.Data.importFailedMessage
            return
        }

        let typeIndex = index([L10n.Data.type, L10n.Data.mediaType])
        let statusIndex = index([L10n.Data.status])
        let subjectIndex = index([L10n.Data.doubanID, L10n.Data.itemID])
        let urlIndex = index([L10n.Data.link])
        let ratingIndex = index([L10n.Data.rating])
        let markedIndex = index([L10n.Data.doubanMarkedDate, L10n.Data.markedDate])
        let effectiveIndex = index([L10n.Data.localEffectiveDate, L10n.Data.effectiveDate])
        let editedIndex = index([L10n.Data.locallyAdjusted])
        let commentIndex = index([L10n.Data.shortComment, L10n.Data.comment])
        let introIndex = index([L10n.Data.summary])
        let durationIndex = index([L10n.Data.duration])
        let pagesIndex = index([L10n.Data.pages])
        let wordIndex = index([L10n.Data.words])
        let yearIndex = index([L10n.Data.year])

        let dateFormatters: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/M/d", "yyyy/MM/dd"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = $0
            return formatter
        }

        var indexByKey: [String: Int] = [:]
        for (offset, record) in store.records.enumerated() {
            indexByKey[recordKey(record)] = offset
        }

        var inserted = 0
        var updated = 0
        var failures: [String] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            func value(_ index: Int?) -> String {
                guard let index, row.indices.contains(index) else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let title = value(titleIndex)
            guard !title.isEmpty else {
                failures.append(L10n.Data.rowMissingTitle(String(describing: line)))
                continue
            }
            let media = parseMediaType(value(typeIndex))
            let status = parseStatus(value(statusIndex))
            let url = value(urlIndex)
            let subjectID = value(subjectIndex).isEmpty
                ? derivedSubjectID(media: media, status: status, title: title, url: url)
                : value(subjectIndex)
            let marked = dateFormatters.compactMap { $0.date(from: value(markedIndex)) }.first ?? Date()
            let effective = dateFormatters.compactMap { $0.date(from: value(effectiveIndex)) }.first ?? marked
            let rating = min(5, max(0, Int(value(ratingIndex)) ?? 0))
            let edited = [L10n.Data.yes, "true", "1", "yes"].contains(value(editedIndex).lowercased())
            let year = value(yearIndex).isEmpty ? nil : value(yearIndex)

            var record = MediaRecord(
                mediaType: media,
                status: status,
                title: title,
                subjectID: subjectID,
                doubanURL: url.isEmpty ? nil : url,
                art: placeholderArt(media: media, subjectID: subjectID, title: title),
                markedDate: marked,
                effectiveDate: effective,
                rating: rating,
                comment: value(commentIndex),
                intro: value(introIndex),
                durationMinutes: Int(value(durationIndex)),
                pages: Int(value(pagesIndex)),
                wordCount: Int(value(wordIndex)),
                year: year,
                isLocalEdited: edited
            )

            let key = recordKey(record)
            if let existingIndex = indexByKey[key] {
                let existing = store.records[existingIndex]
                record.id = existing.id
                record.art = existing.art
                store.records[existingIndex] = record
                updated += 1
            } else {
                indexByKey[key] = store.records.count
                store.records.append(record)
                inserted += 1
            }
        }

        store.save()
        importSummary = L10n.Data.importDone(String(describing: inserted), String(describing: updated))
        importFailures = failures
        toast = failures.isEmpty ? L10n.Data.importComplete : L10n.Data.partialImport
    }

    private func recordKey(_ record: MediaRecord) -> String {
        "\(record.mediaType.rawValue)|\(record.subjectID)|\(record.status.rawValue)"
    }

    private func parseMediaType(_ value: String) -> MediaType {
        let text = value.lowercased()
        if text.contains("book") || text.contains(L10n.Data.read) || text.contains(L10n.Data.book) { return .book }
        return .movie
    }

    private func parseStatus(_ value: String) -> RecordStatus {
        let text = value.lowercased()
        if text.contains("wish") || text.contains(L10n.Data.wish) { return .wish }
        return .done
    }

    private func derivedSubjectID(media: MediaType, status: RecordStatus, title: String, url: String) -> String {
        if let range = url.range(of: #"/subject/(\d+)"#, options: .regularExpression) {
            let match = String(url[range])
            if let id = match.split(separator: "/").last { return String(id) }
        }
        let seed = "\(media.rawValue)|\(status.rawValue)|\(title)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return "local-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func placeholderArt(media: MediaType, subjectID: String, title: String) -> PosterArt {
        let seed = subjectID.isEmpty ? title : subjectID
        let hash = seed.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value }
        let options: [PosterArt] = media == .movie
            ? [.war, .space, .road, .dunes, .mountains, .sea, .bokeh, .forest, .city, .nebula, .anime, .volcano, .stage]
            : [.bookCream, .bookViolet, .bookSand, .bookIvory, .bookCharcoal, .bookSage, .bookTeal]
        return options[Int(hash % UInt32(options.count))]
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if (char == "\n" || char == "\r") && !inQuotes {
                if char == "\r", let peek = iterator.next(), peek != "\n" {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                    continue
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
