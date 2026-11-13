import Foundation

/// kleine persistente einstellungen (statt ~/.config/hellofairy/config.json)
enum Settings {
    static var defaults: UserDefaults = .standard

    static var deviceID: String? {
        get { defaults.string(forKey: "hf.device") }
        set { defaults.set(newValue, forKey: "hf.device") }
    }

    static var city: String {
        get { defaults.string(forKey: "hf.city") ?? "" }
        set { defaults.set(newValue, forKey: "hf.city") }
    }

    static var location: GeoLocation? {
        get {
            guard let data = defaults.data(forKey: "hf.location") else { return nil }
            return try? JSONDecoder().decode(GeoLocation.self, from: data)
        }
        set {
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                defaults.set(data, forKey: "hf.location")
            } else {
                defaults.removeObject(forKey: "hf.location")
            }
        }
    }

    static var pongDifficulty: String {
        get { defaults.string(forKey: "hf.pong.difficulty") ?? "normal" }
        set { defaults.set(newValue, forKey: "hf.pong.difficulty") }
    }

    static var pongPoints: Int {
        get { let v = defaults.integer(forKey: "hf.pong.points"); return v > 0 ? v : 5 }
        set { defaults.set(newValue, forKey: "hf.pong.points") }
    }

    static var marqueeText: String {
        get { defaults.string(forKey: "hf.marquee.text") ?? "HELLO FAIRY" }
        set { defaults.set(newValue, forKey: "hf.marquee.text") }
    }

    static var marqueeBig: Bool {
        get { defaults.object(forKey: "hf.marquee.big") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hf.marquee.big") }
    }

    static var marqueeRainbow: Bool {
        get { defaults.object(forKey: "hf.marquee.rainbow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hf.marquee.rainbow") }
    }

    /// sekunden pro schritt der laufschrift
    static var marqueeTick: Double {
        get { let v = defaults.double(forKey: "hf.marquee.tick"); return v > 0 ? v : 0.09 }
        set { defaults.set(newValue, forKey: "hf.marquee.tick") }
    }

    static var timerMinutes: Int {
        get { let v = defaults.integer(forKey: "hf.timer.minutes"); return v > 0 ? v : 5 }
        set { defaults.set(newValue, forKey: "hf.timer.minutes") }
    }

    /// gespeichertes bild der zeichen-app (400 bytes)
    static var paintData: [UInt8]? {
        get { defaults.data(forKey: "hf.paint").map { [UInt8]($0) } }
        set { defaults.set(newValue.map { Data($0) }, forKey: "hf.paint") }
    }

    static var minInterval: Double {
        get { let v = defaults.double(forKey: "hf.minInterval"); return v > 0 ? v : 0.06 }
        set { defaults.set(newValue, forKey: "hf.minInterval") }
    }
}
