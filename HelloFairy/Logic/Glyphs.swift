import Foundation

/// 3x5 pixel schrift (wie in snake/pong), ":" ist nur 1 breit
enum Glyphs {
    static let table: [Character: [String]] = [
        "G": ["011", "100", "101", "101", "011"],
        "A": ["010", "101", "111", "101", "101"],
        "M": ["101", "111", "111", "101", "101"],
        "E": ["111", "100", "110", "100", "111"],
        "O": ["010", "101", "101", "101", "010"],
        "V": ["101", "101", "101", "101", "010"],
        "R": ["110", "101", "110", "101", "101"],
        "W": ["101", "101", "111", "111", "101"],
        "I": ["111", "010", "010", "010", "111"],
        "N": ["110", "101", "101", "101", "101"],
        "L": ["100", "100", "100", "100", "111"],
        "S": ["011", "100", "010", "001", "110"],
        ":": ["0", "1", "0", "1", "0"],
        "-": ["000", "000", "111", "000", "000"],
        "B": ["110", "101", "110", "101", "110"],
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["110", "001", "010", "100", "111"],
        "3": ["110", "001", "010", "001", "110"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "110", "001", "110"],
        "6": ["011", "100", "110", "101", "010"],
        "7": ["111", "001", "010", "010", "010"],
        "8": ["010", "101", "010", "101", "010"],
        "9": ["010", "101", "011", "001", "110"],
        "C": ["011", "100", "100", "100", "011"],
        "D": ["110", "101", "101", "101", "110"],
        "F": ["111", "100", "110", "100", "100"],
        "H": ["101", "101", "111", "101", "101"],
        "J": ["001", "001", "001", "101", "010"],
        "K": ["101", "101", "110", "101", "101"],
        "P": ["110", "101", "110", "100", "100"],
        "Q": ["010", "101", "101", "110", "011"],
        "T": ["111", "010", "010", "010", "010"],
        "U": ["101", "101", "101", "101", "111"],
        "X": ["101", "101", "010", "101", "101"],
        "Y": ["101", "101", "010", "010", "010"],
        "Z": ["111", "001", "010", "100", "111"],
        " ": ["00", "00", "00", "00", "00"],
        "!": ["1", "1", "1", "0", "1"],
        "?": ["110", "001", "010", "000", "010"],
        ".": ["0", "0", "0", "0", "1"],
        ",": ["0", "0", "0", "1", "1"],
        "'": ["1", "1", "0", "0", "0"],
        "+": ["000", "010", "111", "010", "000"],
        "/": ["001", "001", "010", "100", "100"],
        "%": ["101", "001", "010", "100", "101"],
        "<": ["001", "010", "100", "010", "001"],
        ">": ["100", "010", "001", "010", "100"],
        "#": ["101", "111", "101", "111", "101"],
    ]

    static func normalize(_ text: String) -> String {
        text.uppercased()
            .replacingOccurrences(of: "Ä", with: "AE")
            .replacingOccurrences(of: "Ö", with: "OE")
            .replacingOccurrences(of: "Ü", with: "UE")
    }

    /// text als spalten (je 5 zeilen), 1 pixel luecke zwischen den zeichen
    static func bitmap(_ text: String) -> [[Bool]] {
        var cols: [[Bool]] = []
        for ch in normalize(text) {
            let g = glyph(ch)
            for x in 0..<g[0].count {
                cols.append((0..<5).map { row in
                    let line = Array(g[min(row, g.count - 1)])
                    return x < line.count && line[x] == "1"
                })
            }
            cols.append([Bool](repeating: false, count: 5))
        }
        return cols
    }

    static func glyph(_ c: Character) -> [String] { table[c] ?? ["0"] }

    static func width(_ c: Character) -> Int { glyph(c)[0].count }

    /// breite eines strings inkl. 1px abstand
    static func textWidth(_ text: String) -> Int {
        text.reduce(0) { $0 + width($1) } + max(0, text.count - 1)
    }

    /// zeichnet einen glyph, gibt die x-position nach dem glyph + abstand zurueck
    @discardableResult
    static func draw(_ c: Character, into f: inout Frame, x: Int, y: Int, color: UInt8) -> Int {
        let g = glyph(c)
        for (dy, row) in g.enumerated() {
            for (dx, bit) in row.enumerated() where bit == "1" {
                let px = x + dx, py = y + dy
                if px >= 0, px < W, py >= 0, py < H { f[py * W + px] = color }
            }
        }
        return x + g[0].count + 1
    }
}

func blankWithBorder() -> Frame {
    var f = blankFrame()
    for i in 0..<W {
        f[i] = Px.white
        f[(H - 1) * W + i] = Px.white
        f[i * W] = Px.white
        f[i * W + W - 1] = Px.white
    }
    return f
}

/// rahmen + eine zeile text, zentriert (pong/mario banner)
func textFrame(_ text: String, color: UInt8) -> Frame {
    var f = blankWithBorder()
    var x = (W - Glyphs.textWidth(text)) / 2
    let y = (H - 5) / 2
    for ch in text { x = Glyphs.draw(ch, into: &f, x: x, y: y, color: color) }
    return f
}

/// rahmen + gestapelter text ("GAME" / "OVER"), 3 breite glyphen
func stackedTextFrame(_ lines: [String], color: UInt8) -> Frame {
    var f = blankWithBorder()
    let totalH = lines.count * 5 + (lines.count - 1)
    let y0 = (H - totalH) / 2
    for (n, line) in lines.enumerated() {
        let x0 = (W - (line.count * 4 - 1)) / 2
        for (k, ch) in line.enumerated() {
            Glyphs.draw(ch, into: &f, x: x0 + k * 4, y: y0 + n * 6, color: color)
        }
    }
    return f
}

func gameOverText() -> Frame { stackedTextFrame(["GAME", "OVER"], color: 0) }
