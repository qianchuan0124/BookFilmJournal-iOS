import SwiftUI
import UniformTypeIdentifiers

private struct SyncNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct CloudSyncView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ExploreStore.self) private var explore
    @AppStorage(CloudSyncService.autoBackupKey) private var autoBackup = false
    @AppStorage(CloudSyncService.autoSyncKey) private var autoSync = false

    @State private var folderName = ""
    @State private var lastBackup = ""
    @State private var snapshots: [SyncSnapshotInfo] = []
    @State private var isWorking = false
    @State private var showPicker = false
    @State private var showRestoreList = false
    @State private var showClearConfirm = false
    @State private var pendingRestore: SyncSnapshotInfo?
    @State private var notice: SyncNotice?
    @State private var toast: String?

    private var hasFolder: Bool { !folderName.isEmpty && folderName != L10n.Cloud.notSelected }

    var body: some View {
        PageScaffold {
            VStack(alignment: .leading, spacing: 8) {
                NavHeader(title: L10n.Settings.cloudSync, backLabel: L10n.Tab.settings, trailing: AnyView(
                    Image(systemName: "icloud")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                ))
                folderCard
                    .padding(.horizontal, 16)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                statusGroup

                Text(L10n.Cloud.backupPolicyHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 2)

                if !hasFolder {
                    VStack(spacing: 10) {
                        Button {
                            showPicker = true
                        } label: {
                            Label(L10n.Cloud.chooseSyncFolder, systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(GoldButtonStyle(height: 46, radius: 12, font: .system(size: 15, weight: .semibold)))
                        .disabled(isWorking)

                        Text(L10n.Cloud.chooseFolderFirst)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 10) {
                        Button {
                            backup()
                        } label: {
                            Label(L10n.Cloud.backupNow, systemImage: "arrow.up.doc")
                        }
                        .buttonStyle(GoldButtonStyle(height: 44, radius: 12, font: .system(size: 15, weight: .semibold)))
                        .disabled(isWorking)

                        Button {
                            guard !snapshots.isEmpty else {
                                toast = L10n.Cloud.noRestorableBackup
                                return
                            }
                            showRestoreList = true
                        } label: {
                            Label(L10n.Cloud.restoreFromFolder, systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(OutlineButtonStyle(height: 44, radius: 12, foreground: Theme.gold, font: .system(size: 15, weight: .semibold)))
                        .disabled(isWorking)
                    }

                    HStack(spacing: 10) {
                        Button {
                            showPicker = true
                        } label: {
                            Label(L10n.Cloud.changeFolder, systemImage: "folder")
                        }
                        .buttonStyle(OutlineButtonStyle(height: 44, radius: 12, font: .system(size: 15, weight: .semibold)))
                        .disabled(isWorking)

                        Button {
                            showClearConfirm = true
                        } label: {
                            Label(L10n.Common.clear, systemImage: "xmark")
                        }
                        .buttonStyle(OutlineButtonStyle(height: 44, radius: 12, foreground: Theme.danger, font: .system(size: 15, weight: .semibold)))
                        .disabled(isWorking)
                    }

                    Text(L10n.Cloud.restoreWarning)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text4)
                        .lineSpacing(3)
                        .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 16)
        }
        .toast(message: $toast)
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.Cloud.processingBackup)
                            .font(.appBodySmall)
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    try CloudSyncService.saveFolder(url)
                    refresh()
                    toast = L10n.Cloud.syncFolderSelected
                } catch {
                    notice = SyncNotice(title: L10n.Cloud.folderUnavailableMessage, message: error.localizedDescription)
                }
            case .failure(let error):
                notice = SyncNotice(title: L10n.Cloud.cannotChooseFolder, message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $showRestoreList) {
            SyncSnapshotListView(snapshots: snapshots) { snapshot in
                if snapshot.isDownloaded {
                    pendingRestore = snapshot
                } else if CloudSyncService.requestDownload(at: snapshot.url) {
                    refresh()
                    toast = L10n.Cloud.downloadStarted
                } else {
                    notice = SyncNotice(
                        title: L10n.Cloud.snapshotNotDownloaded,
                        message: L10n.Cloud.desktopBackupHint
                    )
                }
            }
            .presentationDetents([.large])
        }
        .alert(Text(L10n.Cloud.restoreConfirm), isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        )) {
            Button(L10n.Common.cancel, role: .cancel) { pendingRestore = nil }
            Button(L10n.Cloud.restore, role: .destructive) { restorePending() }
        } message: {
            Text(L10n.Cloud.restoreConfirmHint)
        }
        .alert(Text(L10n.Cloud.clearConfirm), isPresented: $showClearConfirm) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.clear, role: .destructive) {
                CloudSyncService.clearFolder()
                refresh()
                toast = L10n.Cloud.syncFolderCleared
            }
        } message: {
            Text(L10n.Cloud.clearFolderHint)
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text(L10n.Cloud.gotIt)))
        }
        .task { refresh() }
    }

    private var folderCard: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(hex: 0x10B981))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "icloud")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.Cloud.syncFolder)
                        .font(.appBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(hasFolder ? folderName : L10n.Cloud.chooseSyncFolder)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text4)
            }
            .padding(13)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statusGroup: some View {
        InfoGroup {
            FieldRow(label: L10n.Cloud.localRecords) {
                Text(L10n.Cloud.recordCount(String(describing: store.activeRecords().count)))
                    .foregroundStyle(Theme.text3)
            }
            FieldRow(label: L10n.Cloud.cloudBackup) {
                Text(hasFolder ? L10n.Cloud.countSuffix(String(describing: snapshots.count)) : L10n.Cloud.noFolderSelected)
                    .foregroundStyle(Theme.text3)
            }
            FieldRow(label: L10n.Cloud.lastBackup) {
                Text(lastBackup.isEmpty ? L10n.Cloud.none : lastBackup)
                    .foregroundStyle(Theme.text3)
            }
            FieldRow(label: L10n.Cloud.autoBackup) {
                if hasFolder {
                    Toggle("", isOn: $autoBackup)
                        .labelsHidden()
                } else {
                    Text(L10n.Cloud.selectFolderFirst)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text4)
                }
            }
            FieldRow(label: L10n.Cloud.autoSync, showDivider: false) {
                if hasFolder {
                    Toggle("", isOn: $autoSync)
                        .labelsHidden()
                } else {
                    Text(L10n.Cloud.selectFolderFirst)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text4)
                }
            }
        }
    }

    private func refresh() {
        folderName = CloudSyncService.hasFolder() ? CloudSyncService.folderDisplayName() : L10n.Cloud.notSelected
        lastBackup = CloudSyncService.lastBackupText()
        snapshots = CloudSyncService.listSnapshots()
    }

    private func backup() {
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try CloudSyncService.backup(
                snapshot: store.currentSnapshot,
                kind: .manual,
                force: true,
                exploreSites: explore.sites
            )
            refresh()
            toast = outcome.skipped ? L10n.Cloud.noChangesHint : L10n.Cloud.manualBackupCreated
        } catch {
            notice = SyncNotice(title: L10n.Cloud.backupFailed, message: error.localizedDescription)
        }
    }

    private func restorePending() {
        guard let info = pendingRestore else { return }
        pendingRestore = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try CloudSyncService.restore(info, current: store.currentSnapshot, exploreSites: explore.sites)
            store.replace(with: result.0)
            explore.replace(with: result.2)
            refresh()
            toast = L10n.Cloud.backupRestored
        } catch {
            notice = SyncNotice(title: L10n.Cloud.restoreFailedMessage, message: error.localizedDescription)
        }
    }
}

private struct SyncSnapshotListView: View {
    let snapshots: [SyncSnapshotInfo]
    let onSelect: (SyncSnapshotInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Cloud.selectBackup, leftTitle: L10n.Common.close, onLeft: { dismiss() })
            }
        } content: {
            VStack(spacing: 8) {
                if snapshots.isEmpty {
                    EmptyStateView(icon: "icloud", title: L10n.Cloud.folderHasNoBackup, detail: L10n.Cloud.backupLocallyFirst)
                } else {
                    ForEach(snapshots) { snapshot in
                        Button {
                            onSelect(snapshot)
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: snapshot.isDownloaded
                                      ? (snapshot.kind == .auto ? "icloud" : "arrow.down.doc")
                                      : "icloud.slash")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.gold)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.goldSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(L10n.Cloud.backupSummary(String(describing: snapshot.kind.label), String(describing: snapshot.dateText)))
                                            .font(.appBodySmall)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(1)
                                        if snapshot.isLatest {
                                            TagView(text: L10n.Cloud.latest, style: .gold)
                                        }
                                        if !snapshot.isDownloaded {
                                            TagView(text: L10n.Cloud.notDownloaded, style: .neutral)
                                        }
                                    }
                                    Text(snapshot.isDownloaded ? snapshot.counts.summary : L10n.Cloud.snapshotNotDownloaded)
                                        .font(.appCaption)
                                        .foregroundStyle(Theme.text3)
                                        .lineLimit(2)
                                    Text("\(snapshot.device) · \(snapshot.sizeText)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.text4)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.text4)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(L10n.Cloud.desktopBackupHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
        }
    }
}
