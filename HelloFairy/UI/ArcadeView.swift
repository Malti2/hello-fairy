import SwiftUI
import UIKit

/// startseite: apps mit pfeil links/rechts (oder wischen) waehlen, die auswahl leuchtet auf dem vorhang
struct ArcadeView: View {
    @Environment(AppModel.self) private var model
    @Environment(FairyLink.self) private var link

    private var items: [AppEntry] { CurtainMenu.items }
    private var item: AppEntry { items[model.menuIndex] }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 20) {
                HStack {
                    Text("Apps").font(.largeTitle.bold())
                    Spacer()
                    ConnectionPill()
                }
                .padding(.top, 8)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    arrow("chevron.left", -1)
                    CurtainView(frame: CurtainMenu.frame(index: model.menuIndex))
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 30))
                        .onTapGesture { start() }
                    arrow("chevron.right", 1)
                }

                VStack(spacing: 6) {
                    Label(item.title, systemImage: item.symbol)
                        .font(.largeTitle.bold())
                        .contentTransition(.opacity)
                    Text(item.subtitle).font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(items.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == model.menuIndex ? Color.white : Color.white.opacity(0.28))
                                .frame(width: i == model.menuIndex ? 22 : 8, height: 8)
                        }
                    }
                    .padding(.top, 8)
                }
                .animation(.snappy, value: model.menuIndex)

                Spacer(minLength: 0)

                Button { start() } label: {
                    Label("Starten", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.launching)

                if !link.isReady {
                    Text("Vorhang nicht verbunden: die Apps laufen nur als Vorschau")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else if let notice = model.notice {
                    Text(notice).font(.footnote).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                if abs(v.translation.width) > abs(v.translation.height) { step(v.translation.width < 0 ? 1 : -1) }
            }
        )
    }

    private func arrow(_ symbol: String, _ d: Int) -> some View {
        Button { step(d) } label: {
            Image(systemName: symbol).font(.title2.weight(.bold)).frame(width: 40, height: 72)
        }
        .buttonStyle(.glass)
    }

    private func step(_ d: Int) {
        let n = items.count
        model.menuIndex = (model.menuIndex + d + n) % n
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.pushMenu()
    }

    private func start() {
        Task { await model.launch(item.id) }
    }
}
