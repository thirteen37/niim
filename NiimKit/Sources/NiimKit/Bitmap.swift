import CoreGraphics
import CoreText
import Foundation

public let printheadPx = 96  // D110, 203 dpi = 8 px/mm

/// 1-bit image, true = black.
public struct Bitmap: Equatable, Sendable {
    public let width: Int, height: Int
    public private(set) var pixels: [Bool]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: false, count: width * height)
    }

    public subscript(x: Int, y: Int) -> Bool {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Label as it reads (length × head) → print orientation (head × feed rows).
    public func rotatedCW() -> Bitmap {
        var out = Bitmap(width: height, height: width)
        for y in 0..<width { for x in 0..<height { out[x, y] = self[y, height - 1 - x] } }
        return out
    }

    /// The label as it reads in `orientation`, split into equal sections along its length (first section
    /// at the start end), each with auto-fit, vertically centered text. Pass the same text n times for n-up.
    /// The D110 loses ~1 mm at the start of the feed (calibrated 2026-09-14), so keep margin ≥ 8 px.
    public static func label(_ texts: [String], spec: LabelSpec, orientation: LabelOrientation, style: TextStyle, margin: Int = 12) -> Bitmap {
        let n = max(texts.count, 1), len = spec.rows, head = printheadPx
        let (w, h) = orientation == .landscape ? (len, head) : (head, len)
        var out = Bitmap(width: w, height: h)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return out }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        for (i, text) in texts.enumerated() {
            let section = orientation == .landscape
                ? CGRect(x: len * i / n, y: 0, width: len / n, height: head)
                : CGRect(x: 0, y: len - (i + 1) * len / n, width: head, height: len / n)  // CG is y-up; section 0 on top
            let box = section.insetBy(dx: CGFloat(margin), dy: CGFloat(margin))
            let layout = TextLayout.fit(text, style: style, in: box.size)
            guard let frame = layout.frame else { continue }
            ctx.saveGState()
            ctx.translateBy(x: box.minX, y: box.midY - layout.height / 2)
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()
        }

        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return out }
        for i in 0..<w * h { out.pixels[i] = data[i] < 128 }  // buffer row 0 is the top
        return out
    }

    public var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels.map { $0 ? 0 : 255 }) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 0x85 bitmap rows (MSB first, black counts per third of the head) or 0x84 empty rows; identical rows merged.
    public func rowPackets() -> [Data] {
        let rows = (0..<height).map { y in
            Data(stride(from: 0, to: width, by: 8).map { x in
                (0..<8).reduce(UInt8(0)) { b, i in x + i < width && self[x + i, y] ? b | UInt8(0x80) >> i : b }
            })
        }
        var out: [Data] = [], y = 0
        while y < height {
            var n = 1
            while y + n < height, n < 255, rows[y + n] == rows[y] { n += 1 }
            let row = rows[y]
            if row.contains(where: { $0 != 0 }) {
                let chunk = width / 8 / 3
                let counts = Data((0..<3).map { i in UInt8(row.dropFirst(i * chunk).prefix(chunk).reduce(0) { $0 + $1.nonzeroBitCount }) })
                out.append(Packet.encode(0x85, u16(y) + counts + Data([UInt8(n)]) + row))
            } else {
                out.append(Packet.encode(0x84, u16(y) + Data([UInt8(n)])))
            }
            y += n
        }
        return out
    }
}
