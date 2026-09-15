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

// "T12.5*74+35-60白线缆": two text areas either side of a fold at 37 mm, then a 35 mm unprintable cable tail.
private let cableAreas = [CGRect(x: 2.34, y: 1.375, width: 32.68, height: 9.875), CGRect(x: 38.97, y: 1.375, width: 32.68, height: 9.875)]

@Test func parsesCableLabelTailAndTextAreas() throws {
    let json = #"{"code":1,"data":{"width":74,"height":12.5,"rotate":90,"paperType":1,"isCable":true,"cableLength":35,"cableDirection":1,"consumableTypeTextId":"app100000909","inputAreas":[{"x":2.34,"y":1.375,"w":32.68,"h":9.875,"type":"text"},{"x":38.97,"y":1.375,"w":32.68,"h":9.875,"type":"text"}]}}"#
    let label = try LabelSpec.fromLookup(Data(json.utf8))
    #expect(label == LabelSpec(lengthMm: 74, widthMm: 12.5, tailMm: 35, areas: cableAreas, material: "app100000909"))
    #expect(label.foldsMm.count == 1 && abs(label.foldsMm[0] - 37) < 0.01)  // midway between the two areas
}

@Test func sectionsFollowTheLabelsTextAreas() {
    let spec = LabelSpec(lengthMm: 74, widthMm: 12.5, areas: cableAreas)  // areas end at 280 px, next starts at 312 px
    func inked(_ bmp: Bitmap, along xs: Range<Int>) -> Bool {
        bmp.width > bmp.height
            ? xs.contains { x in (0..<bmp.height).contains { bmp[x, $0] } }
            : xs.contains { y in (0..<bmp.width).contains { bmp[$0, y] } }
    }
    let land = Bitmap.label(["I", "I"], spec: spec, orientation: .landscape, style: TextStyle())
    #expect(inked(land, along: 19..<280) && !inked(land, along: 280..<312) && inked(land, along: 312..<573))
    let port = Bitmap.label(["I", ""], spec: spec, orientation: .portrait, style: TextStyle())
    #expect(inked(port, along: 19..<280) && !inked(port, along: 280..<592))  // first area at the start end, on top
    let one = Bitmap.label(["I"], spec: spec, orientation: .landscape, style: TextStyle())
    #expect(inked(one, along: 280..<312))  // section count doesn't match the areas: even split, text centred on the fold
}

@Test func namesMaterialsFromLanguagePacks() throws {
    let pack = { (json: String) in Data(json.utf8) }
    let ja = pack(#"{"version":1,"lang":{"app100000062":{"value":"透明感熱紙","desc":"透明热敏"},"app9":{"value":"","desc":"热敏"}}}"#)
    let en = pack(#"{"version":1,"lang":{"app100000062":{"value":"Transparent Thermal Paper","desc":"透明热敏"},"app9":{"value":"Thermal","desc":"热敏"}}}"#)
    #expect(try Materials.name("app100000062", packs: [ja, en]) == "透明感熱紙")
    #expect(try Materials.name("app9", packs: [ja, en]) == "Thermal")  // untranslated: English
    #expect(try Materials.name("app9", packs: [ja]) == "热敏")  // nothing translated: NIIMBOT's Chinese description
    #expect(try Materials.name("missing", packs: [ja, en]) == nil)
    #expect(Materials.pack(for: "ja-JP") == "ja" && Materials.pack(for: "zh-Hant-TW") == "zh-cn-t"
        && Materials.pack(for: "zh-Hans-SG") == "zh-cn" && Materials.pack(for: "id-ID") == "en")
}
