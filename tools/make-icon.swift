// Builds the PNGs in App/Assets.xcassets/AppIcon.appiconset from tools/niim-logo.png (orange wordmark on light gray):
// white wordmark on the logo's orange. iOS: opaque full-bleed square. macOS: rounded tile on the 824/1024 grid.
// Usage (from the repo root): swift tools/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let logo = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent("tools/niim-logo.png") as CFURL, nil)!, 0, nil)!
let (w, h) = (logo.width, logo.height)

// Raw values, no color management: the logo is an untagged palette PNG, which CoreGraphics treats as
// Display P3 and oversaturates when converting to sRGB (#F44841 became #FF3035).
let rgb: [UInt8] = {
    let bytes = [UInt8](logo.dataProvider!.data! as Data)
    if let table = logo.colorSpace?.colorTable {
        return (0..<h).flatMap { y in (0..<w).flatMap { x -> [UInt8] in
            let i = Int(bytes[y * logo.bytesPerRow + x]) * 3
            return Array(table[i..<i + 3])
        }}
    }
    let n = logo.bitsPerPixel / 8
    return (0..<h).flatMap { y in (0..<w).flatMap { x -> [UInt8] in
        let i = y * logo.bytesPerRow + x * n
        return Array(bytes[i..<i + 3])
    }}
}()
func channel(_ i: Int, _ c: Int) -> Double { Double(rgb[i * 3 + c]) }

// Letters are orange (low green), background light gray (high green). Use the median letter color, not the darkest
// pixel: edge outliers made the mask top out at ~84% and the white letters pink.
let bgG = channel(0, 1)
let ink = (0..<w * h).filter { channel($0, 1) < bgG - 100 }
let inkColor = (0..<3).map { c in ink.map { channel($0, c) }.sorted()[ink.count / 2] }
let orange = CGColor(srgbRed: inkColor[0] / 255, green: inkColor[1] / 255, blue: inkColor[2] / 255, alpha: 1)

var alpha = [UInt8](repeating: 0, count: w * h)
var (minX, minY, maxX, maxY) = (w, h, 0, 0)
for y in 0..<h { for x in 0..<w {
    let a = min(1, max(0, (bgG - channel(y * w + x, 1)) / (bgG - inkColor[1])))
    alpha[y * w + x] = UInt8(a * 255)
    if a > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
}}
let (mw, mh) = (maxX - minX + 1, maxY - minY + 1)
print(String(format: "orange #%02X%02X%02X, wordmark %dx%d", Int(inkColor[0]), Int(inkColor[1]), Int(inkColor[2]), mw, mh))

let gray = CGColorSpaceCreateDeviceGray()
let smallMask = CGImage(width: mw, height: mh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: mw, space: gray, bitmapInfo: CGBitmapInfo(),
                        provider: CGDataProvider(data: Data((minY...maxY).flatMap { y in (minX...maxX).map { alpha[y * w + $0] } }) as CFData)!,
                        decode: nil, shouldInterpolate: true, intent: .defaultIntent)!

/// The wordmark mask enlarged to exactly `width`×`height`, re-sharpened (smoothstep 0.35–0.65) so upscaling doesn't blur it.
func mask(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: gray,
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(smallMask, in: CGRect(x: 0, y: 0, width: width, height: height))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for i in 0..<width * height {
        let t = min(1, max(0, (Double(p[i]) / 255 - 0.35) / 0.3))
        p[i] = UInt8(t * t * (3 - 2 * t) * 255)
    }
    return ctx.makeImage()!
}

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func icon(mac: Bool) -> CGImage {
    let s = 1024
    let out = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: s * 4, space: srgb,
                        bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    let tile = mac ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: s, height: s)
    out.setFillColor(orange)
    if mac {
        out.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
        out.fillPath()
    } else {
        out.fill(tile)
    }
    let markW = Int(tile.width * 0.72), markH = Int(tile.width * 0.72 * CGFloat(mh) / CGFloat(mw))
    let rect = CGRect(x: Int(tile.midX) - markW / 2, y: Int(tile.midY) - markH / 2, width: markW, height: markH)
    out.clip(to: rect, mask: mask(width: markW, height: markH))
    out.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    out.fill(rect)
    return out.makeImage()!
}

func save(_ image: CGImage, _ name: String, size: Int = 1024) {
    var image = image
    if size != 1024 {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        image = ctx.makeImage()!
    }
    let url = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/\(name)")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

save(icon(mac: false), "ios-1024.png")
let mac = icon(mac: true)
for size in [16, 32, 64, 128, 256, 512, 1024] { save(mac, "mac-\(size).png", size: size) }
