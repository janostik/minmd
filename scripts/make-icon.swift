// Renders the app icon: a white squircle with a large, softly glowing "#" in minmd's link blue.
// Usage: swift scripts/make-icon.swift <output.appiconset>
import AppKit
import CoreImage

let output = URL(fileURLWithPath: CommandLine.arguments[1])

let blue = CGColor(srgbRed: 0x09 / 255, green: 0x69 / 255, blue: 0xDA / 255, alpha: 1)
let lightBlue = CGColor(srgbRed: 0x44 / 255, green: 0x93 / 255, blue: 0xF8 / 255, alpha: 1)

/// The hash as four rounded strokes (two slanted verticals, two horizontals), filled with a gradient.
func hashImage(size s: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let stroke = s * 0.085
    let slant = s * 0.045
    let path = CGMutablePath()
    for x in [s * 0.41, s * 0.59] {
        path.move(to: CGPoint(x: x - slant, y: s * 0.27))
        path.addLine(to: CGPoint(x: x + slant, y: s * 0.73))
    }
    for y in [s * 0.42, s * 0.58] {
        path.move(to: CGPoint(x: s * 0.27, y: y))
        path.addLine(to: CGPoint(x: s * 0.73, y: y))
    }
    context.addPath(path.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 1))
    context.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [blue, lightBlue] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s * 0.27), end: CGPoint(x: 0, y: s * 0.73), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    return context.makeImage()!
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 squircle, with a soft drop shadow.
    let inset = s * 100 / 1024
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03,
                      color: CGColor(gray: 0, alpha: 0.25))
    context.addPath(squircle)
    context.setFillColor(.white)
    context.fillPath()
    context.restoreGState()

    // Background: white, cooling very slightly toward the bottom.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let background = CGGradient(colorsSpace: nil, colors: [
        CGColor(srgbRed: 0.94, green: 0.96, blue: 0.99, alpha: 1), CGColor.white,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])

    // Glow: a blurred copy of the hash, slightly lower, then the crisp hash on top.
    let hash = hashImage(size: s)
    let blurred = CIImage(cgImage: hash)
        .clampedToExtent()
        .applyingGaussianBlur(sigma: Double(s) * 0.045)
        .cropped(to: CGRect(x: 0, y: 0, width: s, height: s))
    let glow = CIContext().createCGImage(blurred, from: blurred.extent)!
    context.setAlpha(0.7)
    context.draw(glow, in: CGRect(x: 0, y: -s * 0.025, width: s, height: s))
    context.setAlpha(1)
    context.draw(hash, in: CGRect(x: 0, y: 0, width: s, height: s))
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
