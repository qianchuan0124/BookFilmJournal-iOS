import SwiftUI

struct ReportView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @State private var media: MediaType = .movie
    @State private var scope: ReportScope = .month
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var darkTheme = true
    @State private var exportPNG = true
    @State private var startDate = Date().addingTimeInterval(-86400 * 30)
    @State private var endDate = Date()
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false
    @State private var showPeriodPicker = false
    @State private var toast: String?

    private var reports: [GeneratedReport] {
        store.reports.filter { $0.mediaType == media }
    }

    private var currentMonthCount: Int {
        let calendar = Calendar.current
        return reports.filter { calendar.isDate($0.generatedAt, equalTo: Date(), toGranularity: .month) }.count
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 4...current).reversed())
    }

    var body: some View {
        PageScaffold {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Report.reportCenter)
                            .font(.appDisplay)
                            .foregroundStyle(Theme.text)
                        Text(L10n.Report.reportLayoutHint)
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    IconCircleButton(systemName: "clock.arrow.circlepath", action: { toast = L10n.Report.recentReportsHint })
                        .padding(.top, 4)
                }

                AppSegmented(
                    options: MediaType.allCases,
                    selection: $media,
                    title: { $0.label },
                    gold: true,
                    fitContent: true
                )
                .fixedSize(horizontal: true, vertical: false)

                HStack {
                    Text(L10n.Report.generatedSummary(String(describing: reports.count), store.reports.first.map { DateFormatter.reportDate.string(from: $0.generatedAt) } ?? "—"))
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    TagView(text: L10n.Report.currentMonthCount(String(describing: currentMonthCount)), style: .gold)
                }

                ChipBar(
                    items: [
                        ChipItem(id: "month", label: L10n.Report.monthlyReport),
                        ChipItem(id: "year", label: L10n.Report.yearlyReport),
                        ChipItem(id: "custom", label: L10n.Report.custom),
                        ChipItem(id: "all", label: L10n.Report.all)
                    ],
                    selectedID: Binding(
                        get: { scope.rawValue },
                        set: { scope = ReportScope(rawValue: $0) ?? .month }
                    )
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } content: {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(L10n.Report.generateReport)
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        TagView(text: media == .movie ? L10n.Report.movieActivity : L10n.Report.bookActivity, style: .gold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                    if scope == .month || scope == .year {
                        FieldRow(label: scope == .month ? L10n.Report.month : L10n.Report.year) {
                            Button {
                                showPeriodPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: scope == .month ? L10n.Report.yearMonth(String(describing: year), String(describing: month)) : L10n.Report.yearLabel(String(describing: year)))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(Theme.text)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if scope == .custom {
                        FieldRow(label: L10n.Report.start) {
                            Button {
                                showStartDatePicker = true
                            } label: {
                                HStack(spacing: 5) {
                                    Text(fullDateText(startDate))
                                        .font(.appBodySmall)
                                        .foregroundStyle(Theme.text)
                                    Image(systemName: "calendar")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        FieldRow(label: L10n.Report.end) {
                            Button {
                                showEndDatePicker = true
                            } label: {
                                HStack(spacing: 5) {
                                    Text(fullDateText(endDate))
                                        .font(.appBodySmall)
                                        .foregroundStyle(Theme.text)
                                    Image(systemName: "calendar")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    FieldRow(label: L10n.Report.theme) {
                        AppSegmented(options: [true, false], selection: $darkTheme, title: { $0 ? L10n.Report.dark : L10n.Report.light }, compact: true, fitContent: true)
                            .fixedSize()
                    }
                    FieldRow(label: L10n.Report.exportPNGToo) {
                        Toggle("", isOn: $exportPNG).labelsHidden()
                    }

                    Button {
                        generate()
                    } label: {
                        Label(L10n.Report.generateReport, systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(GoldButtonStyle())
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                    Text(L10n.Report.reportShareHint)
                        .font(.appCaption)
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                SectionHeading(title: L10n.Report.generatedCount(String(describing: reports.count)), trailing: L10n.Report.all)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                LazyVStack(spacing: 8) {
                    ForEach(reports) { report in
                        Button {
                            openReport(report)
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.gold)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.goldSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(report.title)
                                        .font(.appBodySmall)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text("\(report.count) \(report.mediaType.noun) · \(report.hasPNG ? "HTML + PNG" : "HTML") · \(DateFormatter.reportDate.string(from: report.generatedAt))")
                                        .font(.appCaption)
                                        .foregroundStyle(Theme.text3)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.text3)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .toast(message: $toast)
        .sheet(isPresented: $showPeriodPicker) {
            PeriodWheelSheet(scope: scope, years: years, year: $year, month: $month)
                .presentationDetents([.height(scope == .month ? 300 : 250)])
        }
        .sheet(isPresented: $showStartDatePicker) {
            DatePickerSheet(title: L10n.Report.startDate, date: $startDate)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showEndDatePicker) {
            DatePickerSheet(title: L10n.Report.endDate, date: $endDate)
                .presentationDetents([.medium])
        }
        .onChange(of: media) { _, _ in
            if reports.isEmpty { scope = .month }
        }
    }

    private func fullDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: date)
    }

    private func makeQuery() -> ReportQuery {
        ReportQuery(
            mediaType: media,
            scope: scope,
            year: year,
            month: month,
            startDate: startDate,
            endDate: endDate,
            darkTheme: darkTheme
        )
    }

    private func generate() {
        let query = makeQuery()
        let records = store.reportRecords(query: query)
        let htmlURL = ReportExportService.writeHTML(query: query, records: records)
        let report = GeneratedReport(
            title: query.title,
            mediaType: media,
            scope: scope,
            generatedAt: Date(),
            count: records.count,
            fileName: htmlURL?.lastPathComponent ?? ReportExportService.fileName(for: query),
            hasPNG: exportPNG
        )
        store.addReport(report)
        router.push(.reportPreview(query))
    }

    private func openReport(_ report: GeneratedReport) {
        let calendar = Calendar.current
        let generatedYear = calendar.component(.year, from: report.generatedAt)
        let generatedMonth = calendar.component(.month, from: report.generatedAt)
        router.push(.reportPreview(ReportQuery(
            mediaType: report.mediaType,
            scope: report.scope,
            year: generatedYear,
            month: generatedMonth,
            startDate: Date().addingTimeInterval(-86400 * 30),
            endDate: Date(),
            darkTheme: true
        )))
    }
}

private struct PeriodWheelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let scope: ReportScope
    let years: [Int]
    @Binding var year: Int
    @Binding var month: Int

    @State private var draftYear: Int
    @State private var draftMonth: Int

    init(scope: ReportScope, years: [Int], year: Binding<Int>, month: Binding<Int>) {
        self.scope = scope
        self.years = years
        self._year = year
        self._month = month
        self._draftYear = State(initialValue: year.wrappedValue)
        self._draftMonth = State(initialValue: month.wrappedValue)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: scope == .month ? L10n.Report.chooseMonth : L10n.Report.chooseYear,
                    leftTitle: L10n.Common.cancel,
                    rightTitle: L10n.Common.done,
                    onLeft: { dismiss() },
                    onRight: {
                        year = draftYear
                        if scope == .month { month = draftMonth }
                        dismiss()
                    }
                )
            }
        } content: {
            HStack(spacing: 0) {
                Picker(L10n.Report.year, selection: $draftYear) {
                    ForEach(years, id: \.self) { value in
                        Text(verbatim: L10n.Report.yearValue(String(describing: value))).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                if scope == .month {
                    Picker(L10n.Report.month, selection: $draftMonth) {
                        ForEach(1...12, id: \.self) { value in
                            Text(verbatim: L10n.Report.monthLabel(String(describing: value))).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
