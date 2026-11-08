import SwiftUI

/// erster start: licht auswaehlen
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(FairyLink.self) private var link
    @State private var error: String?
    @State private var connecting: UUID?

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 20) {
                Spacer(minLength: 20)
                Image(systemName: "sparkles")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(26)
                    .glassEffect(.regular, in: Circle())
                VStack(spacing: 6) {
                    Text("Hello Fairy").font(.largeTitle.bold())
                    Text("Waehle deine Lichter").font(.title3).foregroundStyle(.secondary)
                }

                GlassCard {
                    if link.found.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(emptyText).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(link.found.sorted { $0.rssi > $1.rssi }) { dev in
                        Button { pick(dev) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                VStack(alignment: .leading) {
                                    Text(dev.name).font(.headline)
                                    Text("\(dev.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if connecting == dev.id { ProgressView() } else { Image(systemName: "chevron.right") }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                }
                .padding(.horizontal, 16)

                Spacer()
                Button("Ohne Licht ausprobieren") { model.onboarded = true }
                    .buttonStyle(.glass)
                    .padding(.bottom, 24)
            }
        }
        .task { await scanLoop() }
    }

    private var emptyText: String {
        switch link.btState {
        case "aus": return "Bluetooth ist aus"
        case "nicht erlaubt": return "Bluetooth-Zugriff fehlt (Einstellungen > Hello Fairy)"
        default: return "Suche Lichter in der Naehe ... einschalten und die offizielle App schliessen"
        }
    }

    private func scanLoop() async {
        while !Task.isCancelled {
            do { try await link.scan(seconds: 4, keepFound: true) } catch { self.error = error.localizedDescription }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    private func pick(_ dev: FoundDevice) {
        guard connecting == nil else { return }
        connecting = dev.id
        error = nil
        Task {
            do { try await link.connect(to: dev.id) } catch { self.error = error.localizedDescription }
            connecting = nil
        }
    }
}
