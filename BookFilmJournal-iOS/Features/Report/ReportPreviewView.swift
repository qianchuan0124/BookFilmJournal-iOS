import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ReportPreviewView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    let query: ReportQuery
    @State private var toast: String?
    @State private var isExporting = false
    @State private var image: UIImage?
    @State private var imageURL: URL?

    private var records: [MediaRecord] { store.reportRecords(query: query) }
    private var reportBackground: Color { query.darkTheme ? Theme.reportBG : Theme.reportLightBG }
    private var reportTextColor: Color { query.darkTheme ? Theme.reportText : Theme.reportLightText }
    private var reportGoldColor: Color { query.darkTheme ? Theme.reportGold : Theme.reportLightGold }
    private var reportMutedColor: Color { query.darkTheme ? Theme.reportMuted : Theme.reportLightMuted }

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(
                title: "",
                backLabel: L10n.Report.reportLabel,
                trailing: AnyView(
                    Button {
                        prepareShare()
                    } label: {
                        if isExporting {
                            ProgressView().tint(reportGoldColor)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(reportGoldColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting || imageURL == nil)
                ),
                textColor: reportTextColor,
                accentColor: reportGoldColor
            )
            .background(reportBackground)

            if let image {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(reportBackground)
                }
                .scrollIndicators(.hidden)
                .background(reportBackground)
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(reportGoldColor)
                    Text(L10n.Report.generatingReport)
                        .font(.appCaption)
                        .foregroundStyle(reportMutedColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(reportBackground.ignoresSafeArea())
        .toast(message: $toast)
        .preferredColorScheme(query.darkTheme ? .dark : .light)
        .task(id: query) {
            await Task.yield()
            if let url = NativeReportRenderer.existingURL(for: query),
               let existing = UIImage(contentsOfFile: url.path) {
                image = existing
                imageURL = url
                return
            }
            guard let rendered = await NativeReportRenderer.render(query: query, records: records) else {
                toast = L10n.Report.reportGenerateFailed
                return
            }
            image = rendered
            guard let url = NativeReportRenderer.savePNG(rendered, query: query) else {
                toast = "文件太大，无法导出"
                return
            }
            imageURL = url
        }
    }

    private func prepareShare() {
        guard !isExporting, let imageURL else { return }
        #if canImport(UIKit)
        guard let presenter = topViewController() else {
            toast = "无法打开分享面板"
            return
        }
        isExporting = true
        let controller = UIActivityViewController(activityItems: [imageURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async {
                isExporting = false
                if completed {
                    router.showToast(L10n.Report.exportSuccessToast)
                }
            }
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
        #else
        toast = L10n.Report.previewUnsupported
        #endif
    }

    #if canImport(UIKit)
    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let navigation = top as? UINavigationController {
            return navigation.visibleViewController ?? navigation
        }
        if let tab = top as? UITabBarController {
            return tab.selectedViewController ?? tab
        }
        return top
    }
    #endif
}
