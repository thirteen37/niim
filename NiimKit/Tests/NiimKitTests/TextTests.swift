import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import NiimKit

private let box = CGSize(width: 216, height: 72)  // 30mm label minus 12px margins
private let sentence = "The quick brown fox jumps over the lazy dog"

@Test func shorterTextGetsBiggerFont() {
    #expect(TextLayout.fit("Hi", style: TextStyle(), in: box).size > TextLayout.fit(sentence, style: TextStyle(), in: box).size)
}

@Test func wrapsAtSpacesNotMidWord() {
    let layout = TextLayout.fit(sentence, style: TextStyle(), in: box)
    #expect(layout.lines.count > 1)
    #expect(layout.lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") == sentence)
}

private func font(_ s: NSAttributedString, at i: Int) -> CTFont {
    s.attribute(.init(kCTFontAttributeName as String), at: i, effectiveRange: nil) as! CTFont
}

@Test func spansUseRealFacesAndUnderline() {
    let s = TextStyle(faces: .system(family: "Helvetica"))
        .attributed([TextRun("a", bold: true), TextRun("b", italic: true), TextRun("c", underline: true), TextRun("d")], size: 20)
    #expect(CTFontGetSymbolicTraits(font(s, at: 0)).contains(.traitBold))
    #expect(CTFontGetSymbolicTraits(font(s, at: 1)).contains(.traitItalic))
    #expect(s.attribute(.init(kCTUnderlineStyleAttributeName as String), at: 2, effectiveRange: nil) != nil)
    #expect(s.attribute(.init(kCTUnderlineStyleAttributeName as String), at: 3, effectiveRange: nil) == nil)
    #expect(s.attribute(.init(kCTStrokeWidthAttributeName as String), at: 0, effectiveRange: nil) == nil)  // real bold, no synth
}

@Test func synthesizesMissingBoldAndItalic() {
    let s = TextStyle(faces: .system(family: "Zapfino")).attributed([TextRun("a", bold: true), TextRun("b", italic: true)], size: 20)  // no bold/italic faces
    #expect(((s.attribute(.init(kCTStrokeWidthAttributeName as String), at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0) < 0)
    #expect(CTFontGetMatrix(font(s, at: 1)).c != 0)
}

@Test func manualLineBreaksCountAcrossTextRuns() {
    let spans = [TextRun("The quick brown fox "), TextRun("jumps over the lazy dog", bold: true)]
    #expect(TextLayout.fit(spans, style: TextStyle(wrap: false), in: box).lines.count == 1)
}

@Test func googleCSSURLsForStyles() {
    #expect(GoogleFonts.cssURL(family: "Roboto", bold: false, italic: true).absoluteString == "https://fonts.googleapis.com/css2?family=Roboto:ital@1")
    #expect(GoogleFonts.cssURL(family: "Roboto", bold: true, italic: true).absoluteString == "https://fonts.googleapis.com/css2?family=Roboto:ital,wght@1,700")
}

@Test func nudgeAdjustsAutoFitSize() {
    let auto = TextLayout.fit("Hello", style: TextStyle(), in: box).size
    #expect(TextLayout.fit("Hello", style: TextStyle(sizeAdjust: -3), in: box).size == auto - 3)
    #expect(TextLayout.fit("Hello", style: TextStyle(sizeAdjust: 5), in: box).size == auto + 5)
    #expect(TextLayout.fit("Hello", style: TextStyle(sizeAdjust: -500), in: box).size == 4)
}

@Test func nudgedUpTextStaysInItsSection() {
    let bmp = Bitmap.label(["W W W W", ""], spec: LabelSpec(lengthMm: 30, widthMm: 15), orientation: .portrait, style: TextStyle(sizeAdjust: 40), margin: 12)
    let inked = { (ys: Range<Int>) in ys.contains { y in (0..<bmp.width).contains { bmp[$0, y] } } }
    #expect(inked(0..<120) && !inked(120..<240))
}

@Test func onlyManualLineBreaksWhenWrapIsOff() {
    #expect(TextLayout.fit(sentence, style: TextStyle(wrap: false), in: box).lines == [sentence])
    #expect(TextLayout.fit("A\nB", style: TextStyle(wrap: false), in: box).lines.count == 2)
}

@Test func keepsExplicitNewlines() {
    #expect(TextLayout.fit("A\nB", style: TextStyle(), in: box).lines.map { $0.trimmingCharacters(in: .newlines) } == ["A", "B"])
}

@Test(arguments: LabelAlignment.allCases)
func alignsInsideMargins(_ alignment: LabelAlignment) throws {
    let bmp = Bitmap.label(["I"], spec: LabelSpec(lengthMm: 30, widthMm: 15), orientation: .landscape, style: TextStyle(alignment: alignment), margin: 12)
    let xs = (0..<bmp.width).filter { x in (0..<bmp.height).contains { bmp[x, $0] } }
    let ys = (0..<bmp.height).filter { y in (0..<bmp.width).contains { bmp[$0, y] } }
    let (minX, maxX) = (try #require(xs.min()), try #require(xs.max()))
    #expect(minX >= 12 && maxX < 228 && ys.min()! >= 12 && ys.max()! < 84)
    switch alignment {
    case .left: #expect(minX < 24)
    case .right: #expect(maxX > 216)
    case .center: #expect(abs((minX + maxX) / 2 - 120) <= 4)
    }
}

@Test func nUpRepeatsTextInEachSection() {
    let bmp = Bitmap.label(["I", "I"], spec: LabelSpec(lengthMm: 30, widthMm: 15), orientation: .landscape, style: TextStyle(), margin: 12)
    let inked = { (xs: Range<Int>) in xs.contains { x in (0..<bmp.height).contains { bmp[x, $0] } } }
    #expect(inked(0..<100) && !inked(100..<140) && inked(140..<240))
}

@Test func portraitStacksSectionsFromStartEnd() {
    let bmp = Bitmap.label(["I", ""], spec: LabelSpec(lengthMm: 30, widthMm: 15), orientation: .portrait, style: TextStyle(), margin: 12)
    #expect(bmp.width == 96 && bmp.height == 240)
    let inked = { (ys: Range<Int>) in ys.contains { y in (0..<bmp.width).contains { bmp[$0, y] } } }
    #expect(inked(0..<120) && !inked(120..<240))
    #expect(bmp.forPrinting(.portrait) == bmp)
    #expect(bmp.forPrinting(.landscape).width == 240)
}

@Test func detectsEmojiClusters() {
    #expect(["🙂", "👍🏽", "❤️", "1️⃣", "👨‍👩‍👧"].allSatisfy(isEmoji))
    #expect(!["A", "1", "✓", "\u{F015}"].contains(where: isEmoji))
}

@Test func parsesGoogleFontsMetadata() throws {
    let json = #"{"axisRegistry":[],"familyMetadataList":[{"family":"ABeeZee","category":"Sans Serif","fonts":{"400":{},"400i":{}}},{"family":"Roboto","category":"Sans Serif","fonts":{"400":{},"700":{}}}]}"#
    #expect(try GoogleFonts.families(fromMetadata: Data(json.utf8)) == [
        GoogleFamily(name: "ABeeZee", category: "Sans Serif", hasBold: false),
        GoogleFamily(name: "Roboto", category: "Sans Serif", hasBold: true),
    ])
}

@Test func findsTTFInGoogleCSS() {
    let css = """
    @font-face {
      font-family: 'Roboto';
      src: url(https://fonts.gstatic.com/s/roboto/v51/KFOM.ttf) format('truetype');
    }
    """
    #expect(GoogleFonts.fontURL(fromCSS: css) == URL(string: "https://fonts.gstatic.com/s/roboto/v51/KFOM.ttf"))
    #expect(GoogleFonts.cssURL(family: "Noto Emoji", bold: true).absoluteString
        == "https://fonts.googleapis.com/css2?family=Noto+Emoji:wght@700")
}

@Test func parsesFontAwesomeCSS() {
    let css = ".fa-heart {\n  --fa: \"\\f004\";\n}\n\n.fa-house {\n  --fa: \"\\f015\";\n}\n.fa-0 {\n  --fa: \"\\30 \";\n}\n.fa-solid {\n  --fa-style: 900;\n}\n"
    #expect(FontAwesome.icons(fromCSS: css, brand: false) == [
        Icon(name: "heart", character: "\u{F004}", brand: false),
        Icon(name: "house", character: "\u{F015}", brand: false),
        Icon(name: "0", character: "0", brand: false),
    ])
}
