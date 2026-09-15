#!/usr/bin/env swift
// Draws PressureClutch's icon: an fn key, with a pointer slowing down in front of it.
// Used by Tools/make-icon.sh, which assembles the .icns.
//
//   swift Tools/make-icon.swift <iconset directory> [preview.png]
import AppKit

let arguments = CommandLine.arguments
let outputDirectory = arguments.count > 1 ? arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

/// Everything is laid out on a 1024-unit canvas, then scaled to each pixel size.
let canvas: CGFloat = 1024
/// macOS icon grid: an 824-unit body centred on the canvas, leaving room for its shadow.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let contentScale = body.width / canvas
/// Shadows are measured in device pixels, not canvas units, so they're scaled by hand.
var pixelScale: CGFloat = 1

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func setShadow(alpha: CGFloat, blur: CGFloat, offsetY: CGFloat, scale: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur * scale
    shadow.shadowOffset = NSSize(width: 0, height: offsetY * scale)
    shadow.set()
}

/// A keycap seen from above: its dark skirt, then the lighter top face.
func keycap(_ rect: NSRect) {
    let skirt = NSBezierPath(roundedRect: rect, xRadius: 120, yRadius: 120)
    NSGraphicsContext.saveGraphicsState()
    setShadow(alpha: 0.45, blur: 60, offsetY: -30, scale: pixelScale * contentScale)
    color(0x1B1F2E).setFill()
    skirt.fill()
    NSGraphicsContext.restoreGraphicsState()

    let top = NSBezierPath(roundedRect: NSRect(x: rect.minX + 26, y: rect.minY + 52, width: rect.width - 52, height: rect.height - 72),
                           xRadius: 100, yRadius: 100)
    NSGradient(colors: [color(0x3A4160), color(0x272C42)])?.draw(in: top, angle: -90)

    // "fn" top right, the globe bottom left, as on a Mac keyboard.
    let label = NSAttributedString(string: "fn", attributes: [
        .font: NSFont.systemFont(ofSize: 150, weight: .medium),
        .foregroundColor: color(0xE9ECF5),
    ])
    let labelSize = label.size()
    label.draw(at: NSPoint(x: rect.maxX - 90 - labelSize.width, y: rect.maxY - 90 - labelSize.height))

    let configuration = NSImage.SymbolConfiguration(pointSize: 150, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color(0xE9ECF5)]))
    if let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
        let size = globe.size
        globe.draw(in: NSRect(x: rect.minX + 95, y: rect.minY + 110, width: size.width, height: size.height))
    }
}

/// The macOS arrow pointer, tip at `tip`, pointing up and to the left.
func pointer(tip: NSPoint, scale: CGFloat, alpha: CGFloat) {
    let outline: [(CGFloat, CGFloat)] = [(0, 0), (0, 104), (25, 80), (42, 118), (58, 111), (42, 74), (76, 74)]
    let path = NSBezierPath()
    for (index, point) in outline.enumerated() {
        let location = NSPoint(x: tip.x + point.0 * scale, y: tip.y - point.1 * scale)
        index == 0 ? path.move(to: location) : path.line(to: location)
    }
    path.close()
    path.lineJoinStyle = .round
    path.lineWidth = 7 * scale

    NSGraphicsContext.saveGraphicsState()
    if alpha == 1 { setShadow(alpha: 0.4, blur: 30, offsetY: -12, scale: pixelScale * contentScale) }
    NSColor.white.withAlphaComponent(alpha).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.black.withAlphaComponent(alpha).setStroke()
    path.stroke()
}

func drawIcon() {
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)
    NSGraphicsContext.saveGraphicsState()
    setShadow(alpha: 0.3, blur: 20, offsetY: -8, scale: pixelScale)
    color(0x2F6BFF).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x5AA2FF), color(0x3B4CF0)])?.draw(in: squircle, angle: -90)

    // The artwork is drawn full-canvas, then fitted into the body.
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: body.minX, yBy: body.minY)
    transform.scale(by: contentScale)
    transform.concat()

    keycap(NSRect(x: 150, y: 330, width: 560, height: 560))

    // Three pointers, each step shorter than the last: the pointer slowing down.
    let scale: CGFloat = 3.1
    pointer(tip: NSPoint(x: 500, y: 560), scale: scale, alpha: 0.22)
    pointer(tip: NSPoint(x: 590, y: 470), scale: scale, alpha: 0.45)
    pointer(tip: NSPoint(x: 635, y: 425), scale: scale, alpha: 1)

    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(pixels: Int, to path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    pixelScale = CGFloat(pixels) / canvas
    context.cgContext.scaleBy(x: pixelScale, y: pixelScale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

for size in [16, 32, 128, 256, 512] {
    writePNG(pixels: size, to: "\(outputDirectory)/icon_\(size)x\(size).png")
    writePNG(pixels: size * 2, to: "\(outputDirectory)/icon_\(size)x\(size)@2x.png")
}
if arguments.count > 2 {
    writePNG(pixels: 512, to: arguments[2])
}
print("Icon written to \(outputDirectory)")
