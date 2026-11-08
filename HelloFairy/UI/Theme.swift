import SwiftUI

/// farben der vorhang-pixel (hue-byte 0...180 = 0...360 grad, 255 weiss, 254 aus)
enum CurtainPalette {
    static let offColor = Color(white: 0.11)
    static let colors: [Color] = (0...255).map { i in
        let (r, g, b) = Proto.hueByteToRGB(UInt8(i))
        if i == Int(Px.off) { return offColor }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
    static func color(_ c: UInt8) -> Color { colors[Int(c)] }
}

/// hintergrund: dunkler verlauf mit weichen farbflecken, damit das glas etwas zum brechen hat
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.14), Color(red: 0.10, green: 0.05, blue: 0.20)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.purple.opacity(0.55)).frame(width: 280).blur(radius: 90).offset(x: -140, y: -260)
            Circle().fill(Color.cyan.opacity(0.40)).frame(width: 260).blur(radius: 90).offset(x: 150, y: -60)
            Circle().fill(Color.pink.opacity(0.40)).frame(width: 300).blur(radius: 100).offset(x: -90, y: 300)
        }
        .ignoresSafeArea()
    }
}

/// die 20x20 pixel als runde leds
struct CurtainView: View {
    let frame: Frame
    var glow = true

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let cell = side / CGFloat(W)
            let ox = (size.width - side) / 2, oy = (size.height - side) / 2
            for y in 0..<H {
                for x in 0..<W {
                    let c = frame[y * W + x]
                    let rect = CGRect(x: ox + CGFloat(x) * cell + cell * 0.12, y: oy + CGFloat(y) * cell + cell * 0.12,
                                      width: cell * 0.76, height: cell * 0.76)
                    let color = CurtainPalette.color(c)
                    if glow && c != Px.off {
                        ctx.fill(Path(ellipseIn: rect.insetBy(dx: -cell * 0.18, dy: -cell * 0.18)), with: .color(color.opacity(0.25)))
                    }
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup()
    }
}

/// glaskarte fuer inhalte
struct GlassCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline).foregroundStyle(.secondary) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

/// kleine status-pille: verbunden / nicht verbunden
struct ConnectionPill: View {
    @Environment(FairyLink.self) private var link
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.tab = 3 } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(text).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var color: Color {
        switch link.phase {
        case .ready: return .green
        case .idle: return .gray
        default: return .orange
        }
    }

    private var text: String {
        switch link.phase {
        case .ready: return link.deviceName.isEmpty ? "verbunden" : link.deviceName
        case .idle: return "getrennt"
        case .scanning: return "suche..."
        case .connecting, .discovering: return "verbinde..."
        }
    }
}

/// seite mit titel, hintergrund und verbindungs-pille
struct Screen<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) { content }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .background { Backdrop() }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ConnectionPill() }
            }
        }
    }
}
