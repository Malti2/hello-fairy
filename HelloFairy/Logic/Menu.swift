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
        AppEntry(id: "breakout", title: "Breakout", symbol: "rectangle.split.3x1.fill", subtitle: "steine abraeumen"),
        AppEntry(id: "flappy", title: "Flappy", symbol: "bird.fill", subtitle: "tippen zum flattern"),
        AppEntry(id: "life", title: "Life", symbol: "circle.grid.3x3.fill", subtitle: "zellen malen und wachsen sehen"),
        AppEntry(id: "paint", title: "Zeichnen", symbol: "paintbrush.pointed.fill", subtitle: "mit dem finger malen"),
        AppEntry(id: "show", title: "Lichtshow", symbol: "sparkles", subtitle: "plasma, feuer, matrix, sterne"),
        AppEntry(id: "marquee", title: "Laufschrift", symbol: "textformat.abc", subtitle: "dein text scrollt vorbei"),
        AppEntry(id: "clock", title: "Uhr", symbol: "clock.fill", subtitle: "analog und digital"),
        AppEntry(id: "timer", title: "Timer", symbol: "timer", subtitle: "timer und stoppuhr"),
        AppEntry(id: "weather", title: "Wetter", symbol: "cloud.sun.fill", subtitle: "aktuell, heute, regen"),
        AppEntry(id: "mirror", title: "Mirror", symbol: "camera.fill", subtitle: "du als licht-pixel"),
        AppEntry(id: "sound", title: "Sound", symbol: "waveform", subtitle: "musik als leuchtende saeulen"),
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
        "breakout": [
            "RRRRRRRRRRRR", "OOOOOOOOOOOO", "YYYYYYYYYYYY", "............", ".....W......", "............", "....GGGG....",
        ],
        "flappy": [
            ".GG......GG.", ".GG......GG.", ".GG...YY.GG.", "......YYR...", ".GG......GG.", ".GG......GG.", ".GG......GG.",
        ],
        "life": [
            "..C.........", "...C....CCC.", ".CCC........", "............",
        ],
        "paint": [
            "RROOYYGGCCBB", "RROOYYGGCCBB", "............", "......W.....", ".....WW.....",
        ],
        "show": [
            "....RRRR....", "..RROOOORR..", ".ROOYYYYOOR.", "ROYYGGGGYYOR",
        ],
        "marquee": [
            "W.W.WWW.W...", "W.W.W...W...", "WWW.WW..W...", "W.W.W...W...", "W.W.WWW.WWW.",
        ],
        "timer": [
            "WWWWWWWWW", ".WYYYYYW.", "..WYYYW..", "...WYW...", "....W....", "...W.W...", "..W.Y.W..", ".W.YYY.W.", "WWWWWWWWW",
        ],
        "sound": [
            "..........R.", "....Y.....R.", "....Y..G..R.", "..C.Y..G..R.", "..C.Y..G..R.", "B.C.Y..G..R.", "B.C.Y.GG..R.",
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
        let gap = n > 9 ? 1 : 2                 // viele apps: punkte ohne luecke, damit alle passen
        let dotsX = (W - (gap * (n - 1) + 1)) / 2
        for k in 0..<n { f[17 * W + dotsX + gap * k] = k == i ? 30 : 120 }
        return f
    }
}
