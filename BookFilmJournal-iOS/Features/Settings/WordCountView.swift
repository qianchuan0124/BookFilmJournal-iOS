import SwiftUI
import Observation
import UniformTypeIdentifiers

private enum WordCountSheet: Identifiable {
    case results(UUID, [WordCountBookResult])
    case folders

    var id: String {
        switch self {
        case .results(let id, _): "results-\(id.uuidString)"
        case .folders: "folders"
        }
    }
}

struct WordCountView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?
    @State private var showClearConfirm = false
    @State private var folderStore = WordCountFolderStore()
    @State private var isWorking = false
    @State private var results: [WordCountBookResult] = []
    @State private var activeSheet: WordCountSheet?
    @State private var history = WordCountHistoryStore.shared

    private var wordCountSummary: (count: Int, total: Int, all: Int) {
        var keys: [String] = []
        var words: [String: Int] = [:]
        var seen = Set<String>()

        func add(title: String, subjectID: String, wordCount: Int?) {
            let key = summaryKey(title: title, subjectID: subjectID)
            guard !key.isEmpty else { return }
            if seen.insert(key).inserted { keys.append(key) }
            if let wordCount, wordCount > 0 {
                words[key] = max(words[key] ?? 0, wordCount)
            }
        }

        for record in store.records where !record.isDeleted && record.mediaType == .book {
            add(title: record.title, subjectID: record.subjectID, wordCount: record.wordCount)
        }
        let activeListIDs = Set(store.doulists.filter { $0.deletedAt == nil }.map(\.id))
        for item in store.doulistItems where item.mediaType == .book && activeListIDs.contains(item.doulistID) {
            add(title: item.title, subjectID: item.subjectID, wordCount: item.wordCount)
        }

        let counted = keys.compactMap { words[$0] }
        return (counted.count, counted.reduce(0, +), keys.count)
    }

    private func summaryKey(title: String, subjectID: String) -> String {
        let id = subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return "id:\(id)" }
        let normalized = title.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? "" : "title:\(normalized)"
    }

    private func wordText(_ words: Int) -> String {
        if words >= 10_000 {
            return L10n.Stats.tenThousandFormat(Double(words) / 10_000)
        }
        return L10n.WordCount.wordsSuffix(String(describing: words))
    }

    var body: some View {
        PageScaffold {
            VStack(alignment: .leading, spacing: 8) {
                NavHeader(title: L10n.WordCount.title, backLabel: L10n.Tab.settings, trailing: AnyView(
                    Image(systemName: "doc.text")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                ))

                InfoGroup {
                    FieldRow(label: L10n.WordCount.fileSource) {
                        Text(L10n.WordCount.filesApp)
                            .foregroundStyle(Theme.text)
                    }
                    FieldRow(label: L10n.WordCount.supportedFormats) {
                        Text("EPUB · TXT · DOCX")
                            .foregroundStyle(Theme.text)
                    }
                    FieldRow(label: L10n.WordCount.matchingMode, showDivider: false) {
                        Text(L10n.WordCount.matchByFilename)
                            .foregroundStyle(Theme.text)
                    }
                }
                .padding(.horizontal, 16)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.WordCount.importHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.WordCount.countedBooksCount(String(describing: wordCountSummary.count)))
                            .font(.appBody)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(wordText(wordCountSummary.total))
                            .font(.appBody)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.gold)
                    }
                    ProgressView(value: min(1, Double(wordCountSummary.count) / Double(max(1, wordCountSummary.all))))
                        .tint(Theme.teal)
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)
                    HStack {
                        Text(L10n.WordCount.countedBooks)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                        Spacer()
                        Text("\(wordCountSummary.count) / \(wordCountSummary.all)")
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                }
                .padding(14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if !history.entries.isEmpty {
                    SectionHeading(title: L10n.WordCount.statisticsHistory, trailing: L10n.WordCount.times(String(describing: history.entries.count)))
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    VStack(spacing: 8) {
                        ForEach(history.entries) { entry in
                            Button {
                                activeSheet = .results(entry.id, entry.results)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title)
                                            .font(.appBodySmall)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.text)
                                        Text(entry.summary)
                                            .font(.appCaption)
                                            .foregroundStyle(Theme.text3)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.text4)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Text(L10n.WordCount.writeBackHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    Button {
                        scanAllFolders()
                    } label: {
                        Label(L10n.WordCount.countAction, systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(GoldButtonStyle(height: 44, radius: 12, font: .system(size: 15, weight: .semibold)))
                    .disabled(isWorking)

                    Button {
                        activeSheet = .folders
                    } label: {
                        Label(L10n.WordCount.countFolders, systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(OutlineButtonStyle(height: 44, radius: 12, foreground: Theme.gold, font: .system(size: 15, weight: .semibold)))
                    .disabled(isWorking)

                    Button {
                        showClearConfirm = true
                    } label: {
                        Label(L10n.WordCount.clearAll, systemImage: "trash")
                    }
                    .buttonStyle(OutlineButtonStyle(height: 44, radius: 12, foreground: Theme.danger, font: .system(size: 15, weight: .semibold)))
                    .disabled(isWorking)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .toast(message: $toast)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .results(_, let results):
                WordCountResultsSheet(results: results)
                    .presentationDetents([.large])
            case .folders:
                WordCountFoldersView(folders: folderStore)
                    .presentationDetents([.large])
            }
        }
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.WordCount.countingWords)
                            .font(.appBodySmall)
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .alert(L10n.WordCount.clearConfirm, isPresented: $showClearConfirm) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.clear, role: .destructive) {
                WordCountService.clearWordCounts(in: store)
                results = []
                toast = L10n.WordCount.wordsCleared
            }
        } message: {
            Text(L10n.WordCount.clearMessage)
        }
    }

    private func scanAllFolders() {
        let urls = folderStore.allURLs()
        guard !urls.isEmpty else {
            toast = L10n.WordCount.addFolderFirst
            activeSheet = .folders
            return
        }
        isWorking = true
        results = []
        DispatchQueue.main.async {
            let outcome = WordCountService.importFolders(urls, into: store)
            isWorking = false
            results = outcome.books
            history.add(results: outcome.books)
            activeSheet = .results(UUID(), outcome.books)
            toast = outcome.updated.isEmpty ? L10n.WordCount.noMatch : L10n.WordCount.complete
        }
    }
}

struct WordCountFoldersView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folders: WordCountFolderStore
    private let history = WordCountHistoryStore.shared

    @State private var showImporter = false
    @State private var isWorking = false
    @State private var results: [WordCountBookResult] = []
    @State private var showResults = false
    @State private var fileCounts: [UUID: Int] = [:]
    @State private var toast: String?

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.WordCount.countFolders,
                    leftTitle: L10n.Common.close,
                    rightTitle: L10n.WordCount.countAction,
                    rightDisabled: folders.selectedCount == 0 || isWorking,
                    onLeft: { dismiss() },
                    onRight: { scan() }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.WordCount.chooseFoldersHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    Button {
                        showImporter = true
                    } label: {
                        Label(L10n.WordCount.addFolder, systemImage: "folder.badge.plus")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.goldDeep)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Theme.goldSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Spacer()

                    if !folders.folders.isEmpty {
                        Button(folders.selectedCount == folders.folders.count ? L10n.WordCount.deselectAll : L10n.WordCount.selectAll) {
                            folders.selectAll(folders.selectedCount != folders.folders.count)
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.goldDeep)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if folders.folders.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: L10n.WordCount.noFoldersSelected,
                        detail: L10n.WordCount.addFolderHint
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(folders.folders) { folder in
                            folderRow(folder)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Text(L10n.WordCount.folderAccessHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
            .padding(.top, 4)
        }
        .toast(message: $toast)
        .task(id: folders.folders.map(\.id)) {
            let snapshot = folders.folders
            var counts: [UUID: Int] = [:]
            for folder in snapshot {
                guard let url = folders.resolve(folder) else { continue }
                counts[folder.id] = WordCountService.matchableFileCount(in: url)
            }
            fileCounts = counts
        }
        .sheet(isPresented: $showResults) {
            WordCountResultsSheet(results: results)
                .presentationDetents([.large])
        }
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.WordCount.countingFolders)
                            .font(.appBodySmall)
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let errors = folders.add(urls: urls)
                if errors.isEmpty {
                    toast = L10n.WordCount.foldersAddedCount(String(describing: urls.count))
                } else {
                    toast = L10n.WordCount.someFoldersFailed
                }
            case .failure(let error):
                toast = error.localizedDescription
            }
        }
    }

    private func wordText(_ words: Int) -> String {
        if words >= 10_000 {
            return L10n.Stats.tenThousandFormat(Double(words) / 10_000)
        }
        return L10n.WordCount.wordsSuffix(String(describing: words))
    }

    private func folderRow(_ folder: WordCountFolder) -> some View {
        HStack(spacing: 10) {
            Button {
                folders.toggle(id: folder.id)
            } label: {
                Image(systemName: folder.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(folder.isSelected ? Theme.goldBright : Theme.borderStrong)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder.fill")
                .font(.system(size: 17))
                .foregroundStyle(Theme.gold)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.appBody)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(folder.isSelected ? "已选择" : "未选择") · \(fileCounts[folder.id].map { "\($0) 个可匹配文件" } ?? "正在扫描…")")
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
            }

            Spacer()

            Button {
                folders.remove(id: folder.id)
                toast = L10n.WordCount.folderRemoved
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func scan() {
        let urls = folders.selectedURLs()
        guard !urls.isEmpty else {
            toast = L10n.WordCount.selectFolderFirst
            return
        }
        isWorking = true
        results = []
        DispatchQueue.main.async {
            let outcome = WordCountService.importFolders(urls, into: store)
            isWorking = false
            results = outcome.books
            history.add(results: outcome.books)
            showResults = true
            toast = outcome.updated.isEmpty ? L10n.WordCount.noMatch : L10n.WordCount.complete
        }
    }
}


struct WordCountHistoryEntry: Identifiable {
    let id = UUID()
    let date: Date
    let results: [WordCountBookResult]

    var title: String {
        Self.formatter.string(from: date)
    }

    var summary: String {
        let success = results.filter { $0.state == .success }.count
        let unfinished = results.filter { $0.state != .success && $0.state != .existing }.count
        return L10n.WordCount.summaryLong(String(describing: success), String(describing: unfinished), String(describing: results.count))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

@Observable
final class WordCountHistoryStore {
    static let shared = WordCountHistoryStore()
    private init() {}

    var entries: [WordCountHistoryEntry] = []

    func add(results: [WordCountBookResult]) {
        entries.insert(WordCountHistoryEntry(date: Date(), results: results), at: 0)
        if entries.count > 50 { entries.removeLast(entries.count - 50) }
    }
}

struct WordCountResultsSheet: View {
    let results: [WordCountBookResult]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [WordCountBookResult] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return results }
        return results.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
                || ($0.subjectID ?? "").localizedCaseInsensitiveContains(keyword)
                || ($0.fileName ?? "").localizedCaseInsensitiveContains(keyword)
                || ($0.reason ?? "").localizedCaseInsensitiveContains(keyword)
        }
    }

    private var successCount: Int { results.filter { $0.state == .success }.count }
    private var unfinishedCount: Int { results.filter { $0.state != .success && $0.state != .existing }.count }

    private var duplicateTitleKeys: Set<String> {
        var idsByTitle: [String: Set<String>] = [:]
        for result in results {
            guard let subjectID = result.subjectID, !subjectID.isEmpty else { continue }
            let key = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            idsByTitle[key, default: []].insert(subjectID)
        }
        return Set(idsByTitle.filter { $0.value.count > 1 }.keys)
    }

    private func showsSubjectID(_ result: WordCountBookResult) -> Bool {
        guard let subjectID = result.subjectID, !subjectID.isEmpty else { return false }
        let key = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return duplicateTitleKeys.contains(key)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.WordCount.results, leftTitle: L10n.Common.close, onLeft: { dismiss() })
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                SearchField(placeholder: L10n.WordCount.searchPlaceholder, text: $query)

                HStack {
                    Text(L10n.WordCount.summary(String(describing: successCount), String(describing: unfinishedCount), String(describing: results.count)))
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    if !query.isEmpty {
                        Text(L10n.WordCount.matchesCount(String(describing: filtered.count)))
                            .font(.appCaption)
                            .foregroundStyle(Theme.goldDeep)
                    }
                }

                if filtered.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: L10n.WordCount.noMatches, detail: L10n.WordCount.tryAnotherKeyword)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { result in
                            resultRow(result)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func resultRow(_ result: WordCountBookResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: result.state))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color(for: result.state))
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    Text(highlight(result.title))
                        .font(.appBodySmall)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let words = result.words {
                        Text(wordText(words))
                            .font(.appCaption)
                            .foregroundStyle(result.state == .existing ? Theme.text3 : Theme.gold)
                    } else {
                        Text(label(for: result.state))
                            .font(.appCaption)
                            .foregroundStyle(color(for: result.state))
                    }
                }
                if showsSubjectID(result), let subjectID = result.subjectID {
                    Text(L10n.WordCount.doubanID(String(describing: subjectID)))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.text4)
                        .lineLimit(1)
                }
                if let fileName = result.fileName, !fileName.isEmpty {
                    Text(highlight(fileName))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text4)
                        .lineLimit(1)
                }
                if let reason = result.reason, result.state == .missing || result.state == .failed {
                    Text(highlight(reason))
                        .font(.system(size: 10.5))
                        .foregroundStyle(result.state == .failed ? Theme.danger : Theme.text3)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func highlight(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return attributed }
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: keyword, options: [.caseInsensitive], range: start..<text.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].foregroundColor = Theme.goldDeep
                attributed[lower..<upper].backgroundColor = Theme.goldSoft
            }
            start = range.upperBound
        }
        return attributed
    }

    private func icon(for state: WordCountBookState) -> String {
        switch state {
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .missing: "questionmark.circle"
        case .existing: "checkmark.seal"
        }
    }

    private func color(for state: WordCountBookState) -> Color {
        switch state {
        case .success: Theme.read
        case .failed: Theme.danger
        case .missing: Theme.text3
        case .existing: Theme.teal
        }
    }

    private func label(for state: WordCountBookState) -> String {
        switch state {
        case .success: L10n.WordCount.success
        case .failed: L10n.WordCount.failure
        case .missing: L10n.WordCount.notFound
        case .existing: L10n.WordCount.existing
        }
    }

    private func wordText(_ words: Int) -> String {
        if words >= 10_000 {
            return L10n.Stats.tenThousandFormat(Double(words) / 10_000)
        }
        return L10n.WordCount.wordsSuffix(String(describing: words))
    }
}
