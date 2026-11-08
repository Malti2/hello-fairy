import SwiftUI
import UIKit

struct LightsView: View {
    @Environment(FairyLink.self) private var link

    @State private var color = Color.purple
    @State private var brightness = 60.0
    @State private var presetBrightness = 50.0
    @State private var statusText = ""
    @State private var error: String?
    @State private var busy = false
    @State private var colorTask: Task<Void, Never>?

    private struct Swatch: Identifiable {
        let name: String
        let h: Int
        let s: Int
        var id: String { name }
        var color: Color { Color(hue: Double(h) / 360, saturation: Double(s) / 100, brightness: 1) }
    }

    private let swatches: [Swatch] = [
        .init(name: "rot", h: 0, s: 100), .init(name: "orange", h: 30, s: 100), .init(name: "gelb", h: 55, s: 100),
        .init(name: "gruen", h: 120, s: 100), .init(name: "cyan", h: 180, s: 100), .init(name: "blau", h: 240, s: 100),
        .init(name: "lila", h: 275, s: 100), .init(name: "magenta", h: 300, s: 100), .init(name: "pink", h: 330, s: 100),
        .init(name: "weiss", h: 0, s: 0), .init(name: "warm", h: 35, s: 40),
    ]

    private let presetColumns = [GridItem(.adaptive(minimum: 140), spacing: 10)]

    var body: some View {
        Screen(title: "Licht") {
            GlassCard {
                HStack(spacing: 12) {
                    Button { perform { try await link.setPower(true) } } label: {
                        Label("An", systemImage: "power").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button { perform { try await link.setPower(false) } } label: {
                        Label("Aus", systemImage: "moon.zzz.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }

            GlassCard(title: "Farbe") {
                ColorPicker("Eigene Farbe", selection: $color, supportsOpacity: false)
                    .onChange(of: color) { _, new in sendColor(new) }
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(swatches) { sw in
                                Button {
                                    perform { try await link.setColor(h: sw.h, s: sw.s, v: Int(brightness)) }
                                } label: {
                                    Circle().fill(sw.color).frame(width: 34, height: 34)
                                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: Circle())
                                .accessibilityLabel(sw.name)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            GlassCard(title: "Helligkeit \(Int(brightness)) %") {
                Slider(value: $brightness, in: 0...100, step: 1) { editing in
                    if !editing { perform { try await link.setBrightness(Int(brightness)) } }
                }
            }

            GlassCard(title: "Effekte") {
                Text("Helligkeit \(Int(presetBrightness)) %").font(.footnote).foregroundStyle(.secondary)
                Slider(value: $presetBrightness, in: 0...100, step: 1)
                GlassEffectContainer(spacing: 10) {
                    LazyVGrid(columns: presetColumns, spacing: 10) {
                        ForEach(Proto.presets, id: \.id) { p in
                            Button {
                                perform { try await link.setPreset(p.id, brightness: Int(presetBrightness)) }
                            } label: {
                                Text(p.name).font(.footnote.weight(.semibold)).lineLimit(1)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: Capsule())
                        }
                    }
                }
            }

            GlassCard(title: "Status") {
                HStack {
                    Button("Status lesen") {
                        perform {
                            if let st = try await link.getStatus() { statusText = describe(st) } else { statusText = "keine antwort" }
                        }
                    }
                    .buttonStyle(.glass)
                    Button("Geraeteinfo") {
                        perform {
                            if let i = try await link.getInfo() {
                                statusText = "\(i.model)  fw \(i.firmware)  \(i.ledCount) LEDs (\(i.columns)x\(i.rows))"
                            } else { statusText = "keine antwort" }
                        }
                    }
                    .buttonStyle(.glass)
                }
                if !statusText.isEmpty { Text(statusText).font(.system(.footnote, design: .monospaced)) }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
        }
    }

    private func describe(_ st: DeviceStatus) -> String {
        let p = st.power ? "an" : "aus"
        switch st.mode {
        case 1: return "\(p)  farbe  hue \(st.hue)  sat \(Int(st.saturation)) %  hell \(Int(st.brightness)) %"
        case 2: return "\(p)  effekt #\(st.preset)  hell \(Int(st.brightness)) %"
        default: return "\(p)  modus \(st.mode)"
        }
    }

    private func sendColor(_ c: Color) {
        colorTask?.cancel()
        colorTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)         // nicht bei jedem pixel des pickers senden
            if Task.isCancelled { return }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            let hsv = Imaging.hsv(r: Int(r * 255), g: Int(g * 255), b: Int(b * 255))
            await run { try await link.setColor(h: hsv.h, s: hsv.s, v: Int(brightness)) }
        }
    }

    private func perform(_ op: @escaping () async throws -> Void) {
        Task { await run(op) }
    }

    private func run(_ op: () async throws -> Void) async {
        error = nil
        do { try await op() } catch { self.error = error.localizedDescription }
    }
}
