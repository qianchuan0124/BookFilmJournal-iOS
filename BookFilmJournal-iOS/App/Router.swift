import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case records
    case doulist
    case plan
    case report
    case settings

    var id: String { rawValue }
    var label: String {
        switch self {
        case .records: L10n.Tab.records
        case .doulist: L10n.Tab.doulist
        case .plan: L10n.Tab.plan
        case .report: L10n.Tab.report
        case .settings: L10n.Tab.settings
        }
    }
    var icon: String {
        switch self {
        case .records: "film"
        case .doulist: "list.bullet.rectangle"
        case .plan: "folder"
        case .report: "doc.text"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum AppRoute: Hashable {
    case doulistDetail(UUID)
    case planDetail(UUID)
    case explore
    case cloudSync
    case wordCount
    case dataTransfer
    case recycleBin
    case reportPreview(ReportQuery)
}

@Observable
final class Router {
    var tab: AppTab = .records
    var path: [AppRoute] = []
    var toastMessage: String?

    func switchTab(_ tab: AppTab) {
        if self.tab == tab {
            if !path.isEmpty { path.removeAll() }
            return
        }
        self.tab = tab
        path.removeAll()
    }

    func showToast(_ message: String) {
        toastMessage = message
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}
