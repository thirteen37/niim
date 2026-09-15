import CoreText
import Foundation

// Fonts are fetched on first use and cached forever.
// ponytail: no cache expiry; delete Caches/NiimFonts to pick up new Google Fonts or Font Awesome releases.

/// A family's faces. Missing ones fall back to the nearest face and are synthesized when drawn (TextStyle).
public struct FontFaces {
    public var regular: CTFontDescriptor
    public var bold: CTFontDescriptor?
    public var italic: CTFontDescriptor?
    public var boldItalic: CTFontDescriptor?

    public init(regular: CTFontDescriptor, bold: CTFontDescriptor? = nil, italic: CTFontDescriptor? = nil, boldItalic: CTFontDescriptor? = nil) {
        self.regular = regular
        self.bold = bold
        self.italic = italic
        self.boldItalic = boldItalic
    }

    public static func system(family: String) -> FontFaces {
        let d = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: family] as CFDictionary)
        func face(_ traits: CTFontSymbolicTraits) -> CTFontDescriptor? {
            // Concurrent trait lookups from Swift Testing's parallel runner hang in the font service; one at a time is instant.
            traitLookupLock.lock()
            defer { traitLookupLock.unlock() }
            return CTFontDescriptorCreateCopyWithSymbolicTraits(d, traits, traits)
        }
        return FontFaces(regular: d, bold: face(.traitBold), italic: face(.traitItalic), boldItalic: face([.traitBold, .traitItalic]))
    }

    func descriptor(bold wantBold: Bool, italic wantItalic: Bool) -> CTFontDescriptor {
        switch (wantBold, wantItalic) {
        case (false, false): regular
        case (true, false): bold ?? regular
        case (false, true): italic ?? regular
        case (true, true): boldItalic ?? bold ?? italic ?? regular
        }
    }
}

public struct GoogleFamily: Hashable, Sendable, Identifiable {
    public let name: String
    public let category: String
    public let hasBold: Bool
    public var id: String { name }
}

public enum GoogleFonts {
    public static func families() async throws -> [GoogleFamily] {
        try families(fromMetadata: try await cached("google-fonts.json") { try await fetch(URL(string: "https://fonts.google.com/metadata/fonts")!) })
    }

    /// Regular plus whichever bold/italic faces the family has.
    /// ponytail: failed face requests aren't cached, so families lacking a face re-ask Google each time they're picked.
    public static func faces(family: String) async throws -> FontFaces {
        async let bold = try? font(family: family, bold: true, italic: false)
        async let italic = try? font(family: family, bold: false, italic: true)
        async let boldItalic = try? font(family: family, bold: true, italic: true)
        return FontFaces(regular: try await font(family: family, bold: false, italic: false),
                         bold: await bold, italic: await italic, boldItalic: await boldItalic)
    }

    /// One face; throws if the family doesn't have it.
    public static func font(family: String, bold: Bool, italic: Bool) async throws -> CTFontDescriptor {
        let suffix = (bold ? "-700" : "") + (italic ? "-italic" : "")
        return try descriptor(try await cached("gf-\(family)\(suffix).font") {
            let css = String(decoding: try await fetch(cssURL(family: family, bold: bold, italic: italic)), as: UTF8.self)
            guard let url = fontURL(fromCSS: css) else { throw NiimError("No font file for \(family)") }
            return try await fetch(url)
        })
    }

    static func families(fromMetadata data: Data) throws -> [GoogleFamily] {
        struct Empty: Decodable {}
        struct Family: Decodable { let family: String; let category: String; let fonts: [String: Empty] }
        struct Metadata: Decodable { let familyMetadataList: [Family] }
        return try JSONDecoder().decode(Metadata.self, from: data).familyMetadataList.map {
            GoogleFamily(name: $0.family, category: $0.category, hasBold: $0.fonts["700"] != nil)
        }
    }

    static func cssURL(family: String, bold: Bool, italic: Bool = false) -> URL {
        var c = URLComponents(string: "https://fonts.googleapis.com/css2")!
        let name = (family.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? family).replacingOccurrences(of: "%20", with: "+")
        let axes = switch (bold, italic) {
        case (false, false): ""
        case (true, false): ":wght@700"
        case (false, true): ":ital@1"
        case (true, true): ":ital,wght@1,700"
        }
        c.percentEncodedQuery = "family=\(name)\(axes)"
        return c.url!
    }

    /// First font file in a css2 response (TTF for most clients, WOFF2 for some; CoreText reads both).
    static func fontURL(fromCSS css: String) -> URL? {
        guard let r = css.range(of: #"url\(https://[^)]+\)"#, options: .regularExpression) else { return nil }
        return URL(string: String(css[r].dropFirst(4).dropLast()))
    }
}

public struct Icon: Hashable, Sendable, Identifiable {
    public let name: String
    public let character: Character
    public let brand: Bool
    public var id: String { brand ? "brand-\(name)" : name }
}

public enum FontAwesome {
    static let base = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@7.3.1/"

    /// Free icons, plus the [Solid, Brands] fonts to use as `TextStyle.fallbacks`.
    /// ponytail: Solid and Brands share one fallback cascade, so a codepoint in both renders as Solid.
    public static func load() async throws -> (icons: [Icon], fonts: [CTFontDescriptor]) {
        func get(_ path: String) async throws -> Data {
            try await cached("fa-7.3.1-" + path.replacingOccurrences(of: "/", with: "-")) { try await fetch(URL(string: base + path)!) }
        }
        let solid = icons(fromCSS: String(decoding: try await get("css/fontawesome.css"), as: UTF8.self), brand: false)
        let brands = icons(fromCSS: String(decoding: try await get("css/brands.css"), as: UTF8.self), brand: true)
        let fonts = [try descriptor(try await get("webfonts/fa-solid-900.woff2")), try descriptor(try await get("webfonts/fa-brands-400.woff2"))]
        var seen = Set<String>()
        return ((solid + brands).filter { seen.insert($0.id).inserted }, fonts)
    }

    static func icons(fromCSS css: String, brand: Bool) -> [Icon] {
        let re = try! NSRegularExpression(pattern: #"\.fa-([a-z0-9-]+) \{\s*--fa: "\\([0-9a-f]+) ?";"#)
        return re.matches(in: css, range: NSRange(css.startIndex..., in: css)).compactMap { m in
            guard let name = Range(m.range(at: 1), in: css), let hex = Range(m.range(at: 2), in: css),
                  let value = UInt32(css[hex], radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
            return Icon(name: String(css[name]), character: Character(scalar), brand: brand)
        }
    }
}

public func systemFontFamilies() -> [String] {
    let descs = CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionCreateFromAvailableFonts(nil)) as? [CTFontDescriptor] ?? []
    return Set(descs.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String })
        .filter { !$0.hasPrefix(".") }
        .sorted()
}

private let traitLookupLock = NSLock()

private let cacheDir: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("NiimFonts")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

func cached(_ name: String, _ load: () async throws -> Data) async throws -> Data {
    let file = cacheDir.appendingPathComponent(name)
    if let data = try? Data(contentsOf: file) { return data }
    let data = try await load()
    try? data.write(to: file)
    return data
}

func fetch(_ url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NiimError("Download failed: \(url.lastPathComponent)") }
    return data
}

private func descriptor(_ data: Data) throws -> CTFontDescriptor {
    guard let d = CTFontManagerCreateFontDescriptorFromData(data as CFData) else { throw NiimError("Unreadable font file") }
    return d
}
