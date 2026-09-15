#!/usr/bin/env swift
// Draws PressureClutch's icon: a pointer slowing down, its earlier positions closer and closer together.
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
/// Shadows are measured in device pixels, not canvas units, so they're scaled by hand.
var pixelScale: CGFloat = 1

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func setShadow(alpha: CGFloat, blur: CGFloat, offsetY: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur * pixelScale
    shadow.shadowOffset = NSSize(width: 0, height: offsetY * pixelScale)
    shadow.set()
}

/// The macOS arrow pointer, tip at `tip`, pointing up and to the left. `size` is its height.
func pointerPath(tip: NSPoint, size: CGFloat) -> NSBezierPath {
    let scale = size / 118
    let outline: [(CGFloat, CGFloat)] = [(0, 0), (0, 104), (25, 80), (42, 118), (58, 111), (42, 74), (76, 74)]
    let path = NSBezierPath()
    for (index, point) in outline.enumerated() {
        let location = NSPoint(x: tip.x + point.0 * scale, y: tip.y - point.1 * scale)
        index == 0 ? path.move(to: location) : path.line(to: location)
    }
    path.close()
    path.lineJoinStyle = .round
    return path
}

func drawIcon() {
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)
    NSGraphicsContext.saveGraphicsState()
    setShadow(alpha: 0.3, blur: 20, offsetY: -8)
    color(0x3A3FE0).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x33D1C4), color(0x3A3FE0)])?.draw(in: squircle, angle: -90)

    // The pointer travels down and to the right; its earlier positions trail up-left, each gap shorter than the last.
    let tip = NSPoint(x: 480, y: 610)
    let size: CGFloat = 340
    for (distance, alpha) in [(CGFloat(215), CGFloat(0.2)), (95, 0.42)] {
        let ghostTip = NSPoint(x: tip.x - distance * 0.7071, y: tip.y + distance * 0.7071)
        NSColor.white.withAlphaComponent(alpha).setFill()
        pointerPath(tip: ghostTip, size: size).fill()
    }

    let pointer = pointerPath(tip: tip, size: size)
    pointer.lineWidth = size * 0.055
    NSGraphicsContext.saveGraphicsState()
    setShadow(alpha: 0.45, blur: 40, offsetY: -18)
    NSColor.white.setFill()
    pointer.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0x111217).setStroke()
    pointer.stroke()
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
