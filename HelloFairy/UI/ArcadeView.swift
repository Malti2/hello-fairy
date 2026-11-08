import SwiftUI

struct ArcadeView: View {
    @Environment(AppModel.self) private var model
    @Environment(FairyLink.self) private var link

    @AppStorage("hf.city") private var city = ""
    @AppStorage("hf.pong.difficulty") private var difficulty = "normal"
    @AppStorage("hf.pong.points") private var points = 5
    @AppStorage("hf.minInterval") private var minInterval = 0.06
    @AppStorage("hf.demoCamera") private var demoCamera = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Screen(title: "Apps") {
            GlassCard {
                CurtainView(frame: CurtainMenu.frame(index: model.menuIndex))
                    .frame(maxWidth: 300)
                    .frame(maxWidth: .infinity)
                Text(link.isReady ? "laeuft auf dem vorhang" : "nur vorschau, vorhang nicht verbunden")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(CurtainMenu.items.enumerated()), id: \.element.id) { index, item in
                        tile(item, index: index)
                    }
                }
            }

            Button {
                Task { await model.launch(CurtainMenu.items[model.menuIndex].id) }
            } label: {
                Label("\(CurtainMenu.items[model.menuIndex].title) starten", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.launching)

            if link.isReady {
                Button {
                    Task { await model.switchOffWithEffect() }
                } label: {
                    Label("Vorhang ausschalten (TV-Effekt)", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }

            if let notice = model.notice {
                Text(notice).font(.footnote).foregroundStyle(.orange)
            }

            GlassCard(title: "Einstellungen") {
                HStack {
                    Text("Pong")
                    Spacer()
                    Picker("Staerke", selection: $difficulty) {
                        Text("leicht").tag("easy")
                        Text("normal").tag("normal")
                        Text("hart").tag("hard")
                    }
                    .pickerStyle(.menu)
                }
                Stepper("Pong bis \(points) Punkte", value: $points, in: 1...15)
                HStack {
                    Text("Wetter")
                    TextField("Stadt (z.B. Berlin)", text: $city)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                }
                VStack(alignment: .leading) {
                    Text("Sendetakt \(Int(minInterval * 1000)) ms").font(.subheadline)
                    Slider(value: $minInterval, in: 0.03...0.2, step: 0.01)
                    Text("hakelt das bild, den takt erhoehen").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Demo-Kamera (ohne echte Kamera)", isOn: $demoCamera)
            }
        }
    }

    private func tile(_ item: AppEntry, index: Int) -> some View {
        let selected = model.menuIndex == index
        return Button {
            model.menuIndex = index
            model.pushMenu()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: item.symbol).font(.system(size: 30, weight: .semibold))
                Text(item.title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.purple.opacity(0.55)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 24))
    }
}
