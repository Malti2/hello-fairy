import SwiftUI

@main
struct HelloFairyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.link)
                .environment(model.runner)
                .task { await model.autoConnect() }
        }
    }
}
