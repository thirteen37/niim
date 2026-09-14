import CoreGraphics
import CoreText
import Foundation

public enum LabelAlignment: String, CaseIterable, Sendable {
    case left, center, right

    var ct: CTTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

/// How the label is held when read: landscape = start end on the left, portrait = start end on top.
public enum LabelOrientation: String, CaseIterable, Sendable {
    case landscape, portrait
}

extension Bitmap {
    /// Rows for the printer (head × feed). A portrait canvas already is that; landscape rotates.
    public func forPrinting(_ orientation: LabelOrientation) -> Bitmap {
        orientation == .landscape ? rotatedCW() : self
    }
}

/// A run of label text with its own styling.
public struct TextRun: Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }
}

public struct TextStyle {
    public var faces: FontFaces
    public var fallbacks: [CTFontDescriptor]  // tried when a face lacks a glyph, e.g. Font Awesome
    public var emoji: CTFontDescriptor?  // forced for emoji; mono Noto Emoji thresholds far better than color emoji
    public var alignment: LabelAlignment
    public var wrap: Bool  // false: only the user's own line breaks; text shrinks until the longest line fits
    public var sizeAdjust: CGFloat  // points added to the auto-fit size

    public init(faces: FontFaces = .system(family: "Helvetica"), fallbacks: [CTFontDescriptor] = [], emoji: CTFontDescriptor? = nil,
                alignment: LabelAlignment = .center, wrap: Bool = true, sizeAdjust: CGFloat = 0) {
        self.faces = faces
        self.fallbacks = fallbacks
        self.emoji = emoji
        self.alignment = alignment
        self.wrap = wrap
        self.sizeAdjust = sizeAdjust
    }

    func attributed(_ spans: [TextRun], size: CGFloat) -> NSAttributedString {
        let key = { (k: CFString) in NSAttributedString.Key(k as String) }
        let emojiFont = emoji.map { CTFontCreateWithFontDescriptor($0, size, nil) }
        let out = NSMutableAttributedString()
        for span in spans {
            var attrs = fontAttributes(bold: span.bold, italic: span.italic, size: size)
            if span.underline { attrs[key(kCTUnderlineStyleAttributeName)] = CTUnderlineStyle.single.rawValue }
            for c in span.text {
                if let emojiFont, isEmoji(c) {
                    var e = attrs
                    e[key(kCTFontAttributeName)] = emojiFont
                    e[key(kCTStrokeWidthAttributeName)] = nil
                    // CoreText swaps in Apple Color Emoji for U+FE0F sequences, even with an explicit font
                    let mono = String(String.UnicodeScalarView(c.unicodeScalars.filter { $0.value != 0xFE0F }))
                    out.append(NSAttributedString(string: mono, attributes: e))
                } else {
                    out.append(NSAttributedString(string: String(c), attributes: attrs))
                }
            }
        }
        var align = alignment.ct
        let para = withUnsafePointer(to: &align) {
            CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: $0)], 1)
        }
        out.addAttributes([key(kCTParagraphStyleAttributeName): para, key(kCTForegroundColorAttributeName): CGColor(gray: 0, alpha: 1)],
                          range: NSRange(location: 0, length: out.length))
        return out
    }

    /// The family's face for bold/italic, synthesizing whatever it lacks: a skew for italic, a fill+stroke for bold.
    private func fontAttributes(bold: Bool, italic: Bool, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let desc = CTFontDescriptorCreateCopyWithAttributes(faces.descriptor(bold: bold, italic: italic),
                                                            [kCTFontCascadeListAttribute as String: fallbacks] as CFDictionary)
        var font = CTFontCreateWithFontDescriptor(desc, size, nil)
        let traits = CTFontGetSymbolicTraits(font)
        if italic, !traits.contains(.traitItalic) {
            var skew = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)  // ~11° oblique
            font = CTFontCreateWithFontDescriptor(desc, size, &skew)
        }
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        if bold, !traits.contains(.traitBold) {
            attrs[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = CGFloat(-3)  // stroke 3% of size around the fill
        }
        return attrs
    }
}

func isEmoji(_ c: Character) -> Bool {
    c.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
}

public struct TextLayout {
    public let size: CGFloat
    public let lines: [String]
    let frame: CTFrame?
    let height: CGFloat

    public static func fit(_ text: String, style: TextStyle, in box: CGSize) -> TextLayout {
        fit([TextRun(text)], style: style, in: box)
    }

    /// Auto-fit size plus `style.sizeAdjust` (never below 4 pt).
    public static func fit(_ spans: [TextRun], style: TextStyle, in box: CGSize) -> TextLayout {
        let auto = autoFit(spans, style: style, in: box)
        guard style.sizeAdjust != 0 else { return auto }
        // ponytail: nudged text skips the fit checks, so it may re-wrap or overflow; Bitmap.label clips each section
        return layout(spans, style, max(4, auto.size + style.sizeAdjust), box, strict: false)!
    }

    /// Largest font size whose text fits `box`, wrapping only between words (or not at all if `style.wrap` is off).
    /// ponytail: binary search assumes fit is monotonic in size; word wrapping makes that approximately true.
    static func autoFit(_ spans: [TextRun], style: TextStyle, in box: CGSize) -> TextLayout {
        guard var best = layout(spans, style, 4, box, strict: true) else {
            return layout(spans, style, 4, box, strict: false)!  // too long even at 4pt: break words, let it clip
        }
        var lo: CGFloat = 4, hi = box.height * 1.5
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if let l = layout(spans, style, mid, box, strict: true) { best = l; lo = mid } else { hi = mid }
        }
        return best
    }

    static func layout(_ spans: [TextRun], _ style: TextStyle, _ size: CGFloat, _ box: CGSize, strict: Bool) -> TextLayout? {
        let str = style.attributed(spans, size: size)
        let setter = CTFramesetterCreateWithAttributedString(str)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: box.width, height: .greatestFiniteMagnitude), nil)
        if strict, fit.height > box.height { return nil }
        let height = fit.height.rounded(.up) + 1
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: box.width, height: height), transform: nil), nil)
        let ns = str.string as NSString
        let ranges = (CTFrameGetLines(frame) as? [CTLine] ?? []).map { CTLineGetStringRange($0) }
        if strict {
            let manualLines = spans.map(\.text).joined().components(separatedBy: "\n").count
            if !style.wrap, ranges.count > manualLines { return nil }  // CoreText wrapped a line
            // a line may only end in whitespace; anything else means CoreText broke a word
            for r in ranges.dropLast() {
                guard let ch = Unicode.Scalar(ns.character(at: r.location + r.length - 1)),
                      CharacterSet.whitespacesAndNewlines.contains(ch) else { return nil }
            }
        }
        let lines = ranges.map { ns.substring(with: NSRange(location: $0.location, length: $0.length)) }
        return TextLayout(size: size, lines: lines, frame: frame, height: height)
    }
}
