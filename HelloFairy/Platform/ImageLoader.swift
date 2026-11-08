import Foundation
import UIKit
import CoreGraphics

/// bild / text -> 20x20 frame (CoreGraphics)
enum ImageLoader {
    /// rendert das bild in ein 20x20 raster (rgb), zwischenschritt 80x80 und dann boxfilter fuer saubere mittelwerte
    static func rgbGrid(_ image: UIImage, fit: FitMode) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        let scale = 4
        let size = W * scale
        guard cg.width > 0, cg.height > 0 else { return nil }
        // exif-ausrichtung beruecksichtigen: erst in ein aufrechtes bild zeichnen
        let upright = normalized(image) ?? cg
        let uw = Double(upright.width), uh = Double(upright.height)
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        switch fit {
        case .stretch: break
        case .contain:
            let s = min(Double(size) / uw, Double(size) / uh)
            let rw = uw * s, rh = uh * s
            rect = CGRect(x: (Double(size) - rw) / 2, y: (Double(size) - rh) / 2, width: rw, height: rh)
        case .cover:
            let s = max(Double(size) / uw, Double(size) / uh)
            let rw = uw * s, rh = uh * s
            rect = CGRect(x: (Double(size) - rw) / 2, y: (Double(size) - rh) / 2, width: rw, height: rh)
        }
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.interpolationQuality = .high
        ctx.draw(upright, in: rect)     // speicher-zeile 0 = oberste bildzeile, kein spiegeln noetig
        guard let data = ctx.data else { return nil }
        let p = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: PIXELS * 3)
        for gy in 0..<H {
            for gx in 0..<W {
                var r = 0, g = 0, b = 0
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        let o = ((gy * scale + dy) * size + gx * scale + dx) * 4
                        r += Int(p[o]); g += Int(p[o + 1]); b += Int(p[o + 2])
                    }
                }
                let n = scale * scale
                let i = gy * W + gx
                out[i * 3] = UInt8(r / n); out[i * 3 + 1] = UInt8(g / n); out[i * 3 + 2] = UInt8(b / n)
            }
        }
        return out
    }

    private static func normalized(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let r = UIGraphicsImageRenderer(size: size, format: fmt)
        return r.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }

    static func frame(_ image: UIImage, fit: FitMode, dark: Double, white: Double, boost: Double) -> Frame? {
        guard let rgb = rgbGrid(image, fit: fit) else { return nil }
        return Imaging.frame(fromRGB: rgb, dark: dark, white: white, boost: boost)
    }

    // MARK: text

    /// text mit der systemschrift in 20 pixel breite seiten schneiden (pixelig, ohne kantenglaettung)
    static func textPages(_ text: String, color: UInt8, fontSize: CGFloat = 11, spacing: Int = 1) -> [Frame] {
        guard !text.isEmpty else { return [] }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let bounds = (text as NSString).size(withAttributes: attrs)
        let tw = max(1, Int(ceil(bounds.width))), th = max(1, Int(ceil(bounds.height)))
        let cw = tw + 2 * spacing
        guard let ctx = CGContext(data: nil, width: cw, height: th, bitsPerComponent: 8, bytesPerRow: cw,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: cw, height: th))
        ctx.setShouldAntialias(false)
        ctx.setAllowsFontSmoothing(false)
        UIGraphicsPushContext(ctx)
        // gray-context hat ursprung unten links, UIKit zeichnet oben links -> spiegeln
        ctx.translateBy(x: 0, y: CGFloat(th))
        ctx.scaleBy(x: 1, y: -1)
        (text as NSString).draw(at: CGPoint(x: CGFloat(spacing), y: 0), withAttributes: attrs)
        UIGraphicsPopContext()
        guard let data = ctx.data else { return [] }
        let p = data.assumingMemoryBound(to: UInt8.self)

        // zeilen mit inhalt bestimmen und vertikal zentrieren
        var pages: [Frame] = []
        let usable = min(th, H)
        let yOff = (H - usable) / 2
        let srcOff = (th - usable) / 2
        var x0 = 0
        while x0 < cw {
            var f = blankFrame()
            let chunk = min(W, cw - x0)
            let xOff = (W - chunk) / 2
            for y in 0..<usable {
                for x in 0..<chunk where p[(y + srcOff) * cw + x0 + x] > 127 {
                    f[(y + yOff) * W + xOff + x] = color
                }
            }
            pages.append(f)
            x0 += W
        }
        return pages
    }
}
