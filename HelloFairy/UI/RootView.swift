import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Apps", systemImage: "gamecontroller.fill", value: 0) { ArcadeView() }
            Tab("Licht", systemImage: "lightbulb.max.fill", value: 1) { LightsView() }
            Tab("Bild", systemImage: "photo.fill", value: 2) { ImageView() }
            Tab("Verbindung", systemImage: "dot.radiowaves.left.and.right", value: 3) { ConnectView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Binding(
            get: { model.activeApp != nil },
            set: { shown in if !shown { Task { await model.close() } } }
        )) {
            PlayView(appID: model.activeApp ?? "")
        }
    }
}
