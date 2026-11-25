import SwiftUI

private enum PlanFilter: String, CaseIterable, Identifiable {
    case all, active, finished
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: L10n.Plan.all
        case .active: L10n.Plan.inProgress
        case .finished: L10n.Plan.completed
        }
    }
}

struct PlanView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @State private var media: MediaType = .movie
    @State private var filter: PlanFilter = .all
    @State private var showNewPlan = false
    @State private var toast: String?

    private var folders: [PlanFolder] {
        store.activePlanFolders
            .filter { $0.mediaType == media }
            .filter {
                switch filter {
                case .all: true
                case .active: $0.progress < 1
                case .finished: $0.progress >= 1
                }
            }
    }

    var body: some View {
        PageScaffold {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Plan.my)
                            .font(.appDisplay)
                            .foregroundStyle(Theme.text)
                        Text(L10n.Plan.summary(media.label, String(describing: store.activePlanFolders.filter { $0.mediaType == media }.count), media.doneLabel, String(describing: totalRead(media)), String(describing: totalItems(media)), media.noun))
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    Button {
                        showNewPlan = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                            .frame(width: 34, height: 34)
                            .background(Theme.goldSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                AppSegmented(
                    options: MediaType.allCases,
                    selection: $media,
                    title: { L10n.Plan.tabTitle($0.label) },
                    gold: true,
                    fitContent: true
                )
                .fixedSize(horizontal: true, vertical: false)
                ChipBar(
                    items: [
                        ChipItem(id: PlanFilter.all.rawValue, label: L10n.Plan.allCount(String(describing: store.activePlanFolders.filter { $0.mediaType == media }.count))),
                        ChipItem(id: PlanFilter.active.rawValue, label: L10n.Plan.inProgress),
                        ChipItem(id: PlanFilter.finished.rawValue, label: L10n.Plan.completed)
                    ],
                    selectedID: Binding(
                        get: { filter.rawValue },
                        set: { filter = PlanFilter(rawValue: $0) ?? .all }
                    )
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } content: {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(folders) { folder in
                    Button {
                        router.push(.planDetail(folder.id))
                    } label: {
                        PlanFolderCard(folder: folder)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .toast(message: $toast)
        .sheet(isPresented: $showNewPlan) {
            NewPlanSheet(media: media, onCreated: { toast = L10n.Plan.planCreatedToast })
                .presentationDetents([.medium])
        }
    }

    private func totalItems(_ media: MediaType) -> Int {
        store.activePlanFolders.filter { $0.mediaType == media }.reduce(0) { $0 + $1.itemCount }
    }

    private func totalRead(_ media: MediaType) -> Int {
        store.activePlanFolders.filter { $0.mediaType == media }.reduce(0) { $0 + $1.readCount }
    }
}

struct PlanFolderCard: View {
    @Environment(LibraryStore.self) private var store
    let folder: PlanFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                PlanMosaic(items: store.planItems(for: folder.id), media: folder.mediaType)
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            )

            Text(folder.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .frame(height: 36, alignment: .topLeading)

            HStack {
                Text("\(folder.mediaType.doneLabel) \(folder.readCount)/\(folder.itemCount) \(folder.mediaType.noun)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                Spacer()
                Text(folder.percentText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            ProgressView(value: folder.progress)
                .tint(Theme.gold)
                .scaleEffect(x: 1, y: 0.65, anchor: .center)
        }
        .padding(8)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct PlanMosaic: View {
    @Environment(LibraryStore.self) private var store
    let items: [PlanItem]
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
                .frame(width: 68, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                GeometryReader { proxy in
                    let gap: CGFloat = 2
                    let cellWidth = max(1, (proxy.size.width - gap) / 2)
                    let cellHeight = max(1, (proxy.size.height - gap) / 2)
                    VStack(spacing: gap) {
                        HStack(spacing: gap) {
                            cell(0).frame(width: cellWidth, height: cellHeight)
                            cell(1).frame(width: cellWidth, height: cellHeight)
                        }
                        HStack(spacing: gap) {
                            cell(2).frame(width: cellWidth, height: cellHeight)
                            cell(3).frame(width: cellWidth, height: cellHeight)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
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

struct NewPlanSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let media: MediaType
    var onCreated: (() -> Void)? = nil
    @State private var type: MediaType
    @State private var title = ""
    @State private var note = ""

    init(media: MediaType, onCreated: (() -> Void)? = nil) {
        self.media = media
        self.onCreated = onCreated
        _type = State(initialValue: media)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Plan.new, leftTitle: L10n.Common.cancel, rightTitle: L10n.Plan.create, onLeft: { dismiss() }, onRight: { create() })
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                AppSegmented(
                    options: MediaType.allCases,
                    selection: $type,
                    title: { L10n.Plan.tabTitle($0.label) },
                    gold: true
                )
                .padding(.horizontal, 16)

                Text(L10n.Plan.planName)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                TextField(L10n.Plan.planNameExample, text: $title)
                    .font(.appBody)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.goldBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                Text(L10n.Plan.optionalNote)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                TextEditor(text: $note)
                    .font(.appBody)
                    .scrollContentBackground(.hidden)
                    .frame(height: 84)
                    .padding(10)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                Text(L10n.Plan.createPlanHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }
        }
    }

    private func create() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.addPlanFolder(
            PlanFolder(
                title: name,
                mediaType: type,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                arts: [type == .movie ? .war : .bookCream],
                itemCount: 0,
                readCount: 0,
                createdAt: Date()
            )
        )
        onCreated?()
        dismiss()
    }
}
