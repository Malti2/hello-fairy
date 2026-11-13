import Foundation

/// kleine bilder zum direkt aufs licht schicken
struct PixelArt: Identifiable {
    let id: String
    let title: String
    let rows: [String]

    static let codes: [Character: UInt8] = [
        "Y": 30, "O": 15, "R": 0, "G": 60, "B": 120, "W": Px.white, "C": 90, "P": 140, "M": 165, "L": 45,
    ]

    func frame() -> Frame {
        var f = blankFrame()
        let h = rows.count, w = rows.map { $0.count }.max() ?? 0
        let x0 = (W - w) / 2, y0 = (H - h) / 2
        for (dy, row) in rows.enumerated() {
            for (dx, ch) in row.enumerated() {
                guard let c = PixelArt.codes[ch] else { continue }
                let x = x0 + dx, y = y0 + dy
                if (0..<W).contains(x), (0..<H).contains(y) { f[y * W + x] = c }
            }
        }
        return f
    }

    static let all: [PixelArt] = [
        PixelArt(id: "heart", title: "Herz", rows: [
            ".RRR...RRR.", "RRRRR.RRRRR", "RRRRRRRRRRR", "RRRRRRRRRRR", ".RRRRRRRRR.",
            "..RRRRRRR..", "...RRRRR...", "....RRR....", ".....R.....",
        ]),
        PixelArt(id: "star", title: "Stern", rows: [
            ".....Y.....", ".....Y.....", "....YYY....", "YYYYYYYYYYY", ".YYYYYYYYY.",
            "..YYYYYYY..", "..YYYYYYY..", ".YYYY.YYYY.", ".YYY...YYY.", "YY.......YY",
        ]),
        PixelArt(id: "smiley", title: "Smiley", rows: [
            "...YYYYYY...", ".YYYYYYYYYY.", "YYYYYYYYYYYY", "YYY..YY..YYY", "YYY..YY..YYY",
            "YYYYYYYYYYYY", "YY.YYYYYY.YY", "YYY......YYY", ".YYYYYYYYYY.", "...YYYYYY...",
        ]),
        PixelArt(id: "ghost", title: "Geist", rows: [
            "...WWWWW...", ".WWWWWWWWW.", "WWWWWWWWWWW", "WWBBWWWBBWW", "WWBBWWWBBWW",
            "WWWWWWWWWWW", "WWWWWWWWWWW", "WWWWWWWWWWW", "WW.WW.WW.WW", "W...W...W..",
        ]),
        PixelArt(id: "invader", title: "Invader", rows: [
            "..G.....G..", "...G...G...", "..GGGGGGG..", ".GG.GGG.GG.", "GGGGGGGGGGG",
            "G.GGGGGGG.G", "G.G.....G.G", "...GG.GG...",
        ]),
        PixelArt(id: "tree", title: "Baum", rows: [
            "....G....", "...GGG...", "..GGGGG..", "...GGG...", "..GGGGG..", ".GGGGGGG.",
            "..GGGGG..", ".GGGGGGG.", "GGGGGGGGG", "....O....", "....O....",
        ]),
        PixelArt(id: "mushroom", title: "Pilz", rows: [
            "...RRRRR...", ".RRWWRRRRR.", "RRWWWRRWWRR", "RRRWRRRWWRR", "RRRRRRRRRRR",
            "..WWWWWWW..", "..WWWWWWW..", "...WWWWW...",
        ]),
        PixelArt(id: "moon", title: "Mond", rows: [
            "...WWWW...", "..WWW.....", ".WWW......", ".WWW...C..", ".WWW......",
            ".WWW...C..", ".WWW......", "..WWW.....", "...WWWW...",
        ]),
        PixelArt(id: "bolt", title: "Blitz", rows: [
            "....YYY.", "...YYY..", "..YYY...", ".YYYYYY.", "...YYY..", "..YY....", ".YY.....", "YY......",
        ]),
        PixelArt(id: "flower", title: "Blume", rows: [
            "...RRR...", ".RRRRRRR.", "RRRYYYRRR", "RRRYYYRRR", ".RRRRRRR.", "...RRR...",
            "....G....", "..G.G.G..", "...GGG...", "....G....",
        ]),
    ]

    /// regenbogen als farbverlauf von oben nach unten
    static func rainbow() -> Frame {
        (0..<PIXELS).map { UInt8(min(180, ($0 / W) * 9)) }
    }
}
