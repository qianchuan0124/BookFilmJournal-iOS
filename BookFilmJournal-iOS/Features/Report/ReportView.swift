import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ReportView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @State private var media: MediaType = .movie
    @State private var scope: ReportScope = .month
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var darkTheme = true
    @State private var customStartYear = Calendar.current.component(.year, from: Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date())
    @State private var customEndYear = Calendar.current.component(.year, from: Date())
    @State private var showPeriodPicker = false
    @State private var showStartYearPicker = false
    @State private var showEndYearPicker = false
    @State private var showBatchGenerate = false
    @State private var toast: String?
    @State private var isGenerating = false

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
        PageScaffoldNoScroll {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Report.reportCenter)
                            .font(.appDisplay)
                            .foregroundStyle(Theme.text)
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
            List {
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
                            Button { showStartYearPicker = true } label: { yearLabel(customStartYear) }
                                .buttonStyle(.plain)
                        }
                        FieldRow(label: L10n.Report.end) {
                            Button { showEndYearPicker = true } label: { yearLabel(customEndYear) }
                                .buttonStyle(.plain)
                        }
                    }

                    FieldRow(label: L10n.Report.theme) {
                        AppSegmented(options: [true, false], selection: $darkTheme, title: { $0 ? L10n.Report.dark : L10n.Report.light }, compact: true, fitContent: true)
                            .fixedSize()
                    }
                    Button { generate() } label: {
                        HStack(spacing: 8) {
                            if isGenerating {
                                ProgressView().tint(Theme.bg)
                            } else {
                                Image(systemName: "doc.text.magnifyingglass")
                            }
                            Text(isGenerating ? L10n.Report.generatingReport : L10n.Report.generateReport)
                        }
                        .animation(nil, value: isGenerating)
                    }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(isGenerating)
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
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                SectionHeading(title: L10n.Report.generatedCount(String(describing: reports.count)), trailing: L10n.Report.all)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ForEach(reports) { report in
                    Button { openReport(report) } label: {
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
                                Text("\(report.count) \(report.mediaType.noun) · \(DateFormatter.reportDate.string(from: report.generatedAt))")
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.text3)
                            }
                            Spacer(minLength: 0)
                            if report.id == reports.first?.id {
                                TagView(text: "最新", style: .gold)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteReport(report)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .tint(Color(hex: 0xE5484D))
                    }
                }

                Button { showBatchGenerate = true } label: {
                    Label("批量生成 \(year) 年全部月报", systemImage: "calendar.badge.plus")
                        .font(.appBodySmall)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(Theme.goldDeep)
                        .background(Theme.goldSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.goldBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 82, for: .scrollContent)
        }
        .toast(message: $toast)
        .sheet(isPresented: $showPeriodPicker) {
            PeriodWheelSheet(scope: scope, years: years, year: $year, month: $month)
                .presentationDetents([.height(scope == .month ? 300 : 250)])
        }
        .sheet(isPresented: $showStartYearPicker) {
            PeriodWheelSheet(scope: .year, years: years, year: $customStartYear, month: .constant(1))
                .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showEndYearPicker) {
            PeriodWheelSheet(scope: .year, years: years, year: $customEndYear, month: .constant(1))
                .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showBatchGenerate) {
            BatchReportSheet(media: media, years: years, darkTheme: darkTheme)
                .presentationDetents([.large])
        }
        .onChange(of: media) { _, _ in
            if reports.isEmpty { scope = .month }
        }
    }

    private func yearLabel(_ year: Int) -> some View {
        HStack(spacing: 5) {
            Text(L10n.Report.yearLabel(String(describing: year)))
                .font(.appBodySmall)
                .foregroundStyle(Theme.text)
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gold)
        }
    }

    private func makeQuery() -> ReportQuery {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: customStartYear, month: 1, day: 1)) ?? Date()
        let endStart = calendar.date(from: DateComponents(year: customEndYear + 1, month: 1, day: 1)) ?? Date()
        let end = endStart.addingTimeInterval(-1)
        return ReportQuery(
            mediaType: media,
            scope: scope,
            year: year,
            month: month,
            startDate: min(start, end),
            endDate: max(start, end),
            darkTheme: darkTheme
        )
    }

    private func generate() {
        guard !isGenerating else { return }
        let query = makeQuery()
        let records = store.reportRecords(query: query)
        isGenerating = true

        Task { @MainActor in
            await Task.yield()
            guard let image = await NativeReportRenderer.render(query: query, records: records),
                  let url = NativeReportRenderer.savePNG(image, query: query) else {
                isGenerating = false
                toast = "报告生成失败或文件超过 100MB"
                return
            }

            let report = GeneratedReport(
                title: query.title,
                mediaType: query.mediaType,
                scope: query.scope,
                generatedAt: Date(),
                count: records.count,
                fileName: url.lastPathComponent,
                hasPNG: true,
                year: query.scope == .year || query.scope == .month ? query.year : nil,
                month: query.scope == .month ? query.month : nil,
                startDate: query.scope == .custom ? query.startDate : nil,
                endDate: query.scope == .custom ? query.endDate : nil,
                darkTheme: query.darkTheme
            )
            store.addReport(report)
            isGenerating = false
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            router.showToast(L10n.Report.generatedToast)
            if router.tab == .report && router.path.isEmpty {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    router.push(.reportPreview(query))
                }
            }
        }
    }

    private func deleteReport(_ report: GeneratedReport) {
        store.deleteReport(report.id)
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        router.showToast(L10n.Report.deletedToast)
    }

    private func openReport(_ report: GeneratedReport) {
        router.push(.reportPreview(report.query))
    }
}




private struct BatchReportSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let media: MediaType
    let years: [Int]
    let darkTheme: Bool

    @State private var selectedYear: Int
    @State private var running = false
    @State private var total = 0
    @State private var done = 0
    @State private var currentMonth = 0
    @State private var completed = Set<Int>()

    init(media: MediaType, years: [Int], darkTheme: Bool) {
        self.media = media
        self.years = years
        self.darkTheme = darkTheme
        self._selectedYear = State(initialValue: years.first ?? Calendar.current.component(.year, from: Date()))
    }

    private var monthsWithRecords: [Int] {
        (1...12).filter { monthCount($0) > 0 }
    }

    private var progress: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: "批量生成月报",
                    leftTitle: "关闭",
                    rightTitle: running ? "生成中" : "开始生成",
                    rightDisabled: running || monthsWithRecords.isEmpty,
                    onLeft: { dismiss() },
                    onRight: { generate() }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                AppSegmented(
                    options: years,
                    selection: $selectedYear,
                    title: { "\($0)" },
                    compact: true,
                    fitContent: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        monthCell(month)
                    }
                }

                VStack(spacing: 8) {
                    HStack {
                        Text(running ? "正在生成 \(selectedYear) 年 \(currentMonth) 月报" : "准备生成")
                            .font(.appBodySmall)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(done) / \(max(total, monthsWithRecords.count))")
                            .font(.appCaption)
                            .foregroundStyle(Theme.text3)
                    }
                    ProgressView(value: progress)
                        .tint(Theme.teal)
                }
                .padding(14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))

                Text("批量生成会跳过没有记录的月份；每份完成后写入「已生成报告」，可随时打开或分享。")
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func monthCell(_ month: Int) -> some View {
        let count = monthCount(month)
        let isCurrent = running && currentMonth == month
        let isDone = completed.contains(month)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(month) 月")
                    .font(.appBodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.read)
                }
            }
            Text(isCurrent ? "生成中" : (isDone ? "已生成" : (count == 0 ? "暂无记录" : "\(count) \(media.noun)")))
                .font(.appCaption)
                .foregroundStyle(isCurrent ? Theme.gold : (count == 0 ? Theme.text4 : Theme.text3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(isCurrent ? Theme.goldSoft : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isCurrent ? Theme.goldBorder : Theme.border, lineWidth: 1))
    }

    private func monthCount(_ month: Int) -> Int {
        store.reportRecords(query: ReportQuery(
            mediaType: media,
            scope: .month,
            year: selectedYear,
            month: month,
            startDate: Date().addingTimeInterval(-86400 * 30),
            endDate: Date(),
            darkTheme: darkTheme
        )).count
    }

    private func generate() {
        guard !running else { return }
        let months = monthsWithRecords
        guard !months.isEmpty else { return }
        running = true
        total = months.count
        done = 0
        currentMonth = months.first ?? 0
        completed = []

        Task {
            for month in months {
                currentMonth = month
                let query = ReportQuery(
                    mediaType: media,
                    scope: .month,
                    year: selectedYear,
                    month: month,
                    startDate: Date().addingTimeInterval(-86400 * 30),
                    endDate: Date(),
                    darkTheme: darkTheme
                )
                let records = store.reportRecords(query: query)
                guard let image = await NativeReportRenderer.render(query: query, records: records),
                      let url = NativeReportRenderer.savePNG(image, query: query) else { continue }
                store.addReport(GeneratedReport(
                    title: query.title,
                    mediaType: media,
                    scope: .month,
                    generatedAt: Date(),
                    count: records.count,
                    fileName: url.lastPathComponent,
                    hasPNG: true,
                    year: selectedYear,
                    month: month,
                    darkTheme: darkTheme
                ))
                done += 1
                completed.insert(month)
                await Task.yield()
            }
            running = false
            dismiss()
        }
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
