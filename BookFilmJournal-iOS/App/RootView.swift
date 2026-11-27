import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    tabContent(tab)
                        .opacity(router.tab == tab ? 1 : 0)
                        .allowsHitTesting(router.tab == tab)
                        .accessibilityHidden(router.tab != tab)
                        .zIndex(router.tab == tab ? 1 : 0)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.16), value: router.tab)
            .appScreen()
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
                    .appScreen()
                    .simultaneousGesture(edgeBackGesture)
            }
        }
        .tint(Theme.gold)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if router.path.isEmpty {
                AppTabBar(selection: Binding(
                    get: { router.tab },
                    set: { router.switchTab($0) }
                ))
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toast(message: Binding(
            get: { router.toastMessage },
            set: { router.toastMessage = $0 }
        ))
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .records:
            RecordsView()
        case .doulist:
            DoulistView()
        case .plan:
            PlanView()
        case .report:
            ReportView()
        case .settings:
            SettingsView()
        }
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .global)
            .onEnded { value in
                guard !router.path.isEmpty,
                      value.startLocation.x <= 24,
                      value.translation.width > 72,
                      abs(value.translation.height) < value.translation.width else { return }
                router.pop()
            }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .doulistDetail(let id):
            DoulistDetailView(doulistID: id)
        case .planDetail(let id):
            PlanDetailView(folderID: id)
        case .explore:
            ExploreView()
        case .cloudSync:
            CloudSyncView()
        case .wordCount:
            WordCountView()
        case .dataTransfer:
            DataTransferView()
        case .recycleBin:
            RecycleBinView()
        case .reportPreview(let query):
            ReportPreviewView(query: query)
        }
    }
}
