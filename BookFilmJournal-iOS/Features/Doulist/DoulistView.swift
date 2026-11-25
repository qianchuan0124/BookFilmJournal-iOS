import SwiftUI

private enum DoulistFilter: String, CaseIterable, Identifiable {
    case all, own, following
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: L10n.Doulist.all
        case .own: L10n.Doulist.createdByMe
        case .following: L10n.Doulist.following
        }
    }
}

struct DoulistView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @State private var media: MediaType = .movie
    @State private var filter: DoulistFilter = .all
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var submittedKeyword = ""
    @State private var toast: String?

    private var doulists: [Doulist] {
        let keyword = submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.activeDoulists
            .filter { $0.mediaType == media }
            .filter {
                switch filter {
                case .all: true
                case .own: !$0.isFollowing
                case .following: $0.isFollowing
                }
            }
            .filter { keyword.isEmpty || $0.title.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        PageScaffoldNoScroll {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Doulist.my)
                            .font(.appDisplay)
                            .foregroundStyle(Theme.text)
                        Text(L10n.Doulist.subtitle(store.activeDoulists.count))
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        IconCircleButton(systemName: "magnifyingglass", action: {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showSearch.toggle()
                                if !showSearch {
                                    searchText = ""
                                    submittedKeyword = ""
                                }
                            }
                        })
                        IconCircleButton(systemName: "arrow.triangle.2.circlepath", action: {
                            store.refreshDoulistStats()
                            toast = L10n.Doulist.statsRefreshed
                        })
                    }
                    .padding(.top, 4)
                }
                if showSearch {
                    HStack(spacing: 8) {
                        SearchField(placeholder: L10n.Doulist.searchPlaceholder, text: $searchText, onSubmit: submitSearch)
                        Button(L10n.Common.search, action: submitSearch)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.goldDeep)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(Theme.goldSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Theme.goldBorder, lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                AppSegmented(
                    options: MediaType.allCases,
                    selection: $media,
                    title: { $0 == .movie ? L10n.Doulist.movie : L10n.Doulist.book },
                    gold: true,
                    fitContent: true
                )
                .fixedSize(horizontal: true, vertical: false)
                ChipBar(
                    items: [
                        ChipItem(id: DoulistFilter.all.rawValue, label: L10n.Doulist.all, count: "\(store.activeDoulists.filter { $0.mediaType == media }.count)"),
                        ChipItem(id: DoulistFilter.own.rawValue, label: L10n.Doulist.createdByMe),
                        ChipItem(id: DoulistFilter.following.rawValue, label: L10n.Doulist.following)
                    ],
                    selectedID: Binding(
                        get: { filter.rawValue },
                        set: { filter = DoulistFilter(rawValue: $0) ?? .all }
                    )
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } content: {
            List {
                if doulists.isEmpty {
                    EmptyStateView(icon: "list.bullet.rectangle", title: L10n.Doulist.empty, detail: submittedKeyword.isEmpty ? nil : L10n.Doulist.retryKeyword)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(doulists) { doulist in
                    DoulistCard(doulist: doulist, query: submittedKeyword)
                        .contentShape(Rectangle())
                        .onTapGesture { router.push(.doulistDetail(doulist.id)) }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    var reordered = doulists
                    reordered.move(fromOffsets: source, toOffset: destination)
                    withAnimation(.easeOut(duration: 0.16)) {
                        store.reorderDoulists(reordered.map(\.id))
                    }
                    toast = L10n.Common.orderUpdated
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .contentMargins(.top, 6, for: .scrollContent)
            .contentMargins(.bottom, 82, for: .scrollContent)
        }
        .toast(message: $toast)
        .onChange(of: media) { _, _ in
            searchText = ""
            submittedKeyword = ""
        }
        .onChange(of: searchText) { _, value in
            if value.isEmpty { submittedKeyword = "" }
        }
    }

    private func submitSearch() {
        submittedKeyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DoulistCard: View {
    @Environment(LibraryStore.self) private var store
    let doulist: Doulist
    var query: String = ""

    var body: some View {
        HStack(spacing: 12) {
            DoulistMosaic(items: store.doulistItems(for: doulist.id), media: doulist.mediaType)
                .frame(width: 84, height: 100)

            VStack(alignment: .leading, spacing: 4) {
                Text(highlighted(doulist.title))
                    .font(.appTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(L10n.Doulist.updatedAt(doulist.metaText, DateFormatter.shortDate.string(from: doulist.updatedAt)))
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                HStack(spacing: 5) {
                    TagView(text: doulist.isFollowing ? L10n.Doulist.following : L10n.Doulist.createdByMe, style: doulist.isFollowing ? .teal : .gold)
                    TagView(text: doulist.isPublic ? L10n.Doulist.visibilityPublic : L10n.Doulist.visibilityPrivate, style: .neutral)
                    if doulist.itemCount - doulist.readCount > 0 {
                        TagView(text: L10n.Doulist.pendingCount(String(describing: doulist.itemCount - doulist.readCount)), style: .wish)
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text4)
                .frame(width: 24, height: 100)
                .accessibilityHidden(true)
        }
        .frame(height: 100, alignment: .leading)
        .padding(12)
        .frame(height: 124, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func highlighted(_ text: String) -> AttributedString {
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
}

struct DoulistMosaic: View {
    @Environment(LibraryStore.self) private var store
    let items: [DoulistItem]
    let media: MediaType

    var body: some View {
        Group {
            if items.isEmpty {
                placeholder
            } else if items.count == 1 {
                CoverArtwork(
                    art: items[0].art,
                    urlString: store.coverRemoteURL(for: items[0].subjectID, media: items[0].mediaType, fallback: items[0].coverURL),
                    localKey: store.coverLocalKey(for: items[0].subjectID)
                )
                .frame(width: 54, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        mosaicCell(0).frame(width: 41, height: 49)
                        mosaicCell(1).frame(width: 41, height: 49)
                    }
                    HStack(spacing: 2) {
                        mosaicCell(2).frame(width: 41, height: 49)
                        mosaicCell(3).frame(width: 41, height: 49)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .drawingGroup()
    }

    @ViewBuilder
    private func mosaicCell(_ index: Int) -> some View {
        if index < items.count {
            let item = items[index]
            CoverArtwork(
                art: item.art,
                urlString: store.coverRemoteURL(for: item.subjectID, media: item.mediaType, fallback: item.coverURL),
                localKey: store.coverLocalKey(for: item.subjectID)
            )
            .clipped()
        } else {
            Color.clear
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.subtle)
            Image(systemName: media == .movie ? "film" : "book.closed")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Theme.text4)
        }
    }
}
