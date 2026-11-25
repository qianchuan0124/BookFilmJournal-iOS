import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RecordDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let recordID: UUID
    var onDeleted: (() -> Void)? = nil

    @State private var showEdit = false
    @State private var showResource = false
    @State private var showCoverPicker = false
    @State private var showCoverPreview = false
    @State private var toast: String?

    private var record: MediaRecord? { store.record(id: recordID) }

    var body: some View {
        Group {
            if let record {
                SheetScaffold {
                    VStack(spacing: 0) {
                        SheetGrabber()
                        SheetHeader(
                            title: L10n.Records.recordDetail,
                            leftTitle: L10n.Common.close,
                            rightTitle: L10n.Common.edit,
                            onLeft: { dismiss() },
                            onRight: { showEdit = true }
                        )
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        detailTop(record)
                        resourceCard(record)
                        sectionTitle(L10n.Records.thoughts, trailing: record.comment.isEmpty ? nil : (toast == L10n.Records.copied ? L10n.Records.copied : L10n.Records.copy)) {
                            if !record.comment.isEmpty {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = record.comment
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                toast = L10n.Records.copied
                                #endif
                            }
                        }
                        if record.comment.isEmpty {
                            VStack(spacing: 12) {
                                Text(L10n.Records.noThoughtsYet)
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.text3)
                                Button(L10n.Records.goToAdd) { showEdit = true }
                                    .buttonStyle(GoldButtonStyle(height: 40, radius: 11))
                                    .frame(width: 128)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        } else {
                            Text(record.comment)
                                .font(.appBody)
                                .foregroundStyle(Theme.text2)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                                .padding(.horizontal, 2)
                        }

                        sectionTitle(L10n.Records.actions)
                        HStack(spacing: 8) {
                            Button {
                                DoubanLinkOpener.open(
                                    webURLString: record.doubanURL,
                                    subjectID: record.subjectID,
                                    media: record.mediaType,
                                    fallback: { openURL($0) }
                                )
                            } label: {
                                Label(L10n.Records.doubanPage, systemImage: "link")
                            }
                            .buttonStyle(OutlineButtonStyle())

                            Button {
                                showCoverPicker = true
                            } label: {
                                Label(L10n.Records.changeCover, systemImage: "photo")
                            }
                            .buttonStyle(OutlineButtonStyle())

                            Button {
                                store.deleteRecord(id: record.id)
                                onDeleted?()
                                dismiss()
                            } label: {
                                Label(L10n.Records.delete, systemImage: "trash")
                            }
                            .buttonStyle(OutlineButtonStyle(foreground: Theme.danger))
                            .frame(width: 92)
                        }
                        .padding(.top, 2)

                        Text(L10n.Records.deleteRecordMessage)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                            .lineSpacing(3)
                            .padding(.top, 10)
                            .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 16)
                }
                .toast(message: $toast)
                .sheet(isPresented: $showEdit) {
                    RecordEditorView(record: record, mediaType: record.mediaType, status: record.status, onSaved: { toast = L10n.Records.recordUpdated })
                        .presentationDetents([.large])
                }
                .sheet(isPresented: $showResource) {
                    ResourceSheet(record: record)
                        .presentationDetents([.large])
                }
                .sheet(isPresented: $showCoverPicker) {
                    CoverPickerSheet(recordID: record.id, onApplied: { toast = L10n.Records.coverChanged })
                        .presentationDetents([.large])
                }
                .fullScreenCover(isPresented: $showCoverPreview) {
                    CoverFullscreenView(record: record)
                }
            } else {
                Text(L10n.Records.recordNotFound)
                    .foregroundStyle(Theme.text2)
            }
        }
    }

    private func detailTop(_ record: MediaRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                showCoverPreview = true
            } label: {
                PosterCover(record: record)
                    .frame(width: 118)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                Text(record.title)
                    .font(.appH1)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text("\(record.mediaType.label) · \(record.statusLabel)\(record.year.map { " · " + $0 } ?? "")")
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                    if let tag = record.coverTag {
                        TagView(text: tag, style: .teal)
                    }
                }
                .padding(.top, 4)

                infoRow(L10n.Records.myRating, value: record.ratingText, valueColor: record.rating > 0 ? Theme.star : Theme.text4)
                infoRow(L10n.Records.localDate, value: record.displayDate + (record.isLocalEdited ? "  ●" : ""), valueColor: Theme.text)
                infoRow(record.mediaType == .movie ? L10n.Records.duration : L10n.Records.pagesOrWords, value: record.statsText, valueColor: Theme.text)
                infoRow(L10n.Records.source, value: record.isLocalEdited ? L10n.Records.doubanLocalEdit : L10n.Records.douban, valueColor: Theme.text)
            }
        }
        .padding(.top, 2)
    }

    private func infoRow(_ label: String, value: String, valueColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.appBodySmall)
                .foregroundStyle(Theme.text3)
            Spacer(minLength: 8)
            Text(value)
                .font(.appBodySmall)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func resourceCard(_ record: MediaRecord) -> some View {
        Button {
            showResource = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "safari")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x241804))
                    .frame(width: 34, height: 34)
                    .background(Theme.goldBright)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Records.resources)
                        .font(.appBodySmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.goldDeep)
                    Text(record.isWish ? L10n.Records.searchOnSite(String(describing: record.title)) : L10n.Records.searchSourcesHint)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Text(L10n.Records.find)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.goldDeep)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.goldSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Theme.goldBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private func sectionTitle(_ title: String, trailing: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(.appBodySmall)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text2)
            Spacer()
            if let trailing {
                Button(trailing) { action?() }
                    .font(.appCaption)
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .padding(.horizontal, 2)
    }
}

struct ResourceSheet: View {
    @Environment(ExploreStore.self) private var explore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let record: MediaRecord
    @State private var toast: String?

    private var sites: [ExploreSite] {
        explore.sites(for: record.mediaType)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(title: L10n.Records.resources, leftTitle: L10n.Common.close, rightTitle: L10n.Common.done, onLeft: { dismiss() }, onRight: { dismiss() })
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.title)
                            .font(.appH1)
                            .foregroundStyle(Theme.text)
                        Text("\(record.mediaType.label) · \(record.statusLabel) · \(record.statsText)")
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    TagView(text: record.statusLabel, style: record.isWish ? .wish : .read)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.text3)
                    Text(record.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    TagView(text: L10n.Records.titleAutoFill, style: .gold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.subtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                SectionHeading(title: L10n.Records.siteSummary(String(describing: record.mediaType.label), String(describing: sites.count)), trailing: L10n.Records.preferSearchURL)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                InfoGroup {
                    ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                        siteRow(site, isLast: index == sites.count - 1)
                    }
                }
                .padding(.horizontal, 16)

                SectionHeading(title: L10n.Records.other, trailing: L10n.Records.fallbackEntry)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                Button {
                    DoubanLinkOpener.open(
                        webURLString: record.doubanURL,
                        subjectID: record.subjectID,
                        media: record.mediaType,
                        fallback: { openURL($0) }
                    )
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "link")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color(hex: 0x4C7ED6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(L10n.Records.doubanItem)
                            .font(.appBody)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(L10n.Records.open)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Text(L10n.Records.searchURLHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
        }
        .toast(message: $toast)
    }

    private func siteRow(_ site: ExploreSite, isLast: Bool) -> some View {
        Button {
            if let url = site.searchURL(for: record.title) {
                openURL(url)
            }
        } label: {
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
                        if site.isLocal { TagView(text: L10n.Records.local, style: .teal) }
                    }
                    Text(site.searchURLTemplate == nil ? L10n.Records.openSiteHome : L10n.Records.siteSearchTitleAutoFill)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
                if explore.isReachable(site) == false {
                    TagView(text: L10n.Records.errorState, style: .wish)
                } else {
                    TagView(text: site.searchURLTemplate == nil ? L10n.Records.open : L10n.Records.searchAction, style: .gold)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 45)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private enum CoverChoice: Equatable {
    case link
    case builtin(PosterArt)
    case douban
}

private struct CoverPickerSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let recordID: UUID
    var onApplied: () -> Void = {}

    @State private var coverLink = ""
    @State private var isResolvingLink = false
    @State private var linkError: String?
    @State private var pendingCoverData: Data?
    @State private var pendingCoverImage: UIImage?
    @State private var choice: CoverChoice?

    private var record: MediaRecord? { store.record(id: recordID) }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Records.chooseCover,
                    leftTitle: L10n.Common.close,
                    rightTitle: L10n.Records.confirm,
                    rightDisabled: !canConfirm || isResolvingLink,
                    onLeft: { dismiss() },
                    onRight: { confirmCover() }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.Records.coverPickerHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)

                if record?.isCustomCover == true || record?.coverURL != nil {
                    Button {
                        choice = .douban
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: choice == .douban ? "checkmark.circle.fill" : "arrow.uturn.backward")
                            Text(choice == .douban ? L10n.Records.doubanCoverSelected : L10n.Records.chooseOriginalDoubanCover)
                        }
                    }
                    .buttonStyle(OutlineButtonStyle(height: 38, foreground: Theme.gold))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Records.changeCoverByLink)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                    HStack(spacing: 8) {
                        TextField("", text: $coverLink, prompt: Text("https://movie.douban.com/subject/…").font(.system(size: 15)).foregroundColor(Theme.text3))
                            .font(.system(size: 15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 11)
                            .frame(height: 38)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
                        Button {
                            Task { await parseLinkCover() }
                        } label: {
                            if isResolvingLink {
                                ProgressView().tint(Theme.goldDeep).frame(width: 58, height: 38)
                            } else {
                                Text(L10n.Records.parse)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.goldDeep)
                                    .padding(.horizontal, 10)
                                    .frame(height: 38)
                                    .background(Theme.goldSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolvingLink || coverLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let linkError {
                        Text(linkError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.danger)
                    }
                    Text(L10n.Records.coverLinkSupportHint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text4)
                }

                if let previewImage = pendingCoverImage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Records.parseResult)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                        HStack(spacing: 12) {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 62, height: 93)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .clipped()
                                .onTapGesture { choice = .link }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.Records.doubanLinkCover)
                                    .font(.appBodySmall)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.text)
                                Text(choice == .link ? L10n.Records.coverSelectedHint : L10n.Records.tapToSelectCover)
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.text3)
                                HStack(spacing: 12) {
                                    Button(choice == .link ? L10n.Records.selected : L10n.Records.select) {
                                        choice = .link
                                    }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(choice == .link ? Theme.goldDeep : Theme.text3)
                                    .buttonStyle(.plain)
                                    Button(L10n.Common.remove) {
                                        pendingCoverData = nil
                                        pendingCoverImage = nil
                                        if choice == .link { choice = nil }
                                    }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.text3)
                                    .buttonStyle(.plain)
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(choice == .link ? Theme.goldSoft : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(choice == .link ? Theme.gold : Theme.goldBorder, lineWidth: choice == .link ? 2 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { choice = .link }
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(PosterArt.allCases, id: \.self) { art in
                        Button {
                            choice = .builtin(art)
                        } label: {
                            VStack(spacing: 5) {
                                PosterArtwork(art: art)
                                    .aspectRatio(2 / 3, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(choice == .builtin(art) ? Theme.gold : Theme.border, lineWidth: choice == .builtin(art) ? 2 : 1)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if choice == .builtin(art) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 17))
                                                .foregroundStyle(Theme.gold, .white)
                                                .padding(4)
                                        }
                                    }
                                Text(artLabel(art))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(choice == .builtin(art) ? Theme.gold : Theme.text3)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            if choice == nil, let record, record.usesBuiltinCover {
                choice = .builtin(record.art)
            }
        }
    }

    private var canConfirm: Bool {
        switch choice {
        case .link: pendingCoverData != nil
        case .builtin, .douban: true
        case nil: false
        }
    }

    private func parseLinkCover() async {
        guard let value = record else { return }
        let text = coverLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DoubanCoverResolver.parse(text) != nil else {
            linkError = L10n.Records.invalidCoverLink
            return
        }
        isResolvingLink = true
        linkError = nil
        pendingCoverData = nil
        pendingCoverImage = nil
        if choice == .link { choice = nil }
        defer { isResolvingLink = false }

        let cookie = KeychainStore.loadCookie()
        guard let imageURL = await DoubanCoverResolver.coverURL(for: text, fallbackMedia: value.mediaType, cookie: cookie) else {
            linkError = L10n.Records.coverNotFound
            return
        }
        guard let data = await CoverStore.fetchImageData(urlString: imageURL),
              let image = UIImage(data: data) else {
            linkError = L10n.Records.coverDownloadFailed
            return
        }
        pendingCoverData = data
        pendingCoverImage = image
        choice = .link
    }

    private func confirmCover() {
        guard let value = record, let choice else { return }
        var updated = value
        switch choice {
        case .link:
            guard let data = pendingCoverData,
                  CoverStore.write(data: data, key: CoverStore.linkKey(for: value.subjectID)) else {
                linkError = L10n.Records.coverSaveFailed
                return
            }
            updated.coverSource = .link
            updated.localCover = true
        case .builtin(let art):
            updated.art = art
            updated.coverSource = .builtin
            updated.localCover = true
            CoverStore.removeCover(for: CoverStore.linkKey(for: value.subjectID))
        case .douban:
            updated.coverSource = .douban
            updated.localCover = false
            CoverStore.removeCover(for: CoverStore.linkKey(for: value.subjectID))
        }
        store.updateRecord(updated)
        onApplied()
        dismiss()
    }

    private func artLabel(_ art: PosterArt) -> String {
        switch art {
        case .war: L10n.Records.battle
        case .stage: L10n.Records.stage
        case .space: L10n.Records.space
        case .road: L10n.Records.road
        case .dunes: L10n.Records.dune
        case .mountains: L10n.Records.wilderness
        case .sea: L10n.Records.sea
        case .bokeh: L10n.Records.lightSpot
        case .forest: L10n.Records.forest
        case .city: L10n.Records.city
        case .nebula: L10n.Records.nebula
        case .anime: L10n.Records.animation
        case .volcano: L10n.Records.volcano
        case .bookCream: L10n.Records.bookBeige
        case .bookViolet: L10n.Records.bookPurple
        case .bookSand: L10n.Records.bookSand
        case .bookIvory: L10n.Records.bookWhite
        case .bookCharcoal: L10n.Records.bookInk
        case .bookSage: L10n.Records.bookGrayGreen
        case .bookTeal: L10n.Records.bookCyan
        }
    }
}
