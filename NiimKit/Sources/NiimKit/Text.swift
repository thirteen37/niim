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

public struct TextStyle {
    public var font: CTFontDescriptor
    public var fallbacks: [CTFontDescriptor]  // tried when `font` lacks a glyph, e.g. Font Awesome
    public var emoji: CTFontDescriptor?  // forced for emoji; mono Noto Emoji thresholds far better than color emoji
    public var alignment: LabelAlignment
    public var wrap: Bool  // false: only the user's own line breaks; text shrinks until the longest line fits
    public var sizeAdjust: CGFloat  // points added to the auto-fit size

    public init(font: CTFontDescriptor = CTFontDescriptorCreateWithNameAndSize("Helvetica-Bold" as CFString, 0),
                fallbacks: [CTFontDescriptor] = [], emoji: CTFontDescriptor? = nil, alignment: LabelAlignment = .center,
                wrap: Bool = true, sizeAdjust: CGFloat = 0) {
        self.font = font
        self.fallbacks = fallbacks
        self.emoji = emoji
        self.alignment = alignment
        self.wrap = wrap
        self.sizeAdjust = sizeAdjust
    }

    func attributed(_ text: String, size: CGFloat) -> NSAttributedString {
        let key = { (k: CFString) in NSAttributedString.Key(k as String) }
        let cascade = CTFontDescriptorCreateCopyWithAttributes(font, [kCTFontCascadeListAttribute as String: fallbacks] as CFDictionary)
        let base = CTFontCreateWithFontDescriptor(cascade, size, nil)
        let emojiFont = emoji.map { CTFontCreateWithFontDescriptor($0, size, nil) }
        let out = NSMutableAttributedString()
        for c in text {
            if let emojiFont, isEmoji(c) {
                // CoreText swaps in Apple Color Emoji for U+FE0F sequences, even with an explicit font
                let mono = String(String.UnicodeScalarView(c.unicodeScalars.filter { $0.value != 0xFE0F }))
                out.append(NSAttributedString(string: mono, attributes: [key(kCTFontAttributeName): emojiFont]))
            } else {
                out.append(NSAttributedString(string: String(c), attributes: [key(kCTFontAttributeName): base]))
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
}

func isEmoji(_ c: Character) -> Bool {
    c.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
}

public struct TextLayout {
    public let size: CGFloat
    public let lines: [String]
    let frame: CTFrame?
    let height: CGFloat

    /// Auto-fit size plus `style.sizeAdjust` (never below 4 pt).
    public static func fit(_ text: String, style: TextStyle, in box: CGSize) -> TextLayout {
        let auto = autoFit(text, style: style, in: box)
        guard style.sizeAdjust != 0 else { return auto }
        // ponytail: nudged text skips the fit checks, so it may re-wrap or overflow; Bitmap.label clips each section
        return layout(text, style, max(4, auto.size + style.sizeAdjust), box, strict: false)!
    }

    /// Largest font size whose text fits `box`, wrapping only between words (or not at all if `style.wrap` is off).
    /// ponytail: binary search assumes fit is monotonic in size; word wrapping makes that approximately true.
    static func autoFit(_ text: String, style: TextStyle, in box: CGSize) -> TextLayout {
        guard var best = layout(text, style, 4, box, strict: true) else {
            return layout(text, style, 4, box, strict: false)!  // too long even at 4pt: break words, let it clip
        }
        var lo: CGFloat = 4, hi = box.height * 1.5
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if let l = layout(text, style, mid, box, strict: true) { best = l; lo = mid } else { hi = mid }
        }
        return best
    }

    static func layout(_ text: String, _ style: TextStyle, _ size: CGFloat, _ box: CGSize, strict: Bool) -> TextLayout? {
        let str = style.attributed(text, size: size)
        let setter = CTFramesetterCreateWithAttributedString(str)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: box.width, height: .greatestFiniteMagnitude), nil)
        if strict, fit.height > box.height { return nil }
        let height = fit.height.rounded(.up) + 1
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: box.width, height: height), transform: nil), nil)
        let ns = str.string as NSString
        let ranges = (CTFrameGetLines(frame) as? [CTLine] ?? []).map { CTLineGetStringRange($0) }
        if strict {
            if !style.wrap, ranges.count > text.components(separatedBy: "\n").count { return nil }  // CoreText wrapped a line
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
