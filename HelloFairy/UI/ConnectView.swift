import SwiftUI

struct ConnectView: View {
    @Environment(FairyLink.self) private var link
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Screen(title: "Verbindung") {
            GlassCard(title: "Status") {
                row("Bluetooth", link.btState)
                row("Verbindung", phaseText)
                if link.isReady {
                    row("Geraet", link.deviceName)
                    if let i = link.info {
                        row("Modell", "\(i.model) · fw \(i.firmware)")
                        row("LEDs", "\(i.ledCount) (\(i.columns)x\(i.rows))")
                    }
                    if link.reconnects > 0 { row("Neu verbunden", "\(link.reconnects)x") }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                if let e = link.lastError, error == nil { Text(e).font(.footnote).foregroundStyle(.orange) }
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button { run { try await link.connect() } } label: {
                        Label("Verbinden", systemImage: "link").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(busy)

                    Button { link.disconnect() } label: {
                        Label("Trennen", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }

            GlassCard(title: "Geraete in der Naehe") {
                Button { run { try await link.scan() } } label: {
                    Label("Suchen", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(busy)

                if link.found.isEmpty {
                    Text("nichts gefunden. Lichter einschalten, nah ran, die offizielle Hello-Fairy-App schliessen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(link.found.sorted { $0.rssi > $1.rssi }) { dev in
                    Button {
                        run { try await link.connect(to: dev.id) }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(dev.name)
                            Spacer()
                            Text("\(dev.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !link.log.isEmpty {
                GlassCard(title: "Protokoll") {
                    Text(link.log.suffix(12).joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var phaseText: String {
        switch link.phase {
        case .idle: return "getrennt"
        case .scanning: return "suche..."
        case .connecting: return "verbinde..."
        case .discovering: return "richte ein..."
        case .ready: return "verbunden"
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v)
        }
        .font(.subheadline)
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            do { try await op() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
