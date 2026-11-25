import SwiftUI

struct RecordsView: View {
    @Environment(LibraryStore.self) private var store

    @State private var media: MediaType = .movie
    @State private var status: RecordStatus = .done
    @State private var searchText = ""
    @State private var selectedYearID = "all"
    @State private var jumpTarget: String?
    @State private var locateTarget: String?
    @State private var showBackToTop: [String: Bool] = [:]
    @State private var detailRecord: MediaRecord?
    @State private var showAdd = false
    @State private var showSearch = false
    @State private var showSync = false
    @State private var showMonthPicker = false
    @State private var toast: String?

    private var year: Int? {
        selectedYearID == "all" ? nil : Int(selectedYearID)
    }

    private var allCount: Int {
        store.activeRecords(media: media).count
    }

    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let source = store.filteredRecords(media: media, status: status, year: year, query: "")
        let months = source.compactMap { record in
            calendar.date(from: calendar.dateComponents([.year, .month], from: record.effectiveDate))
        }
        return Array(Set(months)).sorted(by: >)
    }

    private var yearItems: [ChipItem] {
        [ChipItem(id: "all", label: L10n.Records.all)] + store.years(media: media).map {
            ChipItem(id: "\($0)", label: "\($0)")
        }
    }

    var body: some View {
        PageScaffoldNoScroll {
            header
        } content: {
            ZStack {
                ForEach(MediaType.allCases) { itemMedia in
                    ForEach(RecordStatus.allCases) { itemStatus in
                        recordScroll(media: itemMedia, status: itemStatus)
                    }
                }
            }
        }
        .toast(message: $toast)
        .sheet(item: $detailRecord) { record in
            RecordDetailView(recordID: record.id, onDeleted: { toast = L10n.Records.movedToRecycleBin })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAdd) {
            RecordEditorView(record: nil, mediaType: media, status: status, onSaved: { toast = L10n.Records.recordAdded })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSearch) {
            RecordSearchView(media: media) { record in
                showSearch = false
                DispatchQueue.main.async { locate(record) }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSync) {
            SyncSheet(media: media)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthJumpSheet(months: availableMonths) { month in
                jumpTarget = monthJumpID(month)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Button {
                            switchMedia(media == .movie ? .book : .movie)
                        } label: {
                            Text(media.recordTitle)
                                .font(.appDisplay)
                                .foregroundStyle(Theme.text)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button(L10n.Records.movieRecords, systemImage: "film") { switchMedia(.movie) }
                            Button(L10n.Records.bookRecords, systemImage: "book.closed") { switchMedia(.book) }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.text3)
                                .frame(width: 28, height: 34)
                                .contentShape(Rectangle())
                        }
                        .padding(.top, 2)
                    }
                    Text(L10n.Records.subtitle(allCount, media.noun))
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    IconCircleButton(systemName: "magnifyingglass", action: { showSearch = true })
                    IconCircleButton(systemName: "calendar", action: { showMonthPicker = true })
                    IconCircleButton(systemName: "plus", tint: Color(hex: 0x241804), background: Theme.goldBright, action: { showAdd = true })
                }
                .padding(.top, 4)
            }

            HStack(spacing: 10) {
                Picker(L10n.Records.recordStatus, selection: $status) {
                    ForEach(RecordStatus.allCases) { value in
                        Text(value.label(for: media)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                .tint(Theme.gold)
                Spacer(minLength: 0)
                Button {
                    showSync = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.Records.syncAction)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.goldDeep)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Theme.goldSoft)
                    .overlay(Capsule().stroke(Theme.goldBorder, lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            ChipBar(items: yearItems, selectedID: $selectedYearID)
                .onChange(of: selectedYearID) { _, _ in
                    jumpTarget = "records-top"
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func recordScroll(media itemMedia: MediaType, status itemStatus: RecordStatus) -> some View {
        let items = store.filteredRecords(media: itemMedia, status: itemStatus, year: year, query: searchText)
        let itemGroups = store.grouped(items)
        let isActive = media == itemMedia && status == itemStatus
        let layerKey = "\(itemMedia.rawValue)-\(itemStatus.rawValue)"
        ScrollViewReader { proxy in
            List {
                Color.clear
                    .frame(height: 1)
                    .id("records-top")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if items.isEmpty {
                    EmptyStateView(
                        icon: itemMedia.icon,
                        title: L10n.Records.emptyTitle(itemMedia.recordTitle),
                        detail: L10n.Records.emptyDetail
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(itemGroups.enumerated()), id: \.element.date) { index, group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.text2)
                                Spacer()
                                Text("\(group.items.count) \(itemMedia.noun)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.text4)
                            }
                            .padding(.horizontal, 2)
                            PosterWallGrid {
                                ForEach(group.items) { record in
                                    PosterCardView(
                                        record: record,
                                        onTap: { detailRecord = record }
                                    )
                                    .id(record.id.uuidString)
                                }
                            }
                        }
                        .id(monthAnchorID(groups: itemGroups, index: index, date: group.date))
                        .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .environment(\.defaultMinListRowHeight, 1)
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, 82, for: .scrollContent)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 260
            } action: { _, scrolled in
                showBackToTop[layerKey] = scrolled
            }
            .onChange(of: jumpTarget) { _, target in
                guard isActive, let target else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                DispatchQueue.main.async { jumpTarget = nil }
            }
            .onChange(of: locateTarget) { _, target in
                guard isActive, let target else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                DispatchQueue.main.async { locateTarget = nil }
            }
            .overlay(alignment: .bottomTrailing) {
                if showBackToTop[layerKey] == true {
                    Button {
                        withAnimation(.easeOut(duration: 0.28)) {
                            proxy.scrollTo("records-top", anchor: .top)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.goldDeep)
                            .frame(width: 42, height: 42)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.goldBorder, lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Records.backToTop)
                    .padding(.trailing, 16)
                    .padding(.bottom, 72)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .disabled(!isActive)
        .accessibilityHidden(!isActive)
    }

    private func monthAnchorID(groups: [(date: Date, title: String, items: [MediaRecord])], index: Int, date: Date) -> String {
        guard index > 0 else { return monthJumpID(date) }
        let calendar = Calendar.current
        return calendar.isDate(groups[index - 1].date, equalTo: date, toGranularity: .month)
            ? "day-\(date.timeIntervalSince1970)"
            : monthJumpID(date)
    }

    private func locate(_ record: MediaRecord) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            media = record.mediaType
            status = record.status
            selectedYearID = "all"
            searchText = ""
        }
        let groups = store.grouped(store.filteredRecords(media: record.mediaType, status: record.status, year: nil, query: ""))
        if let groupIndex = groups.firstIndex(where: { group in group.items.contains(where: { $0.id == record.id }) }) {
            let anchor = monthAnchorID(groups: groups, index: groupIndex, date: groups[groupIndex].date)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                locateTarget = anchor
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            locateTarget = record.id.uuidString
        }
    }

    private func switchMedia(_ value: MediaType) {
        guard media != value else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            media = value
            status = .done
            selectedYearID = "all"
            searchText = ""
        }
    }
}

private extension DateFormatter {
    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter
    }()
}

private func monthJumpID(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return "month-\(components.year ?? 0)-\(components.month ?? 0)"
}

struct MonthJumpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let months: [Date]
    let onSelect: (Date) -> Void

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Records.jumpDate, leftTitle: L10n.Common.close, onLeft: { dismiss() })
            }
        } content: {
            VStack(spacing: 8) {
                if months.isEmpty {
                    EmptyStateView(icon: "calendar", title: L10n.Records.noJumpableMonths, detail: L10n.Records.monthGroupsHint)
                } else {
                    ForEach(months, id: \.self) { month in
                        Button {
                            onSelect(month)
                            dismiss()
                        } label: {
                            HStack {
                                Text(DateFormatter.monthTitle.string(from: month))
                                    .font(.appBody)
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.text4)
                                    .rotationEffect(.degrees(-90))
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 13)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
