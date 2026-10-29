import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func glyphImage(size: CGFloat, lowerColor: NSColor, upperColor: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    if let symbol = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size * 0.52, weight: .semibold)) {
        let glyphRect = NSRect(x: size * 0.22, y: size * 0.20,
                               width: size * 0.56, height: size * 0.60)
        symbol.draw(in: glyphRect)
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        NSGradient(starting: lowerColor, ending: upperColor)?
            .draw(in: glyphRect, angle: 135)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
    return image
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: Int(size), pixelsHigh: Int(size),
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    defer { NSGraphicsContext.restoreGraphicsState() }

    let tile = NSBezierPath(roundedRect: NSRect(x: size * 0.055, y: size * 0.068,
                                                width: size * 0.89, height: size * 0.89),
                            xRadius: size * 0.205, yRadius: size * 0.205)

    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0, 69, 136, 0.30)
    tileShadow.shadowBlurRadius = size * 0.035
    tileShadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
    tileShadow.set()
    NSGradient(starting: color(8, 119, 233), ending: color(50, 181, 248))!
        .draw(in: tile, angle: 90)
    NSShadow().set()

    color(255, 255, 255, 0.22).setStroke()
    tile.lineWidth = max(size * 0.002, 0.5)
    tile.stroke()

    let glyph = glyphImage(size: size,
                           lowerColor: color(172, 210, 255), upperColor: .white)
    let bevel = glyphImage(size: size,
                           lowerColor: color(48, 139, 221), upperColor: color(151, 208, 255))
    let fullRect = NSRect(x: 0, y: 0, width: size, height: size)
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = color(0, 56, 132, 0.48)
    glyphShadow.shadowBlurRadius = size * 0.034
    glyphShadow.shadowOffset = NSSize(width: size * 0.014, height: -size * 0.026)
    glyphShadow.set()
    bevel.draw(in: fullRect.offsetBy(dx: size * 0.010, dy: -size * 0.014),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSShadow().set()
    glyph.draw(in: fullRect, from: .zero, operation: .sourceOver, fraction: 1)

    context.flushGraphics()
    return bitmap
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = drawIcon(size: CGFloat(pixels))
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent(name))
    }
}
