import SwiftUI

struct RecordEditorView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let record: MediaRecord?
    let mediaType: MediaType
    var onSaved: (() -> Void)? = nil

    @State private var title: String
    @State private var status: RecordStatus
    @State private var date: Date
    @State private var rating: Int
    @State private var durationText: String
    @State private var pagesText: String
    @State private var wordsText: String
    @State private var comment: String
    @State private var intro: String
    @State private var year: String
    @State private var subjectID: String
    @State private var linkText: String
    @State private var resetOriginalDate: Bool = false
    @State private var showDatePicker = false
    @State private var isParsingLink = false
    @State private var linkMessage = ""
    @State private var toast: String?

    init(record: MediaRecord?, mediaType: MediaType, status: RecordStatus, onSaved: (() -> Void)? = nil) {
        self.record = record
        self.mediaType = mediaType
        self.onSaved = onSaved
        _title = State(initialValue: record?.title ?? "")
        _status = State(initialValue: record?.status ?? status)
        _date = State(initialValue: record?.effectiveDate ?? Date())
        _rating = State(initialValue: record?.rating ?? 0)
        _durationText = State(initialValue: record?.durationMinutes.map { String($0) } ?? "")
        _pagesText = State(initialValue: record?.pages.map { String($0) } ?? "")
        _wordsText = State(initialValue: record?.wordCount.map { String($0) } ?? "")
        _comment = State(initialValue: record?.comment ?? "")
        _intro = State(initialValue: record?.intro ?? "")
        _year = State(initialValue: record?.year ?? "")
        _subjectID = State(initialValue: record?.subjectID ?? "")
        _linkText = State(initialValue: record?.doubanURL ?? "")
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: record == nil ? L10n.Records.addRecord(String(describing: mediaType.label)) : L10n.Records.editRecord,
                    leftTitle: L10n.Common.cancel,
                    rightTitle: L10n.Common.save,
                    onLeft: { dismiss() },
                    onRight: { save() }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    PosterCover(record: draft)
                        .frame(width: 76)
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
                    VStack(alignment: .leading, spacing: 9) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Records.titleLabel)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text3)
                            TextField(L10n.Records.enterTitle(String(describing: mediaType.label)), text: $title)
                                .font(.appBody)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(Theme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(title.isEmpty ? Theme.borderStrong : Theme.goldBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Records.doubanLinkParse)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text3)
                            HStack(spacing: 6) {
                                TextField(L10n.Records.pasteDoubanLink, text: $linkText)
                                    .font(.appBody)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .keyboardType(.URL)
                                    .onSubmit { parseLink() }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(Theme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(Theme.borderStrong, lineWidth: 1)
                                    )
                                Button {
                                    parseLink()
                                } label: {
                                    if isParsingLink {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Text(L10n.Records.parse)
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(Theme.gold)
                                .frame(width: 58, height: 40)
                                .background(Theme.goldSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .disabled(isParsingLink)
                            }
                        }
                        if !linkMessage.isEmpty {
                            Text(linkMessage)
                                .font(.appCaption)
                                .foregroundStyle(linkMessage.hasPrefix(L10n.Records.parsed) ? Theme.read : Theme.danger)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)

                InfoGroup {
                    FieldRow(label: L10n.Records.localDate) {
                        Button {
                            showDatePicker = true
                        } label: {
                            HStack(spacing: 5) {
                                Text(dateText)
                                    .font(.appBodySmall)
                                    .foregroundStyle(Theme.text)
                                Image(systemName: "calendar")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    FieldRow(label: L10n.Records.status) {
                        AppSegmented(
                            options: RecordStatus.allCases,
                            selection: $status,
                            title: { $0.label(for: mediaType) },
                            gold: true,
                            compact: true,
                            fitContent: true
                        )
                        .fixedSize()
                    }
                    FieldRow(label: L10n.Records.rating) {
                        HStack(spacing: 5) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    rating = rating == value ? 0 : value
                                } label: {
                                    Image(systemName: value <= rating ? "star.fill" : "star")
                                        .font(.system(size: 15.5))
                                        .foregroundStyle(value <= rating ? Theme.star : Theme.text4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if mediaType == .movie {
                        FieldRow(label: L10n.Records.durationMinutes, hint: StatsInputFormat.durationHint(durationText)) {
                            numberField($durationText, placeholder: L10n.Records.durationExample)
                        }
                    } else {
                        FieldRow(label: L10n.Records.pagesOrWords, hint: StatsInputFormat.wordsHint(wordsText).map { L10n.Records.wordCountHint($0) }) {
                            HStack(spacing: 6) {
                                numberField($pagesText, placeholder: L10n.Records.pages)
                                Text("/").foregroundStyle(Theme.text4)
                                numberField($wordsText, placeholder: L10n.Records.words)
                            }
                        }
                    }
                    if record != nil {
                        FieldRow(label: L10n.Records.restoreDoubanTime, showDivider: false) {
                            Toggle("", isOn: $resetOriginalDate)
                                .labelsHidden()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                SectionHeading(title: L10n.Records.shortReview)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                TextEditor(text: $comment)
                    .font(.appBody)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 74)
                    .padding(10)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)

                Button {
                    save()
                } label: {
                    Label(record == nil ? L10n.Records.saveRecord : L10n.Records.saveChanges, systemImage: "checkmark")
                }
                .buttonStyle(GoldButtonStyle(height: 42))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .toast(message: $toast)
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(date: $date)
                .presentationDetents([.medium])
        }
    }

    private var draft: MediaRecord {
        MediaRecord(
            id: record?.id ?? UUID(),
            mediaType: mediaType,
            status: status,
            title: title.isEmpty ? L10n.Records.untitled : title,
            subjectID: subjectID.isEmpty ? "manual-\(UUID().uuidString)" : subjectID,
            doubanURL: linkText.isEmpty ? nil : linkText,
            coverURL: record?.coverURL,
            localCover: record?.localCover,
            coverSource: record?.coverSource,
            art: record?.art ?? (mediaType == .movie ? .war : .bookCream),
            markedDate: record?.markedDate ?? date,
            effectiveDate: date,
            rating: rating,
            comment: comment,
            intro: intro,
            durationMinutes: Int(durationText),
            pages: Int(pagesText),
            wordCount: Int(wordsText),
            year: year.isEmpty ? nil : year,
            releaseDate: record?.releaseDate,
            isLocalEdited: true,
            deletedAt: nil,
            deleteSource: nil,
            isHidden: record?.isHidden
        )
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: date)
    }

    private func parseLink() {
        let raw = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            linkMessage = L10n.Records.pasteDoubanLinkFirst
            return
        }
        isParsingLink = true
        linkMessage = ""
        Task {
            do {
                let parsed = try await DoubanLinkParser.parse(raw, expected: mediaType)
                title = parsed.title
                subjectID = parsed.subjectID
                linkText = parsed.url
                intro = parsed.intro
                if let parsedYear = parsed.year { year = parsedYear }
                if let duration = parsed.durationMinutes { durationText = String(duration) }
                if let pages = parsed.pages { pagesText = String(pages) }
                linkMessage = L10n.Records.parsedWithTitle(String(describing: parsed.title))
                isParsingLink = false
            } catch {
                linkMessage = error.localizedDescription
                isParsingLink = false
            }
        }
    }

    private func numberField(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.appBody)
            .frame(maxWidth: 130)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast = L10n.Records.enterTitleFirst
            return
        }
        let value = draft
        if record == nil {
            store.addRecord(value)
        } else if resetOriginalDate, let original = record {
            var updated = value
            updated.effectiveDate = original.markedDate
            updated.isLocalEdited = false
            store.updateRecord(updated)
        } else {
            store.updateRecord(value)
        }
        onSaved?()
        dismiss()
    }
}
