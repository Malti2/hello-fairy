import Foundation
import CoreBluetooth
import Observation

enum LinkError: Error, LocalizedError {
    case bluetoothOff(String)
    case notFound
    case timeout(String)
    case notCurtain(String)
    case lost(String)

    var errorDescription: String? {
        switch self {
        case .bluetoothOff(let s): return s
        case .notFound: return "keine Hello Fairy gefunden. einschalten, nah ran, offizielle app schliessen"
        case .timeout(let s): return "zeitueberschreitung: \(s)"
        case .notCurtain(let s): return "bildupload geht nur mit dem 20x20 vorhang (\(s))"
        case .lost(let s): return "verbindung verloren: \(s)"
        }
    }
}

struct FoundDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum LinkPhase: Equatable {
    case idle, scanning, connecting, discovering, ready
}

/// BLE verbindung zur Hello Fairy (CoreBluetooth). Reconnect + ack/status/info wie in ble.py
@MainActor
@Observable
final class FairyLink: NSObject {
    // sichtbarer zustand
    private(set) var phase: LinkPhase = .idle
    private(set) var deviceName: String = ""
    private(set) var info: DeviceInfo?
    private(set) var found: [FoundDevice] = []
    private(set) var reconnects = 0
    private(set) var lastError: String?
    private(set) var btState: String = "unbekannt"
    var log: [String] = []

    /// gemeinsamer bildschirmzustand der apps (nil = vorhang muss neu initialisiert werden)
    @ObservationIgnored var screenState: [UInt8]?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var command: CBCharacteristic?
    @ObservationIgnored private var notify: CBCharacteristic?
    @ObservationIgnored private var seen: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var acks: Set<UInt8> = []
    @ObservationIgnored private var statusReply: DeviceStatus?
    @ObservationIgnored private var infoReply: DeviceInfo?
    @ObservationIgnored private var wantDisconnect = false
    @ObservationIgnored private var reconnecting = false
    @ObservationIgnored private var scanTarget: UUID?          // gezielte suche nach gespeichertem geraet
    @ObservationIgnored private var connectError: String?

    var isReady: Bool { phase == .ready && peripheral?.state == .connected }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    private func note(_ s: String) {
        log.append(s)
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }

    // MARK: bluetooth zustand

    private func waitForPoweredOn(timeout: Double = 6) async throws {
        let end = Date().addingTimeInterval(timeout)
        while central.state != .poweredOn {
            switch central.state {
            case .unauthorized:
                throw LinkError.bluetoothOff("bluetooth-zugriff fehlt: einstellungen > Hello Fairy > bluetooth erlauben")
            case .unsupported:
                throw LinkError.bluetoothOff("dieses geraet kann kein bluetooth LE")
            case .poweredOff:
                throw LinkError.bluetoothOff("bluetooth ist aus")
            default: break
            }
            if Date() > end { throw LinkError.timeout("bluetooth nicht bereit") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: scannen

    func scan(seconds: Double = 5) async throws {
        try await waitForPoweredOn()
        found = []
        seen = [:]
        phase = .scanning
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        central.stopScan()
        if phase == .scanning { phase = .idle }
    }

    private func isFairy(_ p: CBPeripheral, _ adv: [String: Any]) -> Bool {
        let name = (adv[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        if name.lowercased().hasPrefix(Proto.namePrefix.lowercased()) { return true }
        if let uuids = adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           uuids.contains(CBUUID(string: Proto.serviceUUID)) { return true }
        return false
    }

    // MARK: verbinden

    /// verbindet mit dem gespeicherten geraet oder dem staerksten Hello Fairy in der naehe
    func connect(to id: UUID? = nil, scanSeconds: Double = 8) async throws {
        wantDisconnect = false
        lastError = nil
        try await waitForPoweredOn()
        if isReady { return }
        let wanted = id ?? Settings.deviceID.flatMap { UUID(uuidString: $0) }

        // 1) direkt zum bekannten geraet (ohne scan)
        if let wanted, let known = seen[wanted] ?? central.retrievePeripherals(withIdentifiers: [wanted]).first {
            do {
                try await open(known, timeout: 8)
                return
            } catch {
                note("direkt verbinden klappte nicht, scanne: \(error.localizedDescription)")
            }
        }

        // 2) scannen bis ein passendes geraet auftaucht
        seen = [:]
        found = []
        scanTarget = wanted
        phase = .scanning
        central.scanForPeripherals(withServices: nil, options: nil)
        let end = Date().addingTimeInterval(scanSeconds)
        var firstSeen: Date?
        var target: CBPeripheral?
        while Date() < end {
            if let w = wanted, let p = seen[w] { target = p; break }
            if wanted == nil, !found.isEmpty {
                if firstSeen == nil { firstSeen = Date() }
                if let t0 = firstSeen, Date().timeIntervalSince(t0) > 1.2 { break }     // kurz weiter schauen: staerkstes nehmen
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        central.stopScan()
        scanTarget = nil
        if target == nil, let f = found.max(by: { $0.rssi < $1.rssi }) { target = seen[f.id] }
        guard let t = target else {
            phase = .idle
            throw LinkError.notFound
        }
        try await open(t, timeout: 15)
    }

    private func open(_ p: CBPeripheral, timeout: Double) async throws {
        peripheral = p
        p.delegate = self
        command = nil
        notify = nil
        connectError = nil
        phase = .connecting
        deviceName = p.name ?? "Hello Fairy"
        central.connect(p, options: nil)
        let end = Date().addingTimeInterval(timeout)
        while phase != .ready {
            if let e = connectError {
                central.cancelPeripheralConnection(p)
                phase = .idle
                throw LinkError.lost(e)
            }
            if Date() > end {
                central.cancelPeripheralConnection(p)
                phase = .idle
                throw LinkError.timeout("verbinden")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Settings.deviceID = p.identifier.uuidString
        note("verbunden mit \(deviceName)")
    }

    func disconnect() {
        wantDisconnect = true
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        phase = .idle
        screenState = nil
    }

    /// link fiel weg: neu verbinden. Danach muss der vorhang neu initialisiert werden (screenState = nil)
    func ensureConnected(attempts: Int = 5) async throws {
        if isReady { return }
        if reconnecting {
            while reconnecting { try await Task.sleep(nanoseconds: 100_000_000) }
            if isReady { return }
        }
        reconnecting = true
        defer { reconnecting = false }
        var last: Error?
        for attempt in 1...attempts {
            do {
                if let p = peripheral { central.cancelPeripheralConnection(p) }
                try await connect(scanSeconds: attempt == 1 ? 4 : 6)
                reconnects += 1
                screenState = nil
                info = nil
                note("neu verbunden (#\(reconnects))")
                return
            } catch {
                last = error
                try await Task.sleep(nanoseconds: UInt64(min(2.0, 0.5 * Double(attempt)) * 1_000_000_000))
            }
        }
        throw LinkError.lost("neu verbinden fehlgeschlagen: \(last?.localizedDescription ?? "?")")
    }

    // MARK: schreiben

    /// wie viele bytes pro write passen
    var writeCapacity: Int? {
        peripheral?.maximumWriteValueLength(for: .withoutResponse)
    }

    func write(_ packet: [UInt8], ack: Bool = false, timeout: Double = 5) async throws {
        var sent = false
        for _ in 1...2 {
            try await ensureConnected()
            guard let p = peripheral, let c = command, p.state == .connected else {
                phase = .idle           // link tot: beim naechsten versuch neu verbinden
                continue
            }
            if ack { acks.remove(packet[1]) }
            // flusskontrolle: ohne antwort nur schreiben, wenn der controller bereit ist
            var waited = 0.0
            while !p.canSendWriteWithoutResponse && waited < 2.0 {
                try await Task.sleep(nanoseconds: 5_000_000)
                waited += 0.005
            }
            if p.state != .connected {
                phase = .idle
                continue
            }
            p.writeValue(Data(packet), for: c, type: .withoutResponse)
            sent = true
            break
        }
        if !sent { throw LinkError.lost("senden fehlgeschlagen") }
        if ack {
            let end = Date().addingTimeInterval(timeout)
            while !acks.contains(packet[1]) && Date() < end {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            if !acks.contains(packet[1]) { note("kein ACK fuer 0x\(String(format: "%02x", packet[1]))") }
            acks.remove(packet[1])
        }
    }

    func getInfo(timeout: Double = 5) async throws -> DeviceInfo? {
        infoReply = nil
        try await write(Proto.infoRequest())
        let end = Date().addingTimeInterval(timeout)
        while infoReply == nil && Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        info = infoReply
        return infoReply
    }

    func getStatus(timeout: Double = 4) async throws -> DeviceStatus? {
        statusReply = nil
        try await write(Proto.statusRequest())
        let end = Date().addingTimeInterval(timeout)
        while statusReply == nil && Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        return statusReply
    }

    // MARK: licht-kommandos

    func setPower(_ on: Bool) async throws {
        try await write(Proto.power(on), ack: true)
    }

    func setColor(h: Int, s: Int, v: Int) async throws {
        try await setPower(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        try await write(Proto.color(h: h, s: s, v: v), ack: true)
    }

    func setPreset(_ n: Int, brightness: Int = 50) async throws {
        try await setPower(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        try await write(try Proto.preset(n, brightness: brightness), ack: true)
    }

    func setBrightness(_ pct: Int) async throws {
        let st = try await getStatus()
        if let st, st.mode == 2 {
            try await write(try Proto.preset(st.preset, brightness: pct), ack: true)
        } else if let st, st.mode == 1 {
            try await write(Proto.color(h: st.hue, s: Int(st.saturation), v: pct), ack: true)
        } else {
            try await write(Proto.color(h: 0, s: 0, v: pct), ack: true)
        }
    }

    // MARK: pixel-kommandos

    func requireCurtain(force: Bool = false) async throws {
        if let info, info.isCurtain { return }
        guard let i = try await getInfo() else {
            if force { return }
            throw LinkError.notCurtain("keine geraeteinfo")
        }
        note("geraet: \(i.model) \(i.ledCount) LEDs")
        if !i.isCurtain && !force {
            throw LinkError.notCurtain("\(i.model), \(i.ledCount) LEDs, \(i.columns)x\(i.rows)")
        }
    }

    func play(_ seq: [SeqStep], force: Bool = false, progress: ((Int, Int, String) -> Void)? = nil) async throws {
        try await requireCurtain(force: force)
        try await setPower(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        for (i, step) in seq.enumerated() {
            progress?(i + 1, seq.count, step.label)
            try await write(step.packet)
            try await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
        }
        screenState = nil          // bild kam ueber die offizielle sequenz: draw-mode muss neu aufgesetzt werden
    }

    func sendImage(_ frame: Frame, force: Bool = false, progress: ((Int, Int, String) -> Void)? = nil) async throws {
        try await ensureConnected()
        let per = Proto.pixelsPerPacket(writeCapacity: writeCapacity)
        try await play(Proto.singleImageSequence(frame, perPacket: per), force: force, progress: progress)
    }

    func sendAnimation(_ frames: [Frame], force: Bool = false, progress: ((Int, Int, String) -> Void)? = nil) async throws {
        try await ensureConnected()
        let per = Proto.pixelsPerPacket(writeCapacity: writeCapacity)
        try await play(try Proto.twoPictureSequence(frames, perPacket: per), force: force, progress: progress)
    }

    func playback(kind: String, movement: String, speed: Int, brightness: Int) async throws {
        for pkt in try Proto.playbackPackets(kind: kind, movement: movement, speed: speed, brightness: brightness) {
            try await write(pkt)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

// MARK: - delegates

extension FairyLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn: btState = "an"
            case .poweredOff: btState = "aus"
            case .unauthorized: btState = "nicht erlaubt"
            case .unsupported: btState = "nicht unterstuetzt"
            default: btState = "unbekannt"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            let match = isFairy(peripheral, advertisementData) || id == scanTarget
            guard match else { return }
            seen[id] = peripheral
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Hello Fairy"
            let dev = FoundDevice(id: id, name: name, rssi: RSSI.intValue)
            if let i = found.firstIndex(where: { $0.id == id }) { found[i] = dev } else { found.append(dev) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            phase = .discovering
            peripheral.discoverServices([CBUUID(string: Proto.serviceUUID)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            connectError = error?.localizedDescription ?? "verbindung fehlgeschlagen"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            command = nil
            notify = nil
            screenState = nil
            info = nil
            if phase == .connecting || phase == .discovering { connectError = "getrennt beim verbinden" }
            if phase == .ready || phase == .discovering { phase = .idle }
            if !wantDisconnect { lastError = "verbindung abgebrochen" }
            note("getrennt")
        }
    }
}

extension FairyLink: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error { connectError = error.localizedDescription; return }
            guard let svc = peripheral.services?.first(where: { $0.uuid == CBUUID(string: Proto.serviceUUID) }) else {
                connectError = "service nicht gefunden"
                return
            }
            peripheral.discoverCharacteristics([CBUUID(string: Proto.commandUUID), CBUUID(string: Proto.notifyUUID)],
                                               for: svc)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            if let error { connectError = error.localizedDescription; return }
            for c in service.characteristics ?? [] {
                if c.uuid == CBUUID(string: Proto.commandUUID) { command = c }
                if c.uuid == CBUUID(string: Proto.notifyUUID) { notify = c }
            }
            guard command != nil, let n = notify else {
                connectError = "characteristics nicht gefunden"
                return
            }
            peripheral.setNotifyValue(true, for: n)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            if let error { connectError = error.localizedDescription; return }
            if characteristic.uuid == CBUUID(string: Proto.notifyUUID), characteristic.isNotifying { phase = .ready }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        MainActor.assumeIsolated {
            if let ack = Proto.ackedCommand(bytes) {
                acks.insert(ack)
                return
            }
            if let st = Proto.decodeStatus(bytes) {
                statusReply = st
            } else if let inf = Proto.decodeDeviceInfo(bytes) {
                infoReply = inf
            }
        }
    }
}
