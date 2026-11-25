import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ExploreView: View {
    @Environment(ExploreStore.self) private var explore
    @Environment(\.openURL) private var openURL

    @State private var showAdd = false
    @State private var editingSite: ExploreSite?
    @State private var detailSite: ExploreSite?
    @State private var deleteTarget: ExploreSite?
    @State private var toast: String?

    var body: some View {
        PageScaffoldNoScroll {
            VStack(alignment: .leading, spacing: 7) {
                NavHeader(
                    title: L10n.Explore.title,
                    backLabel: L10n.Explore.settingsAction,
                    trailing: AnyView(
                        Image(systemName: "safari")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                    )
                )

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await explore.pull()
                            toast = explore.message
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if explore.isPulling {
                                ProgressView().tint(Color(hex: 0x241804)).scaleEffect(0.7)
                            } else {
                                Image(systemName: "icloud.and.arrow.down")
                            }
                            Text(L10n.Explore.pull)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x241804))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        LinearGradient(colors: [Color(hex: 0xF4D083), Color(hex: 0xBC7C1D)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Button {
                        Task {
                            await explore.refresh(timeout: 15)
                            toast = explore.message
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if explore.isRefreshing {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(L10n.Explore.connectivityCheck)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.subtle)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Spacer()

                    Button {
                        showAdd = true
                    } label: {
                        Label(L10n.Explore.addNew, systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.goldDeep)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Theme.goldSoft)
                            .overlay(Capsule().stroke(Theme.goldBorder, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)

                configCard
                    .padding(.horizontal, 16)
            }
            .padding(.top, 0)
        } content: {
            List {
                siteSection(media: .movie, showHint: true)
                siteSection(media: .book)

                Section {
                    Text(L10n.Explore.remoteConfigHint)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .lineSpacing(3)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 24, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
        .toast(message: $toast)
        .sheet(isPresented: $showAdd) {
            AddLocalSiteSheet(onSaved: { toast = $0 })
                .presentationDetents([.large])
        }
        .sheet(item: $editingSite) { site in
            AddLocalSiteSheet(editing: site, onSaved: { toast = $0 })
                .presentationDetents([.large])
        }
        .sheet(item: $detailSite) { site in
            SiteDetailSheet(
                site: site,
                onEdit: { value in
                    detailSite = nil
                    DispatchQueue.main.async { editingSite = value }
                },
                onDelete: { value in
                    detailSite = nil
                    DispatchQueue.main.async { deleteTarget = value }
                }
            )
            .presentationDetents([.medium])
        }
        .alert(Text(L10n.Explore.deleteSiteConfirm), isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button(L10n.Common.cancel, role: .cancel) { deleteTarget = nil }
            Button(L10n.Explore.delete, role: .destructive) {
                if let site = deleteTarget {
                    explore.deleteSite(id: site.id)
                    toast = L10n.Explore.siteDeleted
                }
                deleteTarget = nil
            }
        } message: {
            Text(L10n.Explore.deleteSiteHint)
        }
    }

    private func siteSection(media: MediaType, showHint: Bool = false) -> some View {
        let sites = explore.sites(for: media)
        return Section {
            if showHint {
                Text(L10n.Explore.reorderHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            SectionHeading(
                title: media == .movie ? L10n.Explore.movie : L10n.Explore.book,
                trailing: L10n.Explore.siteCountHint(String(describing: sites.count))
            )
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 0)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(sites) { site in
                siteRow(site)
            }
            .onMove { source, destination in
                explore.moveSites(media: media, from: source, to: destination)
                toast = L10n.Explore.orderUpdated
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var configCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(Color(hex: 0x4C7ED6))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(L10n.Explore.configSource)
                    .font(.appBody)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(explore.configSourceLabel)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 53)

            HStack(spacing: 8) {
                Text(L10n.Explore.configStatus)
                    .font(.appBody)
                    .foregroundStyle(Theme.text2)
                Spacer()
                TagView(text: "v\(explore.remoteVersion)", style: .gold)
                Text(explore.lastConfigSourceName.map { "\($0) · sites.json" } ?? "sites.json")
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                TagView(
                    text: explore.reachability.isEmpty ? L10n.Explore.pendingCheck : reachableText,
                    style: explore.reachability.isEmpty ? .neutral : .read
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var reachableText: String {
        guard !explore.reachability.isEmpty else { return L10n.Explore.notChecked }
        return L10n.Explore.reachableCount(String(describing: explore.reachableCount), String(describing: explore.sites.count))
    }

    private func siteRow(_ site: ExploreSite) -> some View {
        HStack(spacing: 10) {
            Group {
                switch explore.isReachable(site) {
                case true?:
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.read)
                        .background(Circle().fill(Theme.readSoft).frame(width: 22, height: 22))
                case false?:
                    Image(systemName: "xmark")
                        .foregroundStyle(Theme.danger)
                        .background(Circle().fill(Theme.dangerSoft).frame(width: 22, height: 22))
                case nil:
                    Image(systemName: "questionmark")
                        .foregroundStyle(Theme.text4)
                        .background(Circle().fill(Theme.subtle).frame(width: 22, height: 22))
                }
            }
            .font(.system(size: 11, weight: .bold))
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(site.name)
                        .font(.appBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if site.isLocal {
                        TagView(text: L10n.Explore.local, style: .teal)
                    }
                }
                Text(site.urlString)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text4)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { detailSite = site }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct SiteDetailSheet: View {
    @Environment(ExploreStore.self) private var explore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let site: ExploreSite
    let onEdit: (ExploreSite) -> Void
    let onDelete: (ExploreSite) -> Void

    private var current: ExploreSite {
        explore.sites.first { $0.id == site.id } ?? site
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Explore.siteDetail, leftTitle: L10n.Common.close, onLeft: { dismiss() })
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(current.name)
                            .font(.appH1)
                            .foregroundStyle(Theme.text)
                        HStack(spacing: 5) {
                            TagView(text: current.kind == .movie ? L10n.Explore.movie : L10n.Explore.book, style: .gold)
                            TagView(text: current.isLocal ? L10n.Explore.local : L10n.Explore.remote, style: current.isLocal ? .teal : .neutral)
                        }
                    }
                    Spacer()
                }

                InfoGroup {
                    FieldRow(label: L10n.Explore.siteAddress) {
                        Text(current.urlString)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    FieldRow(label: L10n.Explore.searchLink, showDivider: false) {
                        Text(current.searchURLTemplate ?? L10n.Explore.notConfigured)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        if let url = current.url { openURL(url) }
                    } label: {
                        Label(L10n.Explore.open, systemImage: "safari")
                    }
                    .buttonStyle(OutlineButtonStyle(foreground: Theme.gold))

                    Button {
                        onEdit(current)
                        dismiss()
                    } label: {
                        Label(L10n.Explore.edit, systemImage: "pencil")
                    }
                    .buttonStyle(OutlineButtonStyle())

                    Button {
                        onDelete(current)
                        dismiss()
                    } label: {
                        Label(L10n.Explore.delete, systemImage: "trash")
                    }
                    .buttonStyle(OutlineButtonStyle(foreground: Theme.danger))
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct AddLocalSiteSheet: View {
    @Environment(ExploreStore.self) private var explore
    @Environment(\.dismiss) private var dismiss

    let editing: ExploreSite?
    var onSaved: ((String) -> Void)? = nil

    @State private var kind: MediaType
    @State private var name: String
    @State private var urlString: String
    @State private var searchURL: String
    @State private var toast: String?

    init(editing: ExploreSite? = nil, onSaved: ((String) -> Void)? = nil) {
        self.editing = editing
        self.onSaved = onSaved
        _kind = State(initialValue: editing?.kind ?? .movie)
        _name = State(initialValue: editing?.name ?? "")
        _urlString = State(initialValue: editing?.urlString ?? "")
        _searchURL = State(initialValue: editing?.searchURLTemplate ?? "")
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: editing == nil ? L10n.Explore.newSite : L10n.Explore.editSite, leftTitle: L10n.Common.cancel, rightTitle: L10n.Common.save, onLeft: { dismiss() }, onRight: { save() })
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                AppSegmented(
                    options: MediaType.allCases,
                    selection: $kind,
                    title: { $0 == .movie ? L10n.Explore.movie : L10n.Explore.book },
                    gold: true
                )
                .padding(.horizontal, 16)

                fieldLabel(L10n.Explore.siteName)
                textField(L10n.Explore.myNasLibrary, text: $name)
                fieldLabel(L10n.Explore.siteLink)
                textField("https://example.com/movies", text: $urlString)
                fieldLabel(L10n.Explore.searchLinkOptional)
                textField("https://example.com/search?q={title}", text: $searchURL)

                Text(L10n.Explore.searchLinkHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                InfoGroup {
                    FieldRow(label: L10n.Explore.checkAfterSave) {
                        Text(L10n.Explore.automatic)
                            .foregroundStyle(Theme.text3)
                    }
                    FieldRow(label: L10n.Explore.localOnly, showDivider: false) {
                        Text(L10n.Explore.noGithubSync)
                            .foregroundStyle(Theme.text3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Text(L10n.Explore.localSiteHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
        }
        .toast(message: $toast)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.appCaption)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 18)
            .padding(.top, 14)
    }

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.appBody)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 6)
    }

    private func save() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let parsed = URL(string: url), parsed.scheme == "https" || parsed.scheme == "http" else {
            toast = L10n.Explore.invalidSiteHint
            return
        }
        if let editing {
            explore.updateSite(
                id: editing.id,
                name: name,
                urlString: url,
                searchURLTemplate: searchURL,
                kind: kind
            )
        } else {
            explore.addLocalSite(
                name: name,
                urlString: url,
                searchURLTemplate: searchURL,
                kind: kind
            )
        }
        onSaved?(editing == nil ? L10n.Explore.siteAdded : L10n.Explore.siteUpdated)
        dismiss()
    }
}
