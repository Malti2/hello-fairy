import SwiftUI
import PhotosUI

struct ImageView: View {
    @Environment(FairyLink.self) private var link
    @Environment(AppModel.self) private var model

    // bild
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var fit: FitMode = .contain
    @State private var dark = 0.18
    @State private var white = 0.18
    @State private var boost = 1.0
    @State private var preview: Frame = blankFrame()

    // text
    @State private var text = ""
    @State private var textColor: UInt8 = 0
    @State private var textSize = 11.0
    @State private var textPages: [Frame] = []

    // bewegung
    @State private var movement = "loop-left"
    @State private var speed = 30.0
    @State private var moveBrightness = 100.0

    // zwei bilder
    @State private var itemA: PhotosPickerItem?
    @State private var itemB: PhotosPickerItem?
    @State private var imageA: UIImage?
    @State private var imageB: UIImage?
    @State private var animMode = "blink"

    // senden
    @State private var progress: String?
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        Screen(title: "Bild") {
            GlassCard(title: "Foto") {
                CurtainView(frame: preview).frame(maxWidth: 260).frame(maxWidth: .infinity)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(image == nil ? "Foto waehlen" : "anderes Foto", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Picker("Anpassung", selection: $fit) {
                    ForEach(FitMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                slider("Dunkel-Schwelle", value: $dark, range: 0...0.5, format: "%.2f")
                slider("Weiss-Schwelle", value: $white, range: 0...0.5, format: "%.2f")
                slider("Helligkeit", value: $boost, range: 0.5...2.0, format: "%.1fx")

                Button {
                    send { try await link.sendImage(preview, progress: report) }
                } label: {
                    Label("Aufs Licht senden", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(sending || image == nil)

                Text("jedes pixel kann nur Farbton, weiss oder aus sein. ein upload dauert 3-4 s.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GlassCard(title: "Text") {
                TextField("Text", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                if let first = textPages.first {
                    CurtainView(frame: first, glow: false).frame(maxWidth: 160).frame(maxWidth: .infinity)
                    if textPages.count > 1 {
                        Text("\(textPages.count) seiten, je 2 s").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Farbe", selection: $textColor) {
                    ForEach(Imaging.colorNames, id: \.byte) { Text($0.name).tag($0.byte) }
                }
                .pickerStyle(.menu)
                slider("Schriftgroesse", value: $textSize, range: 8...16, format: "%.0f pt")
                Button {
                    let pages = textPages
                    send {
                        for (i, page) in pages.enumerated() {
                            try await link.sendImage(page, progress: report)
                            if i < pages.count - 1 { try await Task.sleep(nanoseconds: 2_000_000_000) }
                        }
                    }
                } label: {
                    Label("Text senden", systemImage: "textformat").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(sending || textPages.isEmpty)
            }

            GlassCard(title: "Bewegung des Bildes") {
                Picker("Bewegung", selection: $movement) {
                    ForEach(Proto.movements.filter { $0.name != "blink" && $0.name != "breathe" }, id: \.name) {
                        Text($0.name).tag($0.name)
                    }
                }
                .pickerStyle(.menu)
                slider("Tempo", value: $speed, range: 0...100, format: "%.0f")
                slider("Helligkeit", value: $moveBrightness, range: 0...100, format: "%.0f %%")
                HStack {
                    Button {
                        send { try await link.playback(kind: "picture", movement: movement, speed: Int(speed),
                                                       brightness: Int(moveBrightness)) }
                    } label: { Label("Anwenden", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .disabled(sending)

                    Button {
                        send { try await link.sendImage(blankFrame(), progress: report) }
                    } label: { Label("Leeren", systemImage: "trash").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .disabled(sending)
                }
            }

            GlassCard(title: "Zwei Bilder (experimentell)") {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $itemA, matching: .images) {
                        thumb(imageA, label: "Bild 1")
                    }
                    PhotosPicker(selection: $itemB, matching: .images) {
                        thumb(imageB, label: "Bild 2")
                    }
                }
                Picker("Modus", selection: $animMode) {
                    Text("blinken").tag("blink")
                    Text("atmen").tag("breathe")
                }
                .pickerStyle(.segmented)
                Button {
                    guard let a = imageA, let b = imageB,
                          let fa = ImageLoader.frame(a, fit: fit, dark: dark, white: white, boost: boost),
                          let fb = ImageLoader.frame(b, fit: fit, dark: dark, white: white, boost: boost) else { return }
                    send {
                        try await link.sendAnimation([fa, fb], progress: report)
                        try await link.playback(kind: "animation", movement: animMode, speed: Int(speed),
                                                brightness: Int(moveBrightness))
                    }
                } label: { Label("Animation senden", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
                .disabled(sending || imageA == nil || imageB == nil)
            }

            if let progress { Text(progress).font(.footnote).foregroundStyle(.secondary) }
            if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }
        .onChange(of: pickerItem) { _, item in load(item) { image = $0; refreshPreview() } }
        .onChange(of: itemA) { _, item in load(item) { imageA = $0 } }
        .onChange(of: itemB) { _, item in load(item) { imageB = $0 } }
        .onChange(of: fit) { _, _ in refreshPreview() }
        .onChange(of: dark) { _, _ in refreshPreview() }
        .onChange(of: white) { _, _ in refreshPreview() }
        .onChange(of: boost) { _, _ in refreshPreview() }
        .onChange(of: text) { _, _ in refreshText() }
        .onChange(of: textColor) { _, _ in refreshText() }
        .onChange(of: textSize) { _, _ in refreshText() }
    }

    // MARK: bausteine

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.subheadline).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func thumb(_ img: UIImage?, label: String) -> some View {
        Group {
            if let img {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                VStack { Image(systemName: "plus"); Text(label).font(.caption) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    // MARK: logik

    private func load(_ item: PhotosPickerItem?, _ done: @escaping (UIImage) -> Void) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                done(img)
            } else {
                error = "foto konnte nicht geladen werden"
            }
        }
    }

    private func refreshPreview() {
        guard let image else { return }
        if let f = ImageLoader.frame(image, fit: fit, dark: dark, white: white, boost: boost) { preview = f }
    }

    private func refreshText() {
        textPages = ImageLoader.textPages(text, color: textColor, fontSize: CGFloat(textSize))
    }

    private func report(_ i: Int, _ n: Int, _ label: String) {
        progress = "\(i)/\(n)  \(label)"
    }

    private func send(_ op: @escaping () async throws -> Void) {
        guard !sending else { return }
        sending = true
        error = nil
        progress = nil
        Task {
            do {
                try await op()
                progress = "fertig"
            } catch {
                self.error = error.localizedDescription
                progress = nil
            }
            sending = false
        }
    }
}
