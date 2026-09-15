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
    public var tailMm: Double  // unprintable cable tail after the print area
    public var areas: [CGRect]  // the template's text areas in mm: x along the length, y down from the top edge
    public var material: String?  // consumableTypeTextId: the material's key in NIIMBOT's language packs (Materials)

    public init(lengthMm: Double, widthMm: Double, tailMm: Double = 0, areas: [CGRect] = [], material: String? = nil) {
        self.lengthMm = lengthMm
        self.widthMm = widthMm
        self.tailMm = tailMm
        self.areas = areas
        self.material = material
    }

    public var rows: Int { Int((lengthMm * 8).rounded()) }

    /// Where die-cut panels meet, in mm along the label: midway between neighbouring text areas.
    /// ponytail: assumes one text area per panel, as on the cable roll; the database has no fold positions.
    public var foldsMm: [Double] {
        let sorted = areas.sorted { $0.minX < $1.minX }
        return zip(sorted, sorted.dropFirst()).map { ($0.maxX + $1.minX) / 2 }
    }

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
        struct Area: Decodable { let x, y, w, h: Double }
        struct Reply: Decodable {
            struct D: Decodable {
                let width, height: Double
                let isCable: Bool?, cableLength: Double?, cableDirection: Int?
                let inputAreas: [Area]?
                let consumableTypeTextId: String?
            }
            let data: D
        }
        let d = try JSONDecoder().decode(Reply.self, from: json).data
        // D110 rolls are ≤15 mm wide, so the long side always runs along the feed.
        return LabelSpec(lengthMm: max(d.width, d.height), widthMm: min(d.width, d.height),
                         tailMm: d.isCable == true && d.cableDirection == 1 ? d.cableLength ?? 0 : 0,  // 1 = after the print area; others unseen
                         // ponytail: areas only from templates stored long side across; transpose them if a tall one turns up
                         areas: d.width >= d.height ? (d.inputAreas ?? []).map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) } : [],
                         material: d.consumableTypeTextId)
    }
}

/// Roll material names from NIIMBOT's public language packs, keyed by the lookup's `consumableTypeTextId`.
/// ponytail: packs are cached forever like fonts; delete Caches/NiimFonts/niimbot-*.json to pick up new names.
public enum Materials {
    static let languages: Set = ["en", "ja", "ko", "de", "fr", "es", "it", "pt", "ru", "zh-cn", "zh-cn-t", "th", "vi", "ar"]

    /// The material's name in the user's language, else English, else NIIMBOT's Chinese description.
    public static func name(textId: String, language: String = Locale.preferredLanguages.first ?? "en") async throws -> String? {
        let lang = pack(for: language)
        var data = [try await download(lang)]
        if lang != "en" { data.append(try await download("en")) }
        return try name(textId, packs: data)
    }

    /// First non-empty translation across the packs, else the first pack's Chinese description.
    static func name(_ id: String, packs: [Data]) throws -> String? {
        struct Entry: Decodable { let value: String?, desc: String? }
        struct Pack: Decodable { let lang: [String: Entry] }
        let entries = try packs.compactMap { try JSONDecoder().decode(Pack.self, from: $0).lang[id] }
        return entries.first { $0.value?.isEmpty == false }?.value ?? entries.first?.desc
    }

    /// NIIMBOT's pack for a language tag, e.g. zh-Hant-TW → zh-cn-t; English when there's none.
    static func pack(for language: String) -> String {
        let tag = language.lowercased()
        if tag.hasPrefix("zh") { return tag.contains("hant") || tag.hasSuffix("-tw") || tag.hasSuffix("-hk") ? "zh-cn-t" : "zh-cn" }
        let code = String(tag.prefix { $0 != "-" })
        return languages.contains(code) ? code : "en"
    }

    static func download(_ pack: String) async throws -> Data {
        try await cached("niimbot-\(pack).json") {
            try await fetch(URL(string: "https://oss-print.niimbot.com/public_resources/static_resources/languagePack/\(pack).json")!)
        }
    }
}
