import SwiftUI

@main
struct PlanificadorApp: App {
    @StateObject private var store = PlannerStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .frame(minWidth: 1040, minHeight: 690)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
    }
}
