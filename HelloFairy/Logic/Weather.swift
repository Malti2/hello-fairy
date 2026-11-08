import Foundation

struct GeoLocation: Codable, Equatable {
    var name: String
    var lat: Double
    var lon: Double
}

struct WeatherData: Equatable {
    var temp: Int
    var code: Int
    var isDay: Bool
    var wind: Double?
    var high: Int
    var low: Int
    var rain: [Int]
}

enum WeatherError: Error, LocalizedError {
    case cityNotFound(String)
    case noCity
    case badResponse

    var errorDescription: String? {
        switch self {
        case .cityNotFound(let c): return "stadt nicht gefunden: \(c)"
        case .noCity: return "keine stadt gesetzt"
        case .badResponse: return "unerwartete antwort vom wetterdienst"
        }
    }
}

// MARK: daten (Open-Meteo, gratis, kein key)

enum OpenMeteo {
    struct GeocodeResponse: Decodable {
        struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Result]?
    }

    struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int?
            let wind_speed_10m: Double?
        }
        struct Hourly: Decodable {
            let time: [String]
            let precipitation_probability: [Double?]
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    static func geocodeURL(_ city: String) -> URL? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        c?.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"),
                         .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        return c?.url
    }

    static func forecastURL(lat: Double, lon: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lon)),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "2"),
            .init(name: "current", value: "temperature_2m,weather_code,is_day,wind_speed_10m"),
            .init(name: "hourly", value: "precipitation_probability"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
        ]
        return c?.url
    }

    static func parseGeocode(_ data: Data, city: String) throws -> GeoLocation {
        let r = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        guard let first = r.results?.first else { throw WeatherError.cityNotFound(city) }
        return GeoLocation(name: first.name, lat: first.latitude, lon: first.longitude)
    }

    static func parseForecast(_ data: Data) throws -> WeatherData {
        let r = try JSONDecoder().decode(ForecastResponse.self, from: data)
        guard let hi = r.daily.temperature_2m_max.first, let lo = r.daily.temperature_2m_min.first else {
            throw WeatherError.badResponse
        }
        let nowHour = String(r.current.time.prefix(13))
        let start = r.hourly.time.firstIndex { String($0.prefix(13)) >= nowHour } ?? 0
        let probs = r.hourly.precipitation_probability
        var rain: [Int] = []
        if start < probs.count {
            rain = probs[start..<min(probs.count, start + 6)].map { Int($0 ?? 0) }
        }
        rain += Array(repeating: 0, count: max(0, 6 - rain.count))
        return WeatherData(temp: Int(r.current.temperature_2m.rounded(.toNearestOrEven)),
                           code: r.current.weather_code, isDay: (r.current.is_day ?? 1) != 0,
                           wind: r.current.wind_speed_10m,
                           high: Int(hi.rounded(.toNearestOrEven)), low: Int(lo.rounded(.toNearestOrEven)),
                           rain: rain)
    }

    private static func fetchData(_ url: URL?) async throws -> Data {
        guard let url else { throw WeatherError.badResponse }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("hellofairy-ios/0.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    static func geocode(_ city: String) async throws -> GeoLocation {
        try parseGeocode(await fetchData(geocodeURL(city)), city: city)
    }

    static func fetch(lat: Double, lon: Double) async throws -> WeatherData {
        try parseForecast(await fetchData(forecastURL(lat: lat, lon: lon)))
    }
}

// MARK: darstellung

enum WeatherFace {
    static let codes: [Character: UInt8?] = [".": nil, "Y": 30, "O": 15, "W": 255, "B": 120, "C": 90, "R": 0, "G": 60]

    static let icons: [String: [String]] = [
        "sun": [
            ".....O.....", ".O...O...O.", "..O.YYY.O..", "...YYYYY...", "OOOYYYYYOOO",
            "...YYYYY...", "..O.YYY.O..", ".O...O...O.", ".....O.....",
        ],
        "moon": [
            "....WWW....", "..WWW......", ".WW........", ".WW.....C..", ".WW........",
            ".WW...C....", "..WWW......", "....WWW....",
        ],
        "partly": [
            "..O.O.O....", "...YYY.....", ".O.YYYYWW..", "...YYWWWWWW", "....WWWWWWW", ".....WWWWW.",
        ],
        "cloud": [
            "...WWW.....", "..WWWWW.WW.", ".WWWWWWWWWW", "WWWWWWWWWWW", ".WWWWWWWWW.",
        ],
        "rain": [
            "...WWW.....", "..WWWWW.WW.", ".WWWWWWWWWW", "WWWWWWWWWWW", ".WWWWWWWWW.",
            "...........", "..B..B..B..", ".B..B..B...",
        ],
        "snow": [
            "...WWW.....", "..WWWWW.WW.", ".WWWWWWWWWW", "WWWWWWWWWWW", ".WWWWWWWWW.",
            "...........", "..C..C..C..", ".C..C..C..C",
        ],
        "thunder": [
            "...WWW.....", "..WWWWW.WW.", ".WWWWWWWWWW", "WWWWWWWWWWW", ".WWWWWWWWW.",
            "......YY...", ".....YY....", "....YYYY...", ".....YY....",
        ],
        "fog": [
            "..WWWWWWW..", "...........", ".WWWWWWWWW.", "...........", "..WWWWWWW..",
            "...........", "WWWWWWWWWWW",
        ],
    ]

    static let arrows: [String: [String]] = ["up": ["010", "111", "111"], "down": ["111", "111", "010"]]

    /// WMO wettercode -> icon
    static func iconName(code: Int, isDay: Bool = true) -> String {
        if code == 0 || code == 1 { return isDay ? "sun" : "moon" }
        if code == 2 { return isDay ? "partly" : "cloud" }
        if code == 3 { return "cloud" }
        if code == 45 || code == 48 { return "fog" }
        if (51...67).contains(code) || (80...82).contains(code) { return "rain" }
        if (71...77).contains(code) || code == 85 || code == 86 { return "snow" }
        if code >= 95 { return "thunder" }
        return "cloud"
    }

    static func tempColor(_ t: Double) -> UInt8 {
        if t < 0 { return 120 }
        if t < 10 { return 90 }
        if t < 20 { return 60 }
        if t < 28 { return 30 }
        return 0
    }

    static func blit(_ f: inout Frame, _ rows: [String], x0: Int, y0: Int) {
        for (dy, row) in rows.enumerated() {
            for (dx, ch) in row.enumerated() {
                guard let entry = codes[ch], let color = entry else { continue }
                let x = x0 + dx, y = y0 + dy
                if 0 <= x, x < W, 0 <= y, y < H { f[y * W + x] = color }
            }
        }
    }

    static func number(_ f: inout Frame, _ value: Int, y0: Int, color: UInt8, x0: Int? = nil) {
        let text = String(value)
        var x = x0 ?? (W - Glyphs.textWidth(text) - 2) / 2      // platz fuer das gradzeichen
        for ch in text { x = Glyphs.draw(ch, into: &f, x: x, y: y0, color: color) }
        if x < W { f[y0 * W + x] = color }
    }

    static func pageDots(_ f: inout Frame, page: Int, pages: Int = 3) {
        let x0 = (W - (2 * pages - 1)) / 2
        for i in 0..<pages { f[(H - 1) * W + x0 + 2 * i] = i == page ? 30 : 120 }
    }

    static func render(_ data: WeatherData, page: Int) -> Frame {
        var f = blankFrame()
        if page == 0 {
            let icon = icons[iconName(code: data.code, isDay: data.isDay)] ?? icons["cloud"]!
            blit(&f, icon, x0: (W - icon[0].count) / 2, y0: 1 + (9 - icon.count) / 2)
            number(&f, data.temp, y0: 12, color: tempColor(Double(data.temp)))
        } else if page == 1 {
            let rows: [(top: Int, value: Int, arrow: String)] = [(3, data.high, "up"), (12, data.low, "down")]
            for r in rows {
                let sym = (arrows[r.arrow] ?? []).map {
                    $0.replacingOccurrences(of: "1", with: r.arrow == "up" ? "R" : "B")
                        .replacingOccurrences(of: "0", with: ".")
                }
                blit(&f, sym, x0: 2, y0: r.top + 1)
                number(&f, r.value, y0: r.top, color: tempColor(Double(r.value)), x0: 7)
            }
        } else {
            for (i, pct) in data.rain.prefix(6).enumerated() {
                let height = Int((Double(max(0, min(100, pct))) / 100 * 15).rounded(.toNearestOrEven))
                let x = 2 + 3 * i
                for dy in 0..<max(1, height) {          // mindestens ein stummel, damit 0% sichtbar bleibt
                    for dx in 0..<2 { f[(17 - dy) * W + x + dx] = height > 0 ? 120 : 90 }
                }
            }
            for x in 1..<(W - 1) { f[18 * W + x] = 15 }        // grundlinie
        }
        pageDots(&f, page: page)
        return f
    }

    static func loadingFrame(_ t: Int) -> Frame {
        var f = blankFrame()
        for i in 0..<3 { f[10 * W + 7 + 3 * i] = t % 3 == i ? 90 : 120 }
        return f
    }

    static func errorFrame() -> Frame {
        var f = blankFrame()
        for i in 0..<10 {
            f[(5 + i) * W + 5 + i] = 0
            f[(5 + i) * W + 14 - i] = 0
        }
        return f
    }
}

// MARK: app

final class WeatherApp: CurtainApp {
    typealias Fetcher = @Sendable (Double, Double) async throws -> WeatherData
    typealias Geocoder = @Sendable (String) async throws -> GeoLocation

    static let refreshSeconds = 600.0
    static let retrySeconds = 30.0

    let tick = 1.0
    let hint = "links/rechts seite · enter aktualisiert"

    private var cityQuery: String?
    private let clock: () -> Double
    private let fetcher: Fetcher
    private let geocoder: Geocoder
    private let save: Bool

    private(set) var loc: GeoLocation?
    private(set) var data: WeatherData?
    private(set) var error: String?
    private(set) var page = 0
    private var t = 0
    private var loading = false
    private var nextFetch = 0.0
    private var stopped = false

    init(city: String? = nil, clock: @escaping () -> Double = monotonicNow,
         fetcher: @escaping Fetcher = { try await OpenMeteo.fetch(lat: $0, lon: $1) },
         geocoder: @escaping Geocoder = { try await OpenMeteo.geocode($0) },
         save: Bool = true) {
        let q = city?.trimmingCharacters(in: .whitespaces)
        self.cityQuery = (q?.isEmpty ?? true) ? nil : q
        self.clock = clock
        self.fetcher = fetcher
        self.geocoder = geocoder
        self.save = save
        if cityQuery == nil { loc = Settings.location }
    }

    func reset() { nextFetch = 0 }
    func stop() { stopped = true }

    func key(_ key: Key) {
        switch key {
        case .left, .up: page = (page + 2) % 3
        case .right, .down: page = (page + 1) % 3
        case .enter: reset()
        default: break
        }
    }

    func step() {
        t += 1
        if !loading && clock() >= nextFetch {
            loading = true
            Task { @MainActor [weak self] in await self?.work() }
        }
    }

    @MainActor
    private func work() async {
        defer { loading = false }
        do {
            if let q = cityQuery {
                let l = try await geocoder(q)
                loc = l
                if save { Settings.location = l }
                cityQuery = nil
            }
            guard let l = loc else { throw WeatherError.noCity }
            let d = try await fetcher(l.lat, l.lon)
            if stopped { return }
            data = d
            error = nil
            nextFetch = clock() + WeatherApp.refreshSeconds
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            nextFetch = clock() + WeatherApp.retrySeconds
        }
    }

    func status() -> String {
        let where_ = loc?.name ?? "?"
        if let e = error, data == nil { return "wetter: \(e)" }
        guard let d = data else { return "wetter \(where_): laedt..." }
        let stale = error.map { "  (update fehlgeschlagen: \($0))" } ?? ""
        return "\(where_): \(d.temp)° \(WeatherFace.iconName(code: d.code, isDay: d.isDay))  "
            + "max \(d.high)° min \(d.low)°  regen \(d.rain.max() ?? 0)%  seite \(page + 1)/3\(stale)"
    }

    func frame() -> Frame {
        if let d = data { return WeatherFace.render(d, page: page) }
        return error != nil ? WeatherFace.errorFrame() : WeatherFace.loadingFrame(t)
    }
}
