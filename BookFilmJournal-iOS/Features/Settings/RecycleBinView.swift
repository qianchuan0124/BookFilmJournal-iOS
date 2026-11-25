import SwiftUI

private enum RecycleFilter: String, CaseIterable, Identifiable {
    case records, doulists, plans
    var id: String { rawValue }
    var label: String {
        switch self {
        case .records: L10n.Recycle.record
        case .doulists: L10n.Recycle.doulist
        case .plans: L10n.Recycle.plan
        }
    }
}

struct RecycleBinView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var filter: RecycleFilter = .records
    @State private var toast: String?

    private var deletedRecords: [MediaRecord] { store.deletedRecords }
    private var deletedDoulists: [Doulist] { store.deletedDoulists }
    private var deletedPlanFolders: [PlanFolder] { store.deletedPlanFolders }
    private var deletedPlanItems: [PlanItem] { store.deletedPlanItems }

    var body: some View {
        PageScaffold {
            VStack(alignment: .leading, spacing: 8) {
                NavHeader(title: L10n.Recycle.recycleBin, backLabel: L10n.Recycle.settings, trailing: AnyView(
                    Image(systemName: "trash")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                ))

                AppSegmented(
                    options: RecycleFilter.allCases,
                    selection: $filter,
                    title: { "\($0.label) \(count(for: $0))" },
                    compact: true
                )
                .padding(.horizontal, 16)

                HStack {
                    Text("\(L10n.Recycle.record) \(deletedRecords.count) · \(L10n.Recycle.doulist) \(deletedDoulists.count) · \(L10n.Recycle.plan) \(deletedPlanFolders.count + deletedPlanItems.count)")
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    TagView(text: L10n.Recycle.retainedForever, style: .neutral)
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.Recycle.infoTitle)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text3)

                    legendRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: L10n.Recycle.syncRemoval,
                        detail: L10n.Recycle.syncRemovalHint
                    )
                    legendRow(
                        icon: "trash.slash",
                        title: L10n.Recycle.permanentDelete,
                        detail: L10n.Recycle.permanentDeleteHint
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 16)
            }
        } content: {
            VStack(spacing: 8) {
                if filter == .records {
                    if deletedRecords.isEmpty {
                        EmptyStateView(icon: "trash", title: L10n.Recycle.emptyTitle, detail: L10n.Recycle.emptyDetail)
                    } else {
                        ForEach(deletedRecords) { record in
                            HStack(spacing: 10) {
                                CoverArtwork(art: record.art, urlString: record.coverRemoteURL, localKey: record.coverLocalKey)
                                    .frame(width: 42, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.title)
                                        .font(.appBody)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.text)
                                    Text("\(record.mediaType.label) · \(record.deleteSource?.label ?? "手动删除") · \(record.deletedAt.map { DateFormatter.deletedDate.string(from: $0) } ?? "")")
                                        .font(.appCaption)
                                        .foregroundStyle(Theme.text3)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Button(L10n.Recycle.restore) {
                                    store.restoreRecord(id: record.id)
                                    toast = L10n.Recycle.restored
                                }
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(Theme.goldSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Button(L10n.Recycle.delete) {
                                    store.purgeRecord(id: record.id)
                                    toast = L10n.Recycle.permanentlyDeleted
                                }
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(Theme.dangerSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                } else if filter == .doulists {
                    if deletedDoulists.isEmpty {
                        EmptyStateView(icon: "tray", title: L10n.Recycle.emptyFiltered(String(describing: filter.label)))
                    } else {
                        ForEach(deletedDoulists) { doulist in
                            recycleRow(
                                title: doulist.title,
                                detail: "\(doulist.mediaType.label) · \(doulist.itemCount) \(doulist.mediaType.noun) · \(deletedDateText(doulist.deletedAt))"
                            ) {
                                store.restoreDoulist(id: doulist.id)
                                toast = L10n.Recycle.restored
                            } purge: {
                                store.purgeDoulist(id: doulist.id)
                                toast = L10n.Recycle.permanentlyDeleted
                            }
                        }
                    }
                } else {
                    if deletedPlanFolders.isEmpty && deletedPlanItems.isEmpty {
                        EmptyStateView(icon: "tray", title: L10n.Recycle.emptyFiltered(String(describing: filter.label)))
                    } else {
                        ForEach(deletedPlanFolders) { folder in
                            recycleRow(
                                title: folder.title,
                                detail: "\(folder.mediaType.label) · \(folder.itemCount) \(folder.mediaType.noun) · \(deletedDateText(folder.deletedAt))"
                            ) {
                                store.restorePlanFolder(id: folder.id)
                                toast = L10n.Recycle.restored
                            } purge: {
                                store.purgePlanFolder(id: folder.id)
                                toast = L10n.Recycle.permanentlyDeleted
                            }
                        }
                        ForEach(deletedPlanItems) { item in
                            recycleRow(
                                title: item.title,
                                detail: "\(item.mediaType.label) · \(item.statsText) · \(deletedDateText(item.deletedAt))"
                            ) {
                                store.restorePlanItem(id: item.id)
                                toast = L10n.Recycle.restored
                            } purge: {
                                store.purgePlanItem(id: item.id)
                                toast = L10n.Recycle.permanentlyDeleted
                            }
                        }
                    }
                }

                Text(L10n.Recycle.behaviorHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 2)
                    .padding(.top, 6)

                InfoGroup {
                    FieldRow(label: L10n.Recycle.retentionPolicy) {
                        Text(L10n.Recycle.retainedForever).foregroundStyle(Theme.text3)
                    }
                    FieldRow(label: L10n.Recycle.doulist) {
                        Text("\(deletedDoulists.count) 个").foregroundStyle(Theme.text3)
                    }
                    FieldRow(label: L10n.Recycle.planFolder, showDivider: false) {
                        Text("\(deletedPlanFolders.count + deletedPlanItems.count) 个").foregroundStyle(Theme.text3)
                    }
                }
                .padding(.top, 6)

                Button {
                    store.purgeAllDeleted()
                    toast = L10n.Recycle.recycleBinCleared
                } label: {
                    Label(L10n.Recycle.clearRecycleBin, systemImage: "trash")
                }
                .buttonStyle(OutlineButtonStyle(height: 40, foreground: Theme.danger))
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
        }
        .toast(message: $toast)
    }

    private func legendRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text3)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .fixedSize()
            Text("：")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
    }

    private func deletedDateText(_ date: Date?) -> String {
        date.map { DateFormatter.deletedDate.string(from: $0) } ?? ""
    }

    private func recycleRow(title: String, detail: String, restore: @escaping () -> Void, purge: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text3)
                .frame(width: 42, height: 42)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(L10n.Recycle.restore, action: restore)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Theme.goldSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button(L10n.Recycle.delete, action: purge)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Theme.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func count(for filter: RecycleFilter) -> Int {
        switch filter {
        case .records: store.deletedRecords.count
        case .doulists: store.deletedDoulists.count
        case .plans: store.deletedPlanFolders.count + store.deletedPlanItems.count
        }
    }
}
