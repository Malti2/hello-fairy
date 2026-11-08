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

    static var minInterval: Double {
        get { let v = defaults.double(forKey: "hf.minInterval"); return v > 0 ? v : 0.06 }
        set { defaults.set(newValue, forKey: "hf.minInterval") }
    }
}
