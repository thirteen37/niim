import Foundation
import Testing
@testable import NiimKit

// Vectors mirror niim.py's selftest, which printed correctly on a real D110.

private func hex(_ s: String) -> Data {
    Data(stride(from: 0, to: s.count, by: 2).map {
        UInt8(s[s.index(s.startIndex, offsetBy: $0)..<s.index(s.startIndex, offsetBy: $0 + 2)], radix: 16)!
    })
}

@Test func encodesPacket() {
    #expect(Packet.encode(0x40, Data([0x08])) == hex("555540010849aaaa"))
    #expect(Packet.encode(0xC1) == Packet.encode(0xC1, Data([0x01])))  // default payload is [1]
}

@Test func decoderHandlesSplitAndMergedNotifications() {
    var dec = PacketDecoder()
    let second = Packet.encode(0x49, Data([0x01]))
    #expect(dec.push(Packet.encode(0x48, Data([0x09, 0x00])) + second.prefix(3)) == [Packet(cmd: 0x48, data: Data([0x09, 0x00]))])
    #expect(dec.push(second.dropFirst(3)) == [Packet(cmd: 0x49, data: Data([0x01]))])
}

@Test func encodesRowsWithRepeatsAndEmptyRows() {
    var bmp = Bitmap(width: 96, height: 4)
    for y in [1, 2] { bmp[0, y] = true; bmp[95, y] = true }
    let row = Data([0x80] + [UInt8](repeating: 0, count: 10) + [0x01])  // MSB first
    #expect(bmp.rowPackets() == [
        Packet.encode(0x84, Data([0, 0, 1])),
        Packet.encode(0x85, Data([0, 1, 1, 0, 1, 2]) + row),  // pos, per-third black counts, repeat
        Packet.encode(0x84, Data([0, 3, 1])),
    ])
}

@Test func rotatesLandscapeClockwiseForFeed() {
    var land = Bitmap(width: 240, height: 96)
    land[0, 0] = true  // top-left as the label reads
    let feed = land.rotatedCW()
    #expect(feed.width == 96 && feed.height == 240)
    #expect(feed[95, 0])  // first fed row, far end of the head (matches niim.py's PIL ROTATE_270)
}

@Test func rendersTextInsideStartMargin() {
    let bmp = Bitmap.label(["HI"], spec: LabelSpec(lengthMm: 30, widthMm: 15), orientation: .landscape, style: TextStyle(), margin: 12)
    #expect(bmp.width == 240 && bmp.height == 96)
    #expect(bmp.pixels.contains(true))
    #expect((0..<96).allSatisfy { y in (0..<12).allSatisfy { !bmp[$0, y] } })
}

@Test func parsesRfidFromRealRoll() throws {
    let rfid = try #require(Rfid(hex("881dd978f58c000008303232383232383010505a314733313133333030303334373300fc002801")))
    #expect(rfid.barcode == "02282280")
    #expect(rfid.serial == "PZ1G311330003473")
    #expect(rfid.total == 252 && rfid.used == 40 && rfid.labelType == 1)
    #expect(Rfid(Data([0x00])) == nil)  // no tag
}

@Test func parsesCloudLabelLookup() throws {
    let json = #"{"code":1,"data":{"barcode":"02282280","name":"T15*30-210","width":30,"height":15,"rotate":90,"paperType":1}}"#
    let label = try LabelSpec.fromLookup(Data(json.utf8))
    #expect(label == LabelSpec(lengthMm: 30, widthMm: 15))
    #expect(label.rows == 240)  // 8 px/mm along the feed; printable width is always the 96 px head
}
