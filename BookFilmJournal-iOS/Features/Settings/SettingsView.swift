import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @AppStorage("bookfilm.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("bookfilm.doubanID") private var doubanID = "catnine"
    @AppStorage("bookfilm.doubanAvatarURL") private var doubanAvatarURL = ""
    @AppStorage(CloudSyncService.folderNameKey) private var cloudFolderName = ""
    @AppStorage(CloudSyncService.lastTimeKey) private var cloudLastBackup = ""
    @State private var showLogin = false
    @State private var showAppearance = false
    @State private var showSearch = false
    @State private var authState: DoubanAuthState = .noCookie
    @State private var showClearAllData = false
    @State private var toast: String?

    private var profileAvatar: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xF4D083), Color(hex: 0xB87A1D)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(L10n.Settings.brandMark)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: 0x241804))
            if let url = URL(string: doubanAvatarURL), !doubanAvatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }
    private var cookieSaved: Bool { KeychainStore.loadCookie() != nil }

    var body: some View {
        PageScaffold {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(L10n.Tab.settings)
                        .font(.appDisplay)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    IconCircleButton(systemName: "magnifyingglass", action: { showSearch = true })
                        .padding(.top, 4)
                }

                HStack(spacing: 12) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Settings.brandName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text(L10n.Settings.doubanIDSyncSummary(String(describing: doubanID)))
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    Spacer()
                    TagView(
                        text: authState == .checking ? L10n.Settings.checking : authState.label,
                        style: authState == .valid ? .read : (authState == .expired ? .danger : .neutral)
                    )
                }
                .padding(14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))

                HStack {
                    Text(L10n.Settings.counts(String(describing: store.activeRecords().count), String(describing: store.activeDoulists.count), String(describing: store.activePlanFolders.count)))
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    Text(L10n.Settings.dataOverview)
                        .font(.appCaption)
                        .foregroundStyle(Theme.gold)
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroup(title: L10n.Settings.appearance) {
                    Button {
                        showAppearance = true
                    } label: {
                        settingsRow(
                            icon: "sun.max.fill",
                            color: Theme.goldBright,
                            title: L10n.Settings.appearance,
                            value: appearance.label
                        )
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: L10n.Settings.dataAndExplore) {
                    Button { router.push(.dataTransfer) } label: {
                        settingsRow(icon: "square.and.arrow.up", color: Color(hex: 0x4C7ED6), title: L10n.Settings.dataTransfer, value: L10n.Settings.recordCount(String(describing: store.activeRecords().count)))
                    }
                    .buttonStyle(.plain)
                    Button { router.push(.cloudSync) } label: {
                        settingsRow(icon: "icloud.fill", color: Theme.goldBright, title: L10n.Settings.cloudSync, value: cloudSyncValue)
                    }
                    .buttonStyle(.plain)
                    Button { router.push(.wordCount) } label: {
                        settingsRow(icon: "doc.text.fill", color: Color(hex: 0x8A6FBE), title: L10n.Settings.wordCount, value: wordsText)
                    }
                    .buttonStyle(.plain)
                    Button { router.push(.recycleBin) } label: {
                        settingsRow(icon: "trash.fill", color: Theme.danger, title: L10n.Settings.recycleBin, value: L10n.Settings.countSuffix(String(describing: store.deletedRecords.count)))
                    }
                    .buttonStyle(.plain)
                    Button { router.push(.explore) } label: {
                        settingsRow(icon: "safari.fill", color: Theme.teal, title: L10n.Settings.explore, value: L10n.Settings.mediaCounts)
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: L10n.Settings.account) {
                    Button { showLogin = true } label: {
                        settingsRow(icon: "lock.fill", color: Color(hex: 0x4C7ED6), title: L10n.Settings.doubanLoginAndCookie, value: authState == .checking ? L10n.Settings.checking : authState.label)
                    }
                    .buttonStyle(.plain)
                }

                #if DEBUG
                SettingsGroup(title: L10n.Settings.developer) {
                    Button { showClearAllData = true } label: {
                        settingsRow(icon: "trash.slash.fill", color: Theme.danger, title: L10n.Settings.clearAllData, value: L10n.Settings.clearAllDataValue)
                    }
                    .buttonStyle(.plain)
                }
                #endif

                Text(L10n.Settings.aboutAndLicenses)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .toast(message: $toast)
        .alert(L10n.Settings.clearAllDataConfirmTitle, isPresented: $showClearAllData) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Settings.clearAllDataConfirm, role: .destructive) {
                clearAllData()
            }
        } message: {
            Text(L10n.Settings.clearAllDataMessage)
        }
        .task { await refreshAuthState() }
        .task { await refreshDoubanProfile() }
        .onChange(of: showLogin) { _, isPresented in
            if !isPresented {
                Task { await refreshAuthState() }
                Task { await refreshDoubanProfile() }
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAppearance) {
            AppearancePickerSheet(selection: Binding(
                get: { appearanceRaw },
                set: { appearanceRaw = $0 }
            ))
            .presentationDetents([.height(340)])
        }
        .sheet(isPresented: $showSearch) {
            SettingsSearchSheet { target in
                showSearch = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    openSettings(target)
                }
            }
            .presentationDetents([.large])
        }
    }

    private func clearAllData() {
        CloudSyncService.resetLocalBookkeeping()
        UserDefaults.standard.removeObject(forKey: "bookfilm.recentSearches")
        store.clearAllData()
        toast = L10n.Settings.clearAllDataDone
    }

    private func refreshAuthState() async {
        let cookie = KeychainStore.loadCookie()
        if (doubanID.isEmpty || doubanID == "catnine"), let detected = DoubanSyncService.userID(fromCookie: cookie) {
            doubanID = detected
        }
        authState = cookie == nil ? .noCookie : .checking
        guard let cookie else { return }
        authState = await DoubanAuthService.validate(cookie: cookie, userID: doubanID)
    }

    private func refreshDoubanProfile() async {
        let cookie = KeychainStore.loadCookie()
        guard let cookie, !cookie.isEmpty else { return }
        let userID = DoubanSyncService.userID(fromCookie: cookie) ?? doubanID
        guard let profile = await DoubanProfileService.fetch(userID: userID, cookie: cookie),
              let avatarURL = profile.avatarURL else { return }
        doubanAvatarURL = avatarURL
    }

    private func openSettings(_ target: SettingsSearchTarget) {
        switch target {
        case .appearance:
            showAppearance = true
        case .data:
            router.push(.dataTransfer)
        case .cloud:
            router.push(.cloudSync)
        case .wordCount:
            router.push(.wordCount)
        case .recycle:
            router.push(.recycleBin)
        case .explore:
            router.push(.explore)
        case .login:
            showLogin = true
        }
    }

    private var cloudSyncValue: String {
        guard !cloudFolderName.isEmpty else { return L10n.Common.notSet }
        guard !cloudLastBackup.isEmpty else { return cloudFolderName }
        return "\(cloudFolderName) · \(CloudSyncService.lastBackupText())"
    }

    private var wordsText: String {
        let total = store.wordCountSummary().total
        guard total > 0 else { return L10n.Settings.notCounted }
        return L10n.Stats.tenThousandFormat(Double(total) / 10_000)
    }

    private func settingsRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.appBody)
                .foregroundStyle(Theme.text)
            Spacer()
            Text(value)
                .font(.appCaption)
                .foregroundStyle(Theme.text3)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 54)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.appCaptionMedium)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }
}

private struct AppearancePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var draft: String

    init(selection: Binding<String>) {
        _selection = selection
        _draft = State(initialValue: selection.wrappedValue)
    }

    private var options: [(id: String, title: String, icon: String)] {
        [
            (AppAppearance.system.rawValue, AppAppearance.system.label, "circle.lefthalf.filled"),
            (AppAppearance.light.rawValue, AppAppearance.light.label, "sun.max"),
            (AppAppearance.dark.rawValue, AppAppearance.dark.label, "moon")
        ]
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Settings.appearance,
                    leftTitle: L10n.Common.close,
                    rightTitle: L10n.Common.done,
                    onLeft: { dismiss() },
                    onRight: {
                        selection = draft
                        dismiss()
                    }
                )
            }
        } content: {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        draft = option.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.gold)
                                .frame(width: 26)
                            Text(option.title)
                                .font(.appBody)
                                .foregroundStyle(Theme.text)
                            Spacer()
                            if draft == option.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                        .frame(height: 52)
                        .padding(.horizontal, 14)
                        .background(draft == option.id ? Theme.goldSoft : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < options.count - 1 {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

private enum SettingsSearchTarget {
    case appearance, data, cloud, wordCount, recycle, explore, login
}

private struct SettingsSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (SettingsSearchTarget) -> Void

    @State private var query = ""

    private struct Item: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let target: SettingsSearchTarget
    }

    private let items: [Item] = [
        Item(title: L10n.Settings.appearance, subtitle: L10n.Settings.appearanceModeHint, icon: "sun.max.fill", color: Theme.goldBright, target: .appearance),
        Item(title: L10n.Settings.dataTransfer, subtitle: L10n.Settings.dataTransferSubtitle, icon: "square.and.arrow.up", color: Color(hex: 0x4C7ED6), target: .data),
        Item(title: L10n.Settings.cloudSync, subtitle: L10n.Settings.cloudSyncSubtitle, icon: "icloud.fill", color: Theme.goldBright, target: .cloud),
        Item(title: L10n.Settings.wordCount, subtitle: L10n.Settings.wordCountSubtitle, icon: "doc.text.fill", color: Color(hex: 0x8A6FBE), target: .wordCount),
        Item(title: L10n.Settings.recycleBin, subtitle: L10n.Settings.recycleBinSubtitle, icon: "trash.fill", color: Theme.danger, target: .recycle),
        Item(title: L10n.Settings.explore, subtitle: L10n.Settings.resourceSiteConfig, icon: "safari.fill", color: Theme.teal, target: .explore),
        Item(title: L10n.Settings.doubanLoginAndCookie, subtitle: L10n.Settings.loginAndKeychain, icon: "lock.fill", color: Color(hex: 0x4C7ED6), target: .login)
    ]

    private var filtered: [Item] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(key) || $0.subtitle.localizedCaseInsensitiveContains(key) }
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Settings.search, leftTitle: L10n.Common.close, onLeft: { dismiss() })
                SearchField(placeholder: L10n.Settings.searchSettings, text: $query)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        } content: {
            VStack(spacing: 8) {
                if filtered.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: L10n.Settings.noMatchingSettings)
                } else {
                    ForEach(filtered) { item in
                        Button {
                            onSelect(item.target)
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 29, height: 29)
                                    .background(item.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.appBody)
                                        .foregroundStyle(Theme.text)
                                    Text(item.subtitle)
                                        .font(.appCaption)
                                        .foregroundStyle(Theme.text3)
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
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
