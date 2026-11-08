import XCTest
@testable import FairyLogic

final class ProtocolTests: XCTestCase {
    func testKnownVectors() throws {
        XCTAssertEqual(Proto.hex(Proto.power(true)), "aa020101ae")
        XCTAssertEqual(Proto.hex(Proto.power(false)), "aa020100ad")
        XCTAssertEqual(Proto.hex(try Proto.playbackPackets(kind: "picture", movement: "left", speed: 20, brightness: 100)[0]),
                       "aad00403641401fa")
        let ab = try Proto.playbackPackets(kind: "animation", movement: "breathe", speed: 30, brightness: 75)
        XCTAssertEqual(ab.map(Proto.hex), ["aad004014b1e02ea", "aadc010188"])
        XCTAssertEqual(Proto.d0(3), Proto.build(0xD0, [0, 0x64, 0x64, 3]))
        XCTAssertEqual(Proto.hex(Proto.infoRequest()), "aa0000aa")
    }

    func testFramePacketShape() {
        let packets = Proto.frameToDAPackets(blankFrame())
        XCTAssertEqual(packets.map { $0.count }, [242, 242, 242, 242, 242, 20])
    }

    func testSmallWriteCapacityStillCoversAllPixels() {
        let per = Proto.pixelsPerPacket(writeCapacity: 182)
        XCTAssertEqual(per, 59)
        let packets = Proto.frameToDAPackets(blankFrame(), perPacket: per)
        XCTAssertTrue(packets.allSatisfy { $0.count <= 182 })
        let pixels = packets.reduce(0) { $0 + ($1.count - 5) / 3 }
        XCTAssertEqual(pixels, 400)
    }

    func testColumnMajor() {
        var frame = blankFrame()
        frame[1 * 20 + 0] = 60      // zeile 1, spalte 0 -> index 0*20+1 = 1
        let pkt = Proto.frameToDAPackets(frame)[0]
        XCTAssertEqual(Array(pkt[4..<7]), [0, 0, Px.off])
        XCTAssertEqual(Array(pkt[7..<10]), [0, 1, 60])
    }

    func testTwoPictureSequenceLength() throws {
        let f = Frame(repeating: 0, count: 400)
        XCTAssertEqual(try Proto.twoPictureSequence([f, f]).count, 1 + 2 * (1 + 6 + 1) + 1 + 2)
    }

    func testSingleImageSequence() {
        let seq = Proto.singleImageSequence(blankFrame())
        XCTAssertEqual(seq.count, 2 + 6 + 2)
        XCTAssertEqual(seq.first?.label, "clear")
        XCTAssertEqual(seq.last?.label, "apply")
    }

    func testColorConversion() {
        XCTAssertEqual(Proto.rgbToPixelByte(r: 255, g: 0, b: 0), 0)
        XCTAssertEqual(Proto.rgbToPixelByte(r: 0, g: 255, b: 0), 60)
        XCTAssertEqual(Proto.rgbToPixelByte(r: 0, g: 0, b: 255), 120)
        XCTAssertEqual(Proto.rgbToPixelByte(r: 255, g: 255, b: 255), Px.white)
        XCTAssertEqual(Proto.rgbToPixelByte(r: 10, g: 10, b: 10), Px.off)
        XCTAssertEqual(Proto.hueByteToRGB(0).0, 255)
        XCTAssertEqual(Proto.hueByteToRGB(Px.off).0, 0)
    }

    func testDecodeStatusColorMode() {
        // power on, mode 1, hue 120, sat 80%, bri 50%
        let payload: [UInt8] = [0, 0, 0, 1, 1, 0, 120, 0x03, 0x20, 0x01, 0xF4]
        let st = Proto.decodeStatus(Proto.build(0x01, payload))
        XCTAssertEqual(st?.mode, 1)
        XCTAssertEqual(st?.hue, 120)
        XCTAssertEqual(st?.saturation, 80)
        XCTAssertEqual(st?.brightness, 50)
        XCTAssertEqual(st?.power, true)
    }

    func testDecodeDeviceInfoAndAck() {
        var p = [UInt8](repeating: 0, count: 27)
        for (i, c) in "1.2.3".utf8.enumerated() { p[i] = c }
        for (i, c) in "Curtain".utf8.enumerated() { p[5 + i] = c }
        p[20] = 0x01; p[21] = 0x90          // 400
        p[22] = 20; p[24] = 20; p[26] = 3
        let info = Proto.decodeDeviceInfo(Proto.build(0x00, p))
        XCTAssertEqual(info?.ledCount, 400)
        XCTAssertEqual(info?.model, "Curtain")
        XCTAssertEqual(info?.isCurtain, true)
        XCTAssertEqual(Proto.ackedCommand(Proto.build(0x02)), 0x02)
        XCTAssertNil(Proto.ackedCommand(Proto.build(0x02, [1])))
    }
}
