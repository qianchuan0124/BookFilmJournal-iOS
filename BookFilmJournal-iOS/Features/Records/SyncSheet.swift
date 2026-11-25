import SwiftUI

struct SyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store

    let media: MediaType

    @AppStorage("bookfilm.doubanID") private var doubanID = "catnine"
    @State private var mode: DoubanSyncMode = .incrementalSync
    @State private var scopes = Set(DoubanSyncScope.allCases)
    @State private var syncDoulists = true
    @State private var isSyncing = false
    @State private var showLogin = false
    @State private var toast: String?
    @State private var cookieSaved = KeychainStore.loadCookie() != nil
    @State private var authState: DoubanAuthState = .noCookie
    @State private var lastSyncText = ""
    @State private var lastSummaryText = ""
    @State private var progress = 0.0
    @State private var progressText = ""

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Records.syncDouban,
                    leftTitle: L10n.Common.close,
                    rightTitle: L10n.Records.startSync,
                    onLeft: { dismiss() },
                    onRight: { startSync() }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                InfoGroup {
                    FieldRow(label: L10n.Records.doubanID) {
                        TextField(L10n.Records.enterDoubanID, text: $doubanID)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    FieldRow(label: L10n.Records.loginStatus, showDivider: false) {
                        HStack(spacing: 6) {
                            Image(systemName: authState == .valid ? "checkmark.shield.fill" : (authState == .expired ? "exclamationmark.shield.fill" : "lock.open"))
                                .foregroundStyle(authState == .valid ? Theme.read : (authState == .expired ? Theme.danger : Theme.text4))
                            Text(authState.label)
                                .foregroundStyle(authState == .valid ? Theme.read : (authState == .expired ? Theme.danger : Theme.text3))
                            Button(authActionTitle) {
                                if authState == .unknown {
                                    Task { await refreshAuthState() }
                                } else {
                                    showLogin = true
                                }
                            }
                            .font(.appCaption)
                            .foregroundStyle(Theme.gold)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Text(L10n.Records.syncScopeHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                SectionHeading(title: L10n.Records.syncMode)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                InfoGroup {
                    ForEach(Array(DoubanSyncMode.allCases.enumerated()), id: \.element.id) { index, option in
                        Button {
                            mode = option
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .stroke(mode == option ? Theme.gold : Theme.borderStrong, lineWidth: 1.5)
                                    .background(
                                        Circle()
                                            .fill(mode == option ? Theme.gold : Color.clear)
                                            .padding(4)
                                    )
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.appBody)
                                        .foregroundStyle(Theme.text)
                                    Text(option.note)
                                        .font(.appCaption)
                                        .foregroundStyle(Theme.text3)
                                }
                                Spacer()
                                if option == .incrementalSync {
                                    TagView(text: L10n.Records.recommendation, style: .gold)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) {
                                if index < DoubanSyncMode.allCases.count - 1 {
                                    Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                SectionHeading(title: L10n.Records.syncScope)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                InfoGroup {
                    scopeRow(L10n.Records.movieRecords, detail: L10n.Sync.countUnit(String(describing: store.activeRecords(media: .movie, status: .done).count), L10n.Media.movieNoun), isOn: scopeBinding(.movieDone))
                    scopeRow(L10n.Records.bookRecords, detail: L10n.Sync.countUnit(String(describing: store.activeRecords(media: .book, status: .done).count), L10n.Media.bookNoun), isOn: scopeBinding(.bookDone))
                    scopeRow(L10n.Records.movieWish, detail: L10n.Sync.countUnit(String(describing: store.activeRecords(media: .movie, status: .wish).count), L10n.Media.movieNoun), isOn: scopeBinding(.movieWish))
                    scopeRow(L10n.Records.bookWish, detail: L10n.Sync.countUnit(String(describing: store.activeRecords(media: .book, status: .wish).count), L10n.Media.bookNoun), isOn: scopeBinding(.bookWish))
                    scopeRow(L10n.Records.doulist, detail: L10n.Records.count(String(describing: store.activeDoulists.count)), isOn: $syncDoulists, showDivider: false)
                }
                .padding(.horizontal, 16)

                Text(L10n.Records.syncMergeHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                SectionHeading(title: L10n.Records.lastSync, trailing: lastSyncText.isEmpty ? L10n.Records.none : lastSyncText)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                InfoGroup {
                    FieldRow(label: L10n.Records.syncResult) {
                        Text(lastSummaryText.isEmpty ? L10n.Common.none : lastSummaryText)
                            .foregroundStyle(Theme.text3)
                    }
                    FieldRow(label: L10n.Records.syncMode) {
                        Text(mode == .full ? L10n.Sync.fullReplace : mode == .incrementalAdd ? L10n.Sync.addOnly : L10n.Sync.incremental)
                            .foregroundStyle(Theme.text3)
                    }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(Theme.gold)
                        .frame(height: 4)
                    Text(progressText.isEmpty ? " " : progressText)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .lineLimit(2)
                        .frame(height: 32, alignment: .topLeading)
                }
                .frame(height: 42)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .opacity(isSyncing ? 1 : 0)
                .allowsHitTesting(false)

                Button {
                    startSync()
                } label: {
                    if isSyncing {
                        ProgressView()
                            .tint(Color(hex: 0x241804))
                    } else {
                        Label(L10n.Records.startSync, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(isSyncing)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Text(L10n.Records.syncDataHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text4)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        }
        .toast(message: $toast)
        .sheet(isPresented: $showLogin) {
            LoginSheet()
                .presentationDetents([.large])
        }
        .onChange(of: showLogin) { _, isPresented in
            if !isPresented {
                cookieSaved = KeychainStore.loadCookie() != nil
                Task { await refreshAuthState() }
            }
        }
        .onAppear {
            refreshLastSync()
            Task { await refreshAuthState() }
        }
        .onChange(of: doubanID) { _, _ in
            Task { await refreshAuthState() }
        }
    }

    private func scopeRow(_ title: String, detail: String, isOn: Binding<Bool>, showDivider: Bool = true) -> some View {
        FieldRow(label: title, showDivider: showDivider) {
            HStack(spacing: 8) {
                Text(detail)
                    .foregroundStyle(Theme.text3)
                Toggle("", isOn: isOn)
                    .labelsHidden()
            }
        }
    }

    private func refreshLastSync() {
        let defaults = UserDefaults.standard
        let time = defaults.double(forKey: "bookfilm.sync.lastTime")
        if time > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M 月 d 日 HH:mm"
            lastSyncText = formatter.string(from: Date(timeIntervalSince1970: time))
        } else {
            lastSyncText = ""
        }
        if let summary = defaults.string(forKey: "bookfilm.sync.lastSummary") {
            let parts = summary.split(separator: "|").map(String.init)
            if parts.count == 3 {
                lastSummaryText = L10n.Sync.lastSummary(parts[0], parts[1], parts[2])
            } else {
                lastSummaryText = summary
            }
        } else {
            lastSummaryText = ""
        }
    }

    private var authActionTitle: String {
        switch authState {
        case .unknown: L10n.Records.retry
        case .valid: L10n.Records.switchAccount
        case .expired: L10n.Records.relogin
        case .noCookie, .checking: L10n.Records.login
        }
    }

    private func refreshAuthState() async {
        let cookie = KeychainStore.loadCookie()
        cookieSaved = cookie != nil
        let id = doubanID.trimmingCharacters(in: .whitespacesAndNewlines)
        if (id.isEmpty || id == "catnine"), let detected = DoubanSyncService.userID(fromCookie: cookie) {
            doubanID = detected
        }
        if cookie == nil {
            authState = .noCookie
            return
        }
        authState = .checking
        authState = await DoubanAuthService.validate(cookie: cookie, userID: doubanID)
    }

    private func scopeBinding(_ scope: DoubanSyncScope) -> Binding<Bool> {
        Binding(
            get: { scopes.contains(scope) },
            set: { enabled in
                if enabled { scopes.insert(scope) } else { scopes.remove(scope) }
            }
        )
    }

    private func startSync() {
        guard !isSyncing else { return }
        let cookie = KeychainStore.loadCookie()
        var id = doubanID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty || id == "catnine", let detected = DoubanSyncService.userID(fromCookie: cookie) {
            doubanID = detected
            id = detected
        }
        guard !id.isEmpty else {
            toast = L10n.Records.enterDoubanIDFirst
            return
        }
        let selectedScopes = DoubanSyncScope.allCases.filter { scopes.contains($0) }
        guard !selectedScopes.isEmpty || syncDoulists else {
            toast = L10n.Records.selectSyncScopeFirst
            return
        }
        isSyncing = true
        progress = 0
        progressText = L10n.Records.preparingSync
        Task {
            do {
                let result = try await DoubanSyncService.sync(
                    userID: id,
                    cookie: cookie,
                    scopes: selectedScopes,
                    syncDoulists: syncDoulists,
                    mode: mode,
                    store: store,
                    progress: { value, text in
                        progress = value
                        progressText = text
                    }
                )
                isSyncing = false
                refreshLastSync()
                if syncDoulists {
                    toast = L10n.Sync.doneFull(String(describing: result.added), String(describing: result.updated), String(describing: result.removed), String(describing: result.doulists), String(describing: result.doulistItems))
                } else {
                    toast = L10n.Sync.doneBasic(String(describing: result.added), String(describing: result.updated), String(describing: result.removed))
                }
            } catch {
                isSyncing = false
                progressText = ""
                toast = error.localizedDescription
            }
        }
    }
}
