import Foundation

struct AppEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let subtitle: String
}

/// das menue auf dem vorhang: icon der gewaehlten app + positionspunkte
enum CurtainMenu {
    static let codes: [Character: UInt8] = [
        ".": Px.off, "P": 140, "O": 15, "G": 60, "Y": 30, "R": 0, "B": 120, "W": Px.white, "C": 90,
    ]

    static let items: [AppEntry] = [
        AppEntry(id: "snake", title: "Snake", symbol: "lizard.fill", subtitle: "wischen zum lenken"),
        AppEntry(id: "pong", title: "Pong", symbol: "tennisball.fill", subtitle: "finger hoch und runter"),
        AppEntry(id: "tetris", title: "Tetris", symbol: "square.grid.2x2.fill", subtitle: "wischen und tippen"),
        AppEntry(id: "mario", title: "Mario", symbol: "figure.run", subtitle: "laufen, springen, feuerball"),
        AppEntry(id: "mirror", title: "Mirror", symbol: "camera.fill", subtitle: "du als licht-pixel"),
        AppEntry(id: "clock", title: "Uhr", symbol: "clock.fill", subtitle: "analog und digital"),
        AppEntry(id: "weather", title: "Wetter", symbol: "cloud.sun.fill", subtitle: "aktuell, heute, regen"),
    ]

    static let icons: [String: [String]] = [
        "snake": [
            ".GGGGGGGGG....", ".G.......G....", ".G..R....G....", ".GGGGGGGGG....", ".........G....", ".YGGGGGGGG....",
        ],
        "pong": [
            ".G..........R.", ".G..........R.", ".G....Y.....R.", ".G..........R.", "..............", "WWWWWWWWWWWWWW",
        ],
        "tetris": [
            "....PPP.....", ".....P......", "............", "............", "............",
            "G.......YY..", "GG..B...YY..", "GRRBBB.OOO..", "CCCCCRRBOO..",
        ],
        "mario": [
            "...Y........", "............", "............", "..R.....GG..", "..R.....GG..",
            "......P.GG..", "OOOOOOOOOOOO", "OOOOOOOOOOOO",
        ],
        "clock": [
            "..WWWWWWW..", ".W...Y...W.", "W....Y....W", "W....Y....W", "W....RRR..W", "W.........W", ".W.......W.", "..WWWWWWW..",
        ],
        "weather": [
            "....Y.......", ".Y..Y..Y....", "..YYYYY.....", "..YYYYWWW...", "...YYWWWWWW.", "....WWWWWWW.", ".....WWWWW..",
        ],
        "mirror": [
            "....WWWW....", "..WW....WW..", "WW..CCCC..WW", "W..CCBBCC..W", "WW..CCCC..WW", "..WW....WW..", "....WWWW....",
        ],
    ]

    static func frame(index: Int) -> Frame {
        var f = blankWithBorder()
        let i = ((index % items.count) + items.count) % items.count
        let icon = icons[items[i].id] ?? []
        let ih = icon.count
        let iw = icon.first?.count ?? 0
        let x0 = (W - iw) / 2, y0 = 2 + (12 - ih) / 2 + 1
        for (dy, row) in icon.enumerated() {
            for (dx, ch) in row.enumerated() { f[(y0 + dy) * W + x0 + dx] = codes[ch] ?? Px.off }
        }
        let n = items.count
        let dotsX = (W - (2 * n - 1)) / 2
        for k in 0..<n { f[17 * W + dotsX + 2 * k] = k == i ? 30 : 120 }
        return f
    }
}
