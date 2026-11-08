import Foundation

/// zerlegte uhrzeit, damit sich die darstellung ohne kalender testen laesst
struct ClockTime {
    var hour: Int
    var minute: Int
    var second: Int
    var micro: Int = 0
    var weekday: Int = 0       // montag = 0

    init(hour: Int, minute: Int, second: Int, micro: Int = 0, weekday: Int = 0) {
        self.hour = hour; self.minute = minute; self.second = second
        self.micro = micro; self.weekday = weekday
    }

    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond, .weekday], from: date)
        hour = c.hour ?? 0
        minute = c.minute ?? 0
        second = c.second ?? 0
        micro = (c.nanosecond ?? 0) / 1000
        weekday = ((c.weekday ?? 2) + 5) % 7        // sonntag = 1 -> 6, montag = 2 -> 0
    }
}

enum ClockFace {
    static let cx = 10.0, cy = 10.0
    static let hourLen = 4.0, minLen = 6.5, secLen = 8.0, tickR = 9.2
    static let hourColor: UInt8 = 0, minColor: UInt8 = 30, secColor: UInt8 = 90
    static let quarterColor: UInt8 = 255, tickColor: UInt8 = 120
    static let barColor: UInt8 = 90, dotToday: UInt8 = 30, dotOther: UInt8 = 120

    static func px(_ x: Double, _ y: Double) -> (Int, Int) {
        func r6(_ v: Double) -> Double { (v * 1e6).rounded(.toNearestOrEven) / 1e6 }
        return (Int(floor(r6(x))), Int(floor(r6(y))))
    }

    static func polar(_ angleDeg: Double, _ r: Double) -> (Int, Int) {
        let a = angleDeg * Double.pi / 180
        return px(cx + r * sin(a), cy - r * cos(a))
    }

    static func hand(_ f: inout Frame, angle: Double, length: Double, color: UInt8) {
        for i in 0...Int(length * 4) {          // alle viertel pixel samplen
            let (x, y) = polar(angle, Double(i) / 4)
            if 0 <= x, x < W, 0 <= y, y < H { f[y * W + x] = color }
        }
    }

    static func handAngles(_ now: ClockTime) -> (hour: Double, minute: Double, second: Double) {
        let sec = Double(now.second) + Double(now.micro) / 1e6
        let minute = Double(now.minute) + sec / 60
        let hour = Double(now.hour % 12) + minute / 60
        return (hour * 30, minute * 6, Double(now.second) * 6)     // sekundenzeiger tickt einmal pro sekunde
    }

    static func renderAnalog(_ now: ClockTime) -> Frame {
        var f = blankFrame()
        for i in 0..<12 {
            let (x, y) = polar(Double(i) * 30, tickR)
            f[y * W + x] = i % 3 == 0 ? quarterColor : tickColor
        }
        let a = handAngles(now)
        hand(&f, angle: a.second, length: secLen, color: secColor)      // zuerst, damit die anderen sichtbar bleiben
        hand(&f, angle: a.minute, length: minLen, color: minColor)
        hand(&f, angle: a.hour, length: hourLen, color: hourColor)
        return f
    }

    static func timeColor(_ hour: Int) -> UInt8 {
        if (6..<12).contains(hour) { return 30 }
        if (12..<18).contains(hour) { return 60 }
        if (18..<22).contains(hour) { return 15 }
        return 120
    }

    static func renderDigital(_ now: ClockTime) -> Frame {
        var f = blankFrame()
        let color = timeColor(now.hour)
        let text = String(format: "%02d:%02d", now.hour, now.minute)
        var x = (W - Glyphs.textWidth(text)) / 2
        let y = 7
        for ch in text {
            if ch == ":" && now.second % 2 == 1 {          // blinkender doppelpunkt
                x += Glyphs.width(ch) + 1
                continue
            }
            x = Glyphs.draw(ch, into: &f, x: x, y: y, color: ch == ":" ? 255 : color)
        }
        for d in 0..<7 { f[3 * W + 3 + 2 * d] = d == now.weekday ? dotToday : dotOther }
        let bar = Int((Double(now.second + 1) * Double(W) / 60).rounded(.toNearestOrEven))
        for i in 0..<bar { f[17 * W + i] = barColor }
        return f
    }
}

final class ClockApp: CurtainApp {
    let tick = 1.0
    let hint = "wischen oder tippen wechselt analog / digital"
    private let now: () -> Date
    private(set) var page = 0

    init(now: @escaping () -> Date = { Date() }) { self.now = now }

    func reset() { page = 0 }
    func step() {}

    func key(_ key: Key) {
        if [.left, .right, .up, .down, .enter].contains(key) { page = 1 - page }
    }

    func status() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE dd.MM.yyyy HH:mm:ss"
        return "\(f.string(from: now()))  seite \(page + 1)/2 (\(page == 0 ? "analog" : "digital"))"
    }

    func frame() -> Frame {
        let t = ClockTime(date: now())
        return page == 0 ? ClockFace.renderAnalog(t) : ClockFace.renderDigital(t)
    }
}
