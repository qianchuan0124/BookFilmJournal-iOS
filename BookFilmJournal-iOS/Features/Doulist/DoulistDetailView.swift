import SwiftUI

private enum DoulistItemFilter: String, CaseIterable, Identifiable {
    case all, read, unread
    var id: String { rawValue }
    func label(for media: MediaType) -> String {
        switch self {
        case .all: L10n.Doulist.all
        case .read: media.doneLabel
        case .unread: media.undoneLabel
        }
    }
}

struct DoulistDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let doulistID: UUID
    @State private var filter: DoulistItemFilter = .all
    @State private var sort = "douban"
    @State private var selectedItem: DoulistItem?
    @State private var selectedRecord: MediaRecord?
    @State private var showManage = false
    @State private var toast: String?

    private var doulist: Doulist? { store.doulist(id: doulistID) }

    private var allItems: [DoulistItem] {
        guard let doulist else { return [] }
        return store.doulistItems(for: doulist.id)
    }

    private var totalCount: Int {
        allItems.isEmpty ? (doulist?.itemCount ?? 0) : allItems.count
    }

    private var readCount: Int {
        allItems.isEmpty ? (doulist?.readCount ?? 0) : allItems.filter(\.isRead).count
    }

    private var doulistProgress: Double {
        totalCount == 0 ? 0 : Double(readCount) / Double(totalCount)
    }

    private var items: [DoulistItem] {
        guard let doulist else { return [] }
        let filtered = store.doulistItems(for: doulist.id).filter {
            switch filter {
            case .all: true
            case .read: $0.isRead
            case .unread: !$0.isRead
            }
        }
        switch sort {
        case "rating":
            return filtered.sorted { score($0) > score($1) }
        case "year":
            return filtered.sorted { (year($0) ?? 0) > (year($1) ?? 0) }
        default:
            return filtered
        }
    }

    private func score(_ item: DoulistItem) -> Int {
        store.records.first { $0.mediaType == item.mediaType && $0.subjectID == item.subjectID }?.rating ?? 0
    }

    private func year(_ item: DoulistItem) -> Int? {
        if let raw = item.year, let value = Int(raw) { return value }
        return store.records.first { $0.mediaType == item.mediaType && $0.subjectID == item.subjectID }
            .flatMap { $0.year }
            .flatMap(Int.init)
    }

    var body: some View {
        PageScaffoldNoScroll {
            VStack(alignment: .leading, spacing: 8) {
                NavHeader(title: "", backLabel: L10n.Doulist.doulistLabel, trailing: AnyView(
                    IconCircleButton(systemName: "ellipsis", action: { showManage = true })
                ))
                if let doulist {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(doulist.title)
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Text(L10n.Doulist.doubanDoulistSummary(String(describing: totalCount), String(describing: doulist.mediaType.noun), String(describing: doulist.mediaType.doneLabel), String(describing: readCount), String(describing: doulist.mediaType.noun)))
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                        HStack(spacing: 5) {
                            TagView(text: doulist.isFollowing ? L10n.Doulist.following : L10n.Doulist.createdByMe, style: doulist.isFollowing ? .teal : .gold)
                            TagView(text: doulist.isPublic ? L10n.Doulist.visibilityPublic : L10n.Doulist.visibilityPrivate, style: .neutral)
                            TagView(text: L10n.Doulist.pendingCount(String(describing: max(0, totalCount - readCount))), style: .wish)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)

                    AppSegmented(
                        options: DoulistItemFilter.allCases,
                        selection: $filter,
                        title: { "\($0.label(for: doulist.mediaType)) \(count(for: $0))" },
                        compact: true
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 2)

                    ChipBar(
                        items: [
                            ChipItem(id: "douban", label: L10n.Doulist.doubanOrder),
                            ChipItem(id: "rating", label: L10n.Doulist.rating),
                            ChipItem(id: "year", label: L10n.Doulist.year)
                        ],
                        selectedID: $sort
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 0)
        } content: {
            List {
                if items.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: filter == .all ? L10n.Doulist.noItems : L10n.Doulist.emptyFiltered(String(describing: filter.label(for: doulist?.mediaType ?? .movie))),
                        detail: filter == .all ? L10n.Doulist.emptyStateHint : nil
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        CoverArtwork(art: item.art, urlString: store.coverRemoteURL(for: item.subjectID, media: item.mediaType, fallback: item.coverURL), localKey: store.coverLocalKey(for: item.subjectID))
                            .frame(width: 42, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.appBody)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Text(itemMetaLine(item))
                                .font(.appCaption)
                                .foregroundStyle(Theme.text3)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        TagView(text: item.readStatusLabel, style: item.isRead ? .read : .wish)
                        if filter == .all && sort == "douban" {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text4)
                                .frame(width: 24, height: 30)
                                .accessibilityHidden(true)
                        }
                        Button {
                            selectedItem = item
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let record = store.record(subjectID: item.subjectID, mediaType: item.mediaType) {
                            selectedRecord = record
                        } else {
                            toast = L10n.Doulist.itemNoRecord
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    guard filter == .all, sort == "douban" else { return }
                    var reordered = items
                    reordered.move(fromOffsets: source, toOffset: destination)
                    withAnimation(.easeOut(duration: 0.16)) {
                        store.reorderDoulistItems(reordered.map(\.id))
                    }
                    toast = L10n.Common.orderUpdated
                }

                Text(L10n.Doulist.itemDetailHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .contentMargins(.top, 6, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
        .toast(message: $toast)
        .sheet(item: $selectedRecord) { record in
            RecordDetailView(recordID: record.id, onDeleted: { toast = L10n.Doulist.movedToRecycleBin })
                .presentationDetents([.large])
        }
        .sheet(item: $selectedItem) { item in
            DoulistItemEditor(item: item, onSaved: { toast = L10n.Doulist.itemUpdatedToast })
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showManage) {
            if let doulist {
                DoulistManageSheet(doulist: doulist, onSave: { value in
                    store.updateDoulist(value)
                    toast = L10n.Doulist.doulistUpdatedToast
                }, onDelete: {
                    store.deleteDoulist(id: doulist.id)
                    dismiss()
                })
                .presentationDetents([.height(530)])
            }
        }
    }

    private func itemMetaLine(_ item: DoulistItem) -> String {
        if item.mediaType == .movie {
            var parts: [String] = []
            if let release = item.releaseDate?.trimmingCharacters(in: .whitespacesAndNewlines), !release.isEmpty {
                parts.append(release)
            } else if let year = item.year, !year.isEmpty {
                parts.append(year)
            }
            parts.append(item.statsText)
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return item.statsText
    }

    private func count(for filter: DoulistItemFilter) -> Int {
        guard let doulist else { return 0 }
        let items = store.doulistItems(for: doulist.id)
        switch filter {
        case .all: return allItems.count
        case .read: return allItems.filter(\.isRead).count
        case .unread: return allItems.filter { !$0.isRead }.count
        }
    }
}

struct DoulistItemEditor: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: DoulistItem
    var onSaved: (() -> Void)? = nil
    @State private var durationText: String
    @State private var pagesText: String
    @State private var wordsText: String
    @State private var isRead: Bool

    init(item: DoulistItem, onSaved: (() -> Void)? = nil) {
        self.item = item
        self.onSaved = onSaved
        _durationText = State(initialValue: item.durationMinutes.map { String($0) } ?? "")
        _pagesText = State(initialValue: item.pages.map { String($0) } ?? "")
        _wordsText = State(initialValue: item.wordCount.map { String($0) } ?? "")
        _isRead = State(initialValue: item.isRead)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Doulist.itemTitle, leftTitle: L10n.Common.cancel, rightTitle: L10n.Common.save, onLeft: { dismiss() }, onRight: { save() })
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    CoverArtwork(art: item.art, urlString: store.coverRemoteURL(for: item.subjectID, media: item.mediaType, fallback: item.coverURL), localKey: store.coverLocalKey(for: item.subjectID))
                        .frame(width: 56, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.appTitle)
                            .foregroundStyle(Theme.text)
                        Text(L10n.Doulist.itemDoubanSource)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                InfoGroup {
                    FieldRow(label: L10n.Doulist.status) {
                        AppSegmented(options: [false, true], selection: $isRead, title: { $0 ? item.mediaType.doneLabel : item.mediaType.undoneLabel }, gold: true, compact: true, fitContent: true)
                            .fixedSize()
                    }
                    if item.mediaType == .movie {
                        FieldRow(label: L10n.Doulist.durationMinutes, showDivider: false, hint: StatsInputFormat.durationHint(durationText)) {
                            TextField(L10n.Doulist.optional, text: $durationText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        FieldRow(label: L10n.Doulist.pages, hint: nil) {
                            TextField(L10n.Doulist.optional, text: $pagesText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        FieldRow(label: L10n.Doulist.words, showDivider: false, hint: StatsInputFormat.wordsHint(wordsText)) {
                            TextField(L10n.Doulist.optional, text: $wordsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Text(L10n.Doulist.localItemHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
        }
    }

    private func save() {
        var updated = item
        updated.isRead = isRead
        updated.durationMinutes = Int(durationText)
        updated.pages = Int(pagesText)
        updated.wordCount = Int(wordsText)
        store.updateDoulistItem(updated)
        onSaved?()
        dismiss()
    }
}

private struct DoulistManageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let doulist: Doulist
    let onSave: (Doulist) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var isPublic: Bool
    @State private var doubanURL: String
    @State private var showDeleteConfirm = false

    init(doulist: Doulist, onSave: @escaping (Doulist) -> Void, onDelete: @escaping () -> Void) {
        self.doulist = doulist
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: doulist.title)
        _isPublic = State(initialValue: doulist.isPublic)
        _doubanURL = State(initialValue: doulist.doubanID.map { "https://www.douban.com/doulist/\($0)/" } ?? "")
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Doulist.manage,
                    leftTitle: L10n.Common.cancel,
                    rightTitle: L10n.Common.save,
                    onLeft: { dismiss() },
                    onRight: {
                        var value = doulist
                        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.isPublic = isPublic
                        if let id = Self.doubanID(from: doubanURL) { value.doubanID = id }
                        onSave(value)
                        dismiss()
                    }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Doulist.name)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                TextField(L10n.Doulist.name, text: $title)
                    .font(.appBody)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))

                Toggle(L10n.Doulist.isPublic, isOn: $isPublic)
                    .font(.appBody)
                    .tint(Theme.gold)
                    .padding(.horizontal, 2)

                Text(L10n.Doulist.doubanLink)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                TextField("https://www.douban.com/doulist/…", text: $doubanURL)
                    .font(.system(size: 12.5))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
                Text(L10n.Doulist.privateDoulistHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text4)
                    .lineSpacing(2)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Label(L10n.Doulist.delete, systemImage: "trash")
                }
                .buttonStyle(OutlineButtonStyle(height: 42, foreground: Theme.danger))
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
        }
        .alert(L10n.Doulist.deleteConfirm, isPresented: $showDeleteConfirm) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Doulist.deleteAction, role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text(L10n.Doulist.deleteMessage)
        }
    }

    private static func doubanID(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let range = value.range(of: #"/(?:doulist|subject_collection)/([0-9A-Za-z]+)"#, options: .regularExpression) {
            let matched = String(value[range])
            return matched.split(separator: "/").last.map(String.init)
        }
        if value.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil {
            return value
        }
        return nil
    }
}
