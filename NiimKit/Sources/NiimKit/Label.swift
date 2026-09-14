import Foundation

/// RFID tag on the loaded roll (reply to cmd 0x1A). Has no dimensions; use `LabelSpec.lookup`.
public struct Rfid: Equatable, Sendable {
    public let barcode: String, serial: String
    public let total: Int, used: Int, labelType: UInt8

    public init?(_ data: Data) {
        let b = [UInt8](data)
        var i = 8  // skip 8-byte uuid
        var strs: [String] = []
        for _ in 0..<2 {  // barcode, serial: length-prefixed
            guard i < b.count, i + 1 + Int(b[i]) <= b.count else { return nil }
            strs.append(String(decoding: b[(i + 1)..<(i + 1 + Int(b[i]))], as: UTF8.self))
            i += 1 + Int(b[i])
        }
        guard i + 5 <= b.count else { return nil }
        barcode = strs[0]
        serial = strs[1]
        total = Int(b[i]) << 8 | Int(b[i + 1])
        used = Int(b[i + 2]) << 8 | Int(b[i + 3])
        labelType = b[i + 4]
    }
}

public struct LabelSpec: Equatable, Sendable {
    public var lengthMm: Double  // along the feed
    public var widthMm: Double  // across the head; only the middle 12 mm prints

    public init(lengthMm: Double, widthMm: Double) {
        self.lengthMm = lengthMm
        self.widthMm = widthMm
    }

    public var rows: Int { Int((lengthMm * 8).rounded()) }

    /// Niimbot's public label database, keyed by the RFID barcode. No auth.
    public static func lookup(barcode: String) async throws -> LabelSpec {
        var req = URLRequest(url: URL(string: "https://print.niimbot.com/api/template/getCloudTemplateByOneCode")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("AppVersionName/999.0.0", forHTTPHeaderField: "niimbot-user-agent")
        req.httpBody = try JSONEncoder().encode(["oneCode": barcode])
        return try fromLookup(try await URLSession.shared.data(for: req).0)
    }

    static func fromLookup(_ json: Data) throws -> LabelSpec {
        struct Reply: Decodable { struct D: Decodable { let width, height: Double }; let data: D }
        let d = try JSONDecoder().decode(Reply.self, from: json).data
        // D110 rolls are ≤15 mm wide, so the long side always runs along the feed.
        return LabelSpec(lengthMm: max(d.width, d.height), widthMm: min(d.width, d.height))
    }
}
