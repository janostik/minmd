// Renders the app icon: a GitHub-dark squircle with a JetBrains Mono "md".
// Usage: swift scripts/make-icon.swift <JetBrainsMono-Bold.ttf> <output.appiconset>
import AppKit

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1]) as CFURL
let output = URL(fileURLWithPath: args[2])
CTFontManagerRegisterFontsForURL(fontURL, .process, nil)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSColor(srgbRed: 0x0D / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1).setFill()
    path.fill()

    let font = NSFont(name: "JetBrainsMono-Bold", size: rect.width * 0.36) ?? .monospacedSystemFont(ofSize: rect.width * 0.36, weight: .bold)
    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: "#", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0x8B / 255, green: 0x94 / 255, blue: 0x9E / 255, alpha: 1)]))
    text.append(NSAttributedString(string: "md", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0xF0 / 255, green: 0xF6 / 255, blue: 0xFC / 255, alpha: 1)]))
    let size = text.size()
    text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
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
