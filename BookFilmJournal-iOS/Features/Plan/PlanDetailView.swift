import SwiftUI

private enum PlanItemFilter: String, CaseIterable, Identifiable {
    case all, read, unread
    var id: String { rawValue }
    func label(for media: MediaType) -> String {
        switch self {
        case .all: L10n.Plan.all
        case .read: media.doneLabel
        case .unread: media.undoneLabel
        }
    }
}

struct PlanDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID
    @State private var filter: PlanItemFilter = .all
    @State private var showWishPicker = false
    @State private var showDoulistPicker = false
    @State private var showManage = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var isExporting = false
    @State private var detailItem: PlanItem?
    @State private var detailRecord: MediaRecord?
    @State private var toast: String?

    private var folder: PlanFolder? { store.planFolder(id: folderID) }

    private var allItems: [PlanItem] {
        guard let folder else { return [] }
        return store.planItems(for: folder.id)
    }

    private var totalCount: Int {
        allItems.isEmpty ? (folder?.itemCount ?? 0) : allItems.count
    }

    private var readCount: Int {
        allItems.isEmpty ? (folder?.readCount ?? 0) : allItems.filter(\.isRead).count
    }

    private var planProgress: Double {
        totalCount == 0 ? 0 : Double(readCount) / Double(totalCount)
    }

    private var items: [PlanItem] {
        guard let folder else { return [] }
        return store.planItems(for: folder.id).filter {
            switch filter {
            case .all: true
            case .read: $0.isRead
            case .unread: !$0.isRead
            }
        }
    }

    var body: some View {
        PageScaffoldNoScroll {
            VStack(alignment: .leading, spacing: 7) {
                NavHeader(title: "", backLabel: L10n.Plan.planLabel, trailing: AnyView(
                    IconCircleButton(systemName: "ellipsis", action: { showManage = true })
                ))
                if let folder {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(folder.title)
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Text("\(folder.mediaType.doneLabel) \(readCount)/\(totalCount) \(folder.mediaType.noun) · \(folder.mediaType.undoneLabel) \(max(0, totalCount - readCount)) \(folder.mediaType.noun)\(folder.note.isEmpty ? "" : " · \(folder.note)")")
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                        ProgressView(value: planProgress)
                            .tint(Theme.gold)
                            .scaleEffect(x: 1, y: 0.8, anchor: .center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    AppSegmented(
                        options: PlanItemFilter.allCases,
                        selection: $filter,
                        title: { "\($0.label(for: folder.mediaType)) \(count(for: $0))" },
                        compact: true
                    )
                    .padding(.horizontal, 16)
                }
            }
        } content: {
            List {
                if items.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: filter == .all ? L10n.Plan.noItems : L10n.Plan.emptyFiltered(String(describing: filter.label(for: folder?.mediaType ?? .movie))),
                        detail: filter == .all ? L10n.Plan.emptyDetail(String(describing: (folder?.mediaType.wishLabel ?? L10n.Media.movieWish))) : nil
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    planRow(index: index, item: item)
                }
                .onMove { source, destination in
                    guard filter == .all else { return }
                    movePlanItems(from: source, to: destination)
                }

                if !items.isEmpty {
                    Text(L10n.Plan.toggleHint(folder?.mediaType.doneLabel ?? L10n.Media.movieDone, folder?.mediaType.undoneLabel ?? L10n.Media.movieUndone))
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .contentMargins(.top, 6, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            planActionBar
        }
        .toast(message: $toast)
        .sheet(isPresented: $showWishPicker) {
            WishPickerSheet(folder: folder, onAdded: { count in toast = L10n.Plan.addedCount(String(describing: count)) })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showDoulistPicker) {
            DoulistPickerSheet(folder: folder, onAdded: { count in toast = L10n.Plan.addedCount(String(describing: count)) })
                .presentationDetents([.large])
        }
        .sheet(item: $detailItem) { item in
            PlanItemDetailSheet(item: item)
                .presentationDetents([.medium])
        }
        .sheet(item: $detailRecord) { record in
            RecordDetailView(recordID: record.id, onDeleted: { toast = L10n.Plan.movedToRecycleBin })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showManage) {
            if let folder {
                PlanManageSheet(folder: folder, onSave: { value in
                    store.updatePlanFolder(value)
                    toast = L10n.Plan.planUpdatedToast
                }, onDelete: {
                    store.deletePlanFolder(id: folder.id)
                    toast = L10n.Plan.planDeletedToast
                    dismiss()
                })
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityShareView(items: shareItems)
        }
    }

    private var planActionBar: some View {
        HStack(spacing: 0) {
            actionItem(icon: "plus", title: L10n.Plan.addWishTitle(folder?.mediaType.wishLabel ?? L10n.Media.movieWish), active: false) { showWishPicker = true }
            actionItem(icon: "list.bullet.rectangle", title: L10n.Plan.addFromDoulist, active: true) { showDoulistPicker = true }
            actionItem(icon: "square.and.arrow.up", title: L10n.Plan.exportPNG, active: isExporting) { exportPNG() }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Theme.tabBar)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func exportPNG() {
        guard let folder, !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        guard let url = PlanExportService.makePNG(folder: folder, items: allItems) else {
            toast = L10n.Plan.exportPNGFailed
            return
        }
        shareItems = [url]
        showShare = true
    }

    private func actionItem(icon: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                Text(title)
                    .font(.system(size: 10, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Theme.goldDeep : Theme.text3)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func planRow(index: Int, item: PlanItem) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Theme.text4)
                    .frame(width: 16)
                CoverArtwork(art: item.art, urlString: store.coverRemoteURL(for: item.subjectID, media: item.mediaType, fallback: item.coverURL), localKey: store.coverLocalKey(for: item.subjectID))
                    .frame(width: 42, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.appBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(detailText(for: item))
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text4)
                .frame(width: 32, height: 52)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let record = store.record(subjectID: item.subjectID, mediaType: item.mediaType) {
                detailRecord = record
            } else {
                detailItem = item
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.deletePlanItem(id: item.id)
            } label: {
                Label(L10n.Common.remove, systemImage: "trash")
            }
            Button {
                store.togglePlanItem(id: item.id)
            } label: {
                Label(item.toggleReadLabel, systemImage: item.isRead ? "circle" : "checkmark.circle")
            }
            .tint(Theme.gold)
        }
    }

    private func movePlanItems(from source: IndexSet, to destination: Int) {
        guard filter == .all, let folder else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            store.movePlanItems(folderID: folder.id, from: source, to: destination)
        }
        toast = L10n.Common.orderUpdated
    }

    private func detailText(for item: PlanItem) -> String {
        let record = store.records.first { $0.subjectID == item.subjectID && !$0.isDeleted }
        let status = item.readStatusLabel
        var stats = item.statsText
        for prefix in [L10n.Plan.watched, L10n.Plan.unwatched, L10n.Plan.read, L10n.Plan.unread] {
            if stats.hasPrefix(prefix) {
                stats = stats.replacingOccurrences(of: "\(prefix) · ", with: "")
                break
            }
        }
        if item.mediaType == .movie, stats.isEmpty || stats == L10n.Plan.durationUnset {
            stats = record?.durationText ?? L10n.Plan.durationUnset
        }
        let release = item.mediaType == .movie ? (item.releaseDate ?? record?.releaseDate ?? record?.year) : nil
        return [release, stats, status].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private func count(for filter: PlanItemFilter) -> Int {
        switch filter {
        case .all: return allItems.count
        case .read: return allItems.filter(\.isRead).count
        case .unread: return allItems.filter { !$0.isRead }.count
        }
    }
}

struct PlanItemDetailSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: PlanItem

    private var cleanStats: String {
        var stats = item.statsText
        for prefix in [L10n.Plan.watched, L10n.Plan.unwatched, L10n.Plan.read, L10n.Plan.unread] {
            stats = stats.replacingOccurrences(of: "\(prefix) · ", with: "")
        }
        return stats
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Plan.itemDetail, leftTitle: L10n.Common.close, onLeft: { dismiss() })
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    CoverArtwork(art: item.art, urlString: store.coverRemoteURL(for: item.subjectID, media: item.mediaType, fallback: item.coverURL), localKey: store.coverLocalKey(for: item.subjectID))
                        .frame(width: 78, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(3)
                        HStack(spacing: 5) {
                            TagView(text: item.readStatusLabel, style: item.isRead ? .read : .wish)
                            TagView(text: item.mediaType.noun, style: .neutral)
                        }
                        Text(cleanStats)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer(minLength: 0)
                }

                InfoGroup {
                    FieldRow(label: L10n.Plan.status) {
                        Text(item.readStatusLabel)
                            .foregroundStyle(Theme.text)
                    }
                    if item.mediaType == .movie {
                        FieldRow(label: L10n.Plan.releaseDate) {
                            Text(item.releaseDate ?? store.records.first { $0.subjectID == item.subjectID && !$0.isDeleted }?.releaseDate ?? store.records.first { $0.subjectID == item.subjectID && !$0.isDeleted }?.year ?? L10n.Plan.notSet)
                                .foregroundStyle(Theme.text)
                        }
                    }
                    FieldRow(label: item.mediaType == .movie ? L10n.Plan.duration : L10n.Plan.pagesOrWords) {
                        Text(cleanStats)
                            .foregroundStyle(Theme.text)
                    }
                    FieldRow(label: L10n.Plan.doubanID, showDivider: false) {
                        Text(item.subjectID)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                }

                Button {
                    store.togglePlanItem(id: item.id)
                    dismiss()
                } label: {
                    Label(item.toggleReadLabel, systemImage: item.isRead ? "circle" : "checkmark.circle")
                }
                .buttonStyle(GoldButtonStyle(height: 44, radius: 12, font: .system(size: 15, weight: .semibold)))
            }
            .padding(.horizontal, 16)
        }
    }
}

struct WishPickerSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let folder: PlanFolder?
    var onAdded: ((Int) -> Void)? = nil
    @State private var query = ""
    @State private var submittedKeyword = ""
    @State private var selected: Set<UUID> = []

    private var candidates: [MediaRecord] {
        guard let folder else { return [] }
        let existing = Set(store.planItems(for: folder.id).map(\.subjectID))
        let keyword = submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.activeWishRecords
            .filter { $0.mediaType == folder.mediaType }
            .filter { !existing.contains($0.subjectID) }
            .filter { keyword.isEmpty || $0.searchText.contains(keyword) }
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Plan.addWishTitle(folder?.mediaType.wishLabel ?? L10n.Media.movieWish),
                    leftTitle: L10n.Common.cancel,
                    rightTitle: selected.isEmpty ? L10n.Plan.addButton : L10n.Plan.addItemsCount(String(describing: selected.count)),
                    onLeft: { dismiss() },
                    onRight: { addSelected() }
                )
                HStack(spacing: 8) {
                    SearchField(placeholder: L10n.Plan.searchTitleOrSummary, text: $query, onSubmit: submitSearch)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        } content: {
            VStack(spacing: 8) {
                ForEach(candidates) { record in
                    Button {
                        if selected.contains(record.id) { selected.remove(record.id) } else { selected.insert(record.id) }
                    } label: {
                        HStack(spacing: 10) {
                            CoverArtwork(art: record.art, urlString: record.coverRemoteURL, localKey: record.coverLocalKey)
                                .frame(width: 42, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(highlightedTitle(record.title))
                                    .font(.appBody)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text("\(record.statusLabel) · \(record.statsText)")
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.text3)
                            }
                            Spacer()
                            Image(systemName: selected.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 21))
                                .foregroundStyle(selected.contains(record.id) ? Theme.goldBright : Theme.borderStrong)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if candidates.isEmpty {
                    EmptyStateView(icon: "rectangle.stack", title: L10n.Plan.noWishRecords(folder?.mediaType.wishLabel ?? L10n.Media.movieWish), detail: L10n.Plan.maybeAllInPlan)
                }
                Text(L10n.Plan.addHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
        }
        .onChange(of: query) { _, value in
            if value.isEmpty { submittedKeyword = "" }
        }
    }

    private func submitSearch() {
        submittedKeyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func highlightedTitle(_ title: String) -> AttributedString {
        var attributed = AttributedString(title)
        let keyword = submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return attributed }
        var searchStart = title.startIndex
        while searchStart < title.endIndex,
              let range = title.range(of: keyword, options: [.caseInsensitive], range: searchStart..<title.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].foregroundColor = Theme.goldDeep
                attributed[lower..<upper].backgroundColor = Theme.goldSoft
            }
            searchStart = range.upperBound
        }
        return attributed
    }

    private func addSelected() {
        guard let folder else { dismiss(); return }
        var position = store.planItems(for: folder.id).count
        let count = selected.count
        for record in candidates where selected.contains(record.id) {
            let item = PlanItem(
                folderID: folder.id,
                mediaType: record.mediaType,
                title: record.title,
                subjectID: record.subjectID,
                isRead: record.status == .done,
                art: record.art,
                statsText: record.statsText,
                position: position,
                coverURL: record.coverURL,
                releaseDate: record.releaseDate
            )
            store.addPlanItem(item)
            position += 1
        }
        onAdded?(count)
        dismiss()
    }
}

struct DoulistPickerSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let folder: PlanFolder?
    var onAdded: ((Int) -> Void)? = nil
    @State private var selectedDoulistID = ""
    @State private var selected: Set<UUID> = []

    private var doulists: [Doulist] {
        guard let folder else { return [] }
        return store.activeDoulists
            .filter { $0.mediaType == folder.mediaType }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var candidates: [DoulistItem] {
        guard let folder,
              let doulistID = UUID(uuidString: selectedDoulistID) else { return [] }
        let existing = Set(store.planItems(for: folder.id).map(\.subjectID))
        return store.doulistItems(for: doulistID)
            .filter { $0.mediaType == folder.mediaType && !existing.contains($0.subjectID) }
    }

    private var allSelected: Bool {
        !candidates.isEmpty && candidates.allSatisfy { selected.contains($0.id) }
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Plan.addFromDoulist,
                    leftTitle: L10n.Common.cancel,
                    rightTitle: selected.isEmpty ? L10n.Plan.addButton : L10n.Plan.addItemsCount(String(describing: selected.count)),
                    onLeft: { dismiss() },
                    onRight: { addSelected() }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if doulists.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: L10n.Plan.noSyncedDoulist,
                        detail: L10n.Plan.syncDoulistFirst
                    )
                } else {
                    Text(L10n.Plan.chooseDoulist)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)

                    ChipBar(
                        items: doulists.map {
                            ChipItem(id: $0.id.uuidString, label: $0.title, count: "\($0.itemCount)")
                        },
                        selectedID: $selectedDoulistID
                    )

                    if candidates.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: L10n.Plan.doulistEmpty,
                            detail: L10n.Plan.itemMaybeInPlan
                        )
                        .padding(.top, 12)
                    } else {
                        HStack(spacing: 8) {
                            Text(L10n.Plan.excludedSelectionCount(String(describing: candidates.count), String(describing: selected.count)))
                                .font(.appCaption)
                                .foregroundStyle(Theme.text3)
                            Spacer(minLength: 0)
                            Button {
                                if allSelected {
                                    selected.removeAll()
                                } else {
                                    selected = Set(candidates.map(\.id))
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(L10n.Plan.selectAll)
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(allSelected ? Theme.gold : Theme.text3)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(candidates) { item in
                            Button {
                                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                            } label: {
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
                                        Text([item.year, item.statsText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.appCaption)
                                            .foregroundStyle(Theme.text3)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 21))
                                        .foregroundStyle(selected.contains(item.id) ? Theme.goldBright : Theme.borderStrong)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            if selectedDoulistID.isEmpty {
                selectedDoulistID = doulists.first?.id.uuidString ?? ""
            }
        }
        .onChange(of: selectedDoulistID) { _, _ in
            selected.removeAll()
        }
    }

    private func addSelected() {
        guard let folder else { dismiss(); return }
        var position = store.planItems(for: folder.id).count
        let count = selected.count
        for item in candidates where selected.contains(item.id) {
            store.addPlanItem(
                PlanItem(
                    folderID: folder.id,
                    mediaType: item.mediaType,
                    title: item.title,
                    subjectID: item.subjectID,
                    isRead: item.isRead,
                    art: item.art,
                    statsText: item.statsText,
                    position: position,
                    coverURL: item.coverURL,
                    releaseDate: item.releaseDate
                )
            )
            position += 1
        }
        onAdded?(count)
        dismiss()
    }
}

private struct PlanManageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let folder: PlanFolder
    let onSave: (PlanFolder) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    init(folder: PlanFolder, onSave: @escaping (PlanFolder) -> Void, onDelete: @escaping () -> Void) {
        self.folder = folder
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: folder.title)
        _note = State(initialValue: folder.note)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Plan.managePlan,
                    leftTitle: L10n.Common.cancel,
                    rightTitle: L10n.Common.save,
                    onLeft: { dismiss() },
                    onRight: {
                        var value = folder
                        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(value)
                        dismiss()
                    }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Plan.planName)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                TextField(L10n.Plan.planName, text: $title)
                    .font(.appBody)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))

                Text(L10n.Plan.note)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                TextField(L10n.Plan.notePlaceholder, text: $note)
                    .font(.appBody)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))

                Button {
                    showDeleteConfirm = true
                } label: {
                    Label(L10n.Plan.deletePlan, systemImage: "trash")
                }
                .buttonStyle(OutlineButtonStyle(height: 42, foreground: Theme.danger))
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
        }
        .alert(L10n.Plan.deleteConfirm, isPresented: $showDeleteConfirm) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Plan.delete, role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text(L10n.Plan.deleteMessage)
        }
    }
}
