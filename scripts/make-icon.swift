// Renders the app icon: a white squircle with a large, softly glowing "#" in minmd's link blue.
// Usage: swift scripts/make-icon.swift <output.appiconset> [scripts/icon.json]
// The parameters match the icon tuner page; all lengths are fractions of the icon size.
import AppKit
import CoreImage

struct Params: Codable {
    var size = 0.9          // hash scale around the center
    var stroke = 0.085      // stroke width
    var slant = 0.045       // horizontal lean of the vertical strokes (each end)
    var gapX = 0.18         // distance between the two vertical strokes
    var gapY = 0.16         // distance between the two horizontal strokes
    var length = 0.46       // length of every stroke
    var glowBlur = 0.045    // blur radius (sigma) of the glow
    var glowOpacity = 0.7
    var glowOffset = 0.025  // how far the glow sits below the hash
    var colorTop = "#4493F8"
    var colorBottom = "#0969DA"
    var bgTop = "#FFFFFF"
    var bgBottom = "#F0F5FC"
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let params: Params = CommandLine.arguments.count > 2
    ? try! JSONDecoder().decode(Params.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    : Params()

func color(_ hex: String) -> CGColor {
    let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

/// The hash as four rounded strokes (two slanted verticals, two horizontals), filled with a gradient.
func hashImage(size s: CGFloat) -> CGImage {
    let p = params
    let context = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Unit coordinates (y up), scaled around the center by `size`.
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (0.5 + (x - 0.5) * p.size) * s, y: (0.5 + (y - 0.5) * p.size) * s)
    }
    let half = p.length / 2
    let path = CGMutablePath()
    for x in [0.5 - p.gapX / 2, 0.5 + p.gapX / 2] {
        path.move(to: point(x - p.slant, 0.5 - half))
        path.addLine(to: point(x + p.slant, 0.5 + half))
    }
    for y in [0.5 - p.gapY / 2, 0.5 + p.gapY / 2] {
        path.move(to: point(0.5 - half, y))
        path.addLine(to: point(0.5 + half, y))
    }
    let width = p.stroke * p.size * s
    context.addPath(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1))
    context.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(p.colorBottom), color(p.colorTop)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: point(0.5, 0.5 - half), end: point(0.5, 0.5 + half),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.25))
    context.addPath(squircle)
    context.setFillColor(.white)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let background = CGGradient(colorsSpace: nil, colors: [color(params.bgBottom), color(params.bgTop)] as CFArray,
                                locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])

    // Glow: a blurred copy of the hash, slightly lower, then the crisp hash on top.
    let hash = hashImage(size: s)
    let blurred = CIImage(cgImage: hash)
        .clampedToExtent()
        .applyingGaussianBlur(sigma: params.glowBlur * Double(s))
        .cropped(to: CGRect(x: 0, y: 0, width: s, height: s))
    let glow = CIContext().createCGImage(blurred, from: blurred.extent)!
    context.setAlpha(params.glowOpacity)
    context.draw(glow, in: CGRect(x: 0, y: -s * params.glowOffset, width: s, height: s))
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
