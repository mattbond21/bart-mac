#!/usr/bin/swift
import AppKit

let output = CommandLine.arguments[1]
let width = 660
let height = 420
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(starting: NSColor(calibratedRed: 0.93, green: 0.97, blue: 1.0, alpha: 1),
           ending: NSColor(calibratedRed: 0.92, green: 0.98, blue: 0.95, alpha: 1))!
    .draw(in: rect, angle: 0)

let title = "Install Bart"
let titleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
]
(title as NSString).draw(at: NSPoint(x: 38, y: 344), withAttributes: titleStyle)

let subtitle = "Drag Bart into Applications"
let subtitleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.36, alpha: 1),
]
(subtitle as NSString).draw(at: NSPoint(x: 39, y: 318), withAttributes: subtitleStyle)

let arrow = NSBezierPath()
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 295, y: 177))
arrow.line(to: NSPoint(x: 368, y: 177))
arrow.move(to: NSPoint(x: 358, y: 187))
arrow.line(to: NSPoint(x: 368, y: 177))
arrow.line(to: NSPoint(x: 358, y: 167))
NSColor(calibratedWhite: 0.55, alpha: 0.9).setStroke()
arrow.stroke()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render DMG background")
}
try png.write(to: URL(fileURLWithPath: output))
