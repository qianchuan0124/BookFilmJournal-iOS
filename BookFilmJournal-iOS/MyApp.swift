import SwiftUI

@main
struct MyApp: App {
    @State private var router = Router()
    @State private var library = LibraryStore()
    @State private var explore = ExploreStore()
    @AppStorage("bookfilm.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(CloudSyncService.autoBackupKey) private var autoBackup = false
    @AppStorage(CloudSyncService.autoSyncKey) private var autoSync = false
    @Environment(\.scenePhase) private var scenePhase

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(library)
                .environment(explore)
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .tint(Theme.gold)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    runCloudChecks()
                }
                .task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await explore.autoRefreshIfNeeded()
                }
        }
    }

    private func runCloudChecks() {
        guard CloudSyncService.hasFolder() else { return }
        if autoSync,
           let candidate = CloudSyncService.autoSyncCandidate(current: library.currentSnapshot, exploreSites: explore.sites) {
            if let result = try? CloudSyncService.restore(candidate, current: library.currentSnapshot, exploreSites: explore.sites) {
                library.replace(with: result.0)
                explore.replace(with: result.2)
            }
            // 云端存在更新的快照但尚未下载/暂不可读时，不能用自动备份覆盖云端清单。
            return
        }
        if autoBackup {
            _ = try? CloudSyncService.backup(
                snapshot: library.currentSnapshot,
                kind: .auto,
                force: false,
                exploreSites: explore.sites
            )
        }
    }
}
