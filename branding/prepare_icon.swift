import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1024,
        pixelsHigh: 1024,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fatalError("Usage: swift prepare_icon.swift source.png destination.png")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()

// Keep the generated artwork's dark tile and make its outer corners transparent
// so the icon has the usual macOS Dock silhouette.
let tile = NSRect(x: 25, y: 25, width: 974, height: 974)
NSBezierPath(roundedRect: tile, xRadius: 170, yRadius: 170).addClip()
source.draw(
    in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
    from: NSRect(origin: .zero, size: source.size),
    operation: .sourceOver,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
