import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(FairyLink.self) private var link
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                TabView(selection: $model.tab) {
                    Tab("Apps", systemImage: "gamecontroller.fill", value: 0) { ArcadeView() }
                    Tab("Licht", systemImage: "lightbulb.max.fill", value: 1) { LightsView() }
                    Tab("Bild", systemImage: "photo.fill", value: 2) { ImageView() }
                    Tab("Verbindung", systemImage: "dot.radiowaves.left.and.right", value: 3) { ConnectView() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.tab) { old, new in model.tabChanged(from: old, to: new) }
        .onChange(of: link.phase) { _, phase in if phase == .ready { model.linkBecameReady() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.wentToBackground() }
            if phase == .active { model.becameActive() }
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.activeApp != nil },
            set: { shown in if !shown { Task { await model.close() } } }
        )) {
            PlayView(appID: model.activeApp ?? "")
        }
    }
}
