import SwiftUI
#if canImport(UIKit)
import WebKit
#endif

struct ReportPreviewView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let query: ReportQuery
    @State private var toast: String?
    @State private var isExporting = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var html = ""

    private var records: [MediaRecord] { store.reportRecords(query: query) }

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: "", backLabel: L10n.Report.reportLabel, trailing: AnyView(
                Button {
                    prepareShare()
                } label: {
                    if isExporting {
                        ProgressView().tint(Theme.reportGold)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.reportGold)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
            ))
            .background(Theme.reportBG)

            if html.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().tint(Theme.reportGold)
                    Text(L10n.Report.generatingReport)
                        .font(.appCaption)
                        .foregroundStyle(Theme.reportMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if canImport(UIKit)
                ReportWebView(html: html)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #else
                Text(L10n.Report.previewUnsupported)
                    .font(.appBody)
                    .foregroundStyle(Theme.reportText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
        }
        .background(Theme.reportBG.ignoresSafeArea())
        .toast(message: $toast)
        .sheet(isPresented: $showShare) {
            ActivityShareView(items: shareItems)
        }
        .task(id: query) {
            html = ReportExportService.makeHTML(query: query, records: store.reportRecords(query: query))
        }
    }

    private func prepareShare() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            let records = store.reportRecords(query: query)
            guard let htmlURL = ReportExportService.writeHTML(query: query, records: records) else {
                isExporting = false
                toast = L10n.Report.reportGenerateFailed
                return
            }
            var items: [Any] = [htmlURL]
            if let pngs = try? await ReportExportService.renderPNGs(from: htmlURL, baseName: htmlURL.lastPathComponent) {
                items.append(contentsOf: pngs)
            }
            shareItems = items
            isExporting = false
            showShare = true
        }
    }
}

#if canImport(UIKit)
private struct ReportWebView: UIViewRepresentable {
    let html: String

    final class Coordinator {
        var lastHTML: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#endif
