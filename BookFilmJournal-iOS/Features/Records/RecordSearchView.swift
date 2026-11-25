import SwiftUI

struct RecordSearchView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let media: MediaType
    var onLocate: ((MediaRecord) -> Void)? = nil
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var selected: MediaRecord?
    @State private var recent: [String] = []

    private static let recentKey = "bookfilm.recentSearches"

    init(media: MediaType, onLocate: ((MediaRecord) -> Void)? = nil) {
        self.media = media
        self.onLocate = onLocate
    }

    private var emptyTitle: String {
        media == .movie ? L10n.Records.searchEmptyMovie : L10n.Records.searchEmptyBook
    }

    private var emptyDetail: String {
        media == .movie ? L10n.Records.searchEmptyMovieDetail : L10n.Records.searchEmptyBookDetail
    }

    private var results: [MediaRecord] {
        let keyword = submittedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return [] }
        return store.activeRecords(media: media)
            .filter { $0.searchText.contains(keyword) }
            .sorted { $0.effectiveDate > $1.effectiveDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()
            HStack(spacing: 10) {
                SearchField(placeholder: L10n.Records.searchTitleOrReview, text: $query, onSubmit: submitSearch)
                Button(L10n.Common.cancel) { dismiss() }
                    .font(.appBodySmall)
                    .foregroundStyle(Theme.gold)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if submittedQuery.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: L10n.Records.recentSearches)
                        if recent.isEmpty {
                            Text(L10n.Records.recentSearchesHint)
                                .font(.appCaption)
                                .foregroundStyle(Theme.text3)
                        } else {
                            ChipBar(
                                items: recent.map { ChipItem(id: $0, label: $0) },
                                selectedID: Binding(
                                    get: { "" },
                                    set: { value in
                                        guard !value.isEmpty else { return }
                                        query = value
                                        submitSearch()
                                    }
                                )
                            )
                        }
                        Text(query.isEmpty
                             ? L10n.Records.searchScopeHint
                             : L10n.Records.searchSubmitHint)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            } else {
                List {
                    SectionHeading(
                        title: L10n.Records.titleAndReviewCount(String(describing: results.count)),
                        trailing: results.isEmpty ? L10n.Records.noResults : L10n.Records.totalCount(String(describing: results.count))
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if results.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: emptyTitle, detail: emptyDetail)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(results) { record in
                            Button {
                                commitSubmittedSearch()
                                selected = record
                            } label: {
                                searchRow(record)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    commitSubmittedSearch()
                                    onLocate?(record)
                                    dismiss()
                                } label: {
                                    Label(L10n.Records.locate, systemImage: "scope")
                                }
                                .tint(Theme.gold)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.sheet)
                .environment(\.defaultMinListRowHeight, 1)
                .contentMargins(.top, 0, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
            }
        }
        .background(Theme.sheet.ignoresSafeArea())
        .sheet(item: $selected) { record in
            RecordDetailView(recordID: record.id)
                .presentationDetents([.large])
        }
        .onAppear(perform: loadRecent)
        .onChange(of: query) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines) != submittedQuery {
                submittedQuery = ""
            }
        }
        .onDisappear(perform: commitSubmittedSearch)
    }

    private func searchRow(_ record: MediaRecord) -> some View {
        HStack(spacing: 10) {
            CoverArtwork(art: record.art, urlString: record.coverRemoteURL, localKey: record.coverLocalKey)
                .frame(width: 46, height: 69)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(record.title, query: submittedQuery))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                if let snippet = snippet(for: record) {
                    Text(highlighted(snippet, query: submittedQuery))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(record.statsText)
                    if record.rating > 0 {
                        Text("·")
                        Text(String(repeating: "★", count: record.rating))
                            .foregroundStyle(Theme.star)
                    }
                    Spacer(minLength: 0)
                    if record.mediaType == .movie {
                        Text(record.displayDate)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func highlighted(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return attributed }
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: keyword, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].foregroundColor = Theme.goldDeep
                attributed[lower..<upper].backgroundColor = Theme.goldSoft
            }
            searchStart = range.upperBound
        }
        return attributed
    }

    private func snippet(for record: MediaRecord) -> String? {
        let keyword = submittedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }
        for source in [record.comment, record.intro] where !source.isEmpty {
            guard let range = source.range(of: keyword, options: [.caseInsensitive]) else { continue }
            let lower = source.index(range.lowerBound, offsetBy: -26, limitedBy: source.startIndex) ?? source.startIndex
            let upper = source.index(range.upperBound, offsetBy: 48, limitedBy: source.endIndex) ?? source.endIndex
            var value = String(source[lower..<upper])
            if lower != source.startIndex { value = "…" + value }
            if upper != source.endIndex { value += "…" }
            return value
        }
        return nil
    }

    private func submitSearch() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            submittedQuery = ""
            return
        }
        submittedQuery = value
        commitSubmittedSearch()
    }

    private func commitSubmittedSearch() {
        let value = submittedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        recent.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        recent.insert(value, at: 0)
        if recent.count > 6 { recent = Array(recent.prefix(6)) }
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }

    private func loadRecent() {
        if let stored = UserDefaults.standard.stringArray(forKey: Self.recentKey) {
            recent = stored
        } else {
            recent = [L10n.Records.wanderingEarth, L10n.Records.dune, L10n.Records.littleForest, L10n.Records.oneHundredYearsOfSolitude]
        }
    }
}
