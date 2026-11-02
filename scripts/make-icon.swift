// Draws Luminary's app icon (1024x1024 PNG): swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    // macOS icon template: 824 pt rounded square centred in the canvas, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.09, blue: 0.2, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Deep indigo (top) to blue (bottom), like the login screen.
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.20, green: 0.16, blue: 0.48, alpha: 1).cgColor,
        NSColor(srgbRed: 0.06, green: 0.30, blue: 0.62, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // The "luminary": a soft light behind the play button.
    let glow = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.65, green: 0.85, blue: 1, alpha: 0.85).cgColor,
        NSColor(srgbRed: 0.35, green: 0.6, blue: 1, alpha: 0.0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: 420, options: [])
    // Glass highlight along the top edge.
    let sheen = CGGradient(colorsSpace: space, colors: [
        NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    ctx.restoreGState()

    // Play triangle with rounded corners; its centroid sits on the icon's centre, which is what reads as centred.
    let tri = CGMutablePath()
    let a = CGPoint(x: 415, y: 344), b = CGPoint(x: 415, y: 680), c = CGPoint(x: 705, y: 512) // centroid = canvas centre (512, 512)
    tri.move(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2))
    tri.addArc(tangent1End: a, tangent2End: b, radius: 46)
    tri.addArc(tangent1End: b, tangent2End: c, radius: 46)
    tri.addArc(tangent1End: c, tangent2End: a, radius: 46)
    tri.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: NSColor(srgbRed: 0.3, green: 0.5, blue: 1, alpha: 0.6).cgColor)
    ctx.addPath(tri); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
