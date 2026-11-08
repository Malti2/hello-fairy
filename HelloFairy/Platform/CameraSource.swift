import Foundation
import AVFoundation

enum CameraError: Error, LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return "kamera nicht erlaubt: einstellungen > Hello Fairy > kamera"
        case .unavailable: return "keine kamera verfuegbar (simulator?)"
        }
    }
}

/// frontkamera -> 20x20 raster (gespiegelt, mittig quadratisch beschnitten, flaechengemittelt)
final class CameraSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "hellofairy.camera")
    private let lock = NSLock()
    private var latest: RGBGrid?

    static func make() async throws -> CameraSource {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraError.denied }
        default: throw CameraError.denied
        }
        let src = CameraSource()
        try src.configure()
        return src
    }

    private func configure() throws {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { throw CameraError.unavailable }
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        session.addOutput(output)
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }       // hochformat
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = device.position == .front                              // spiegel-look
            }
        }
        session.commitConfiguration()
        queue.async { [session] in session.startRunning() }
    }

    func read() -> RGBGrid? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func close() {
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let stride = CVPixelBufferGetBytesPerRow(buf)
        let side = min(w, h)
        let x0 = (w - side) / 2, y0 = (h - side) / 2
        let block = max(1, side / W)
        let sample = max(1, block / 4)
        let px = base.assumingMemoryBound(to: UInt8.self)
        var out = RGBGrid()
        for gy in 0..<H {
            for gx in 0..<W {
                var r = 0, g = 0, b = 0, n = 0
                var yy = y0 + gy * block
                while yy < y0 + (gy + 1) * block && yy < h {
                    var xx = x0 + gx * block
                    while xx < x0 + (gx + 1) * block && xx < w {
                        let o = yy * stride + xx * 4          // BGRA
                        b += Int(px[o]); g += Int(px[o + 1]); r += Int(px[o + 2])
                        n += 1
                        xx += sample
                    }
                    yy += sample
                }
                if n > 0 {
                    let i = gy * W + gx
                    out.v[i * 3] = Float(r) / Float(n) / 255
                    out.v[i * 3 + 1] = Float(g) / Float(n) / 255
                    out.v[i * 3 + 2] = Float(b) / Float(n) / 255
                }
            }
        }
        lock.lock()
        latest = out
        lock.unlock()
    }
}
