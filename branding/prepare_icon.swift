import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let sourceData = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let source = NSBitmapImageRep(data: sourceData),
      let sourceCGImage = source.cgImage,
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

// The supplied artwork already has a transparent rounded tile. Trim only its
// transparent canvas, then leave a small consistent margin in the macOS icon.
var minX = source.pixelsWide
var minY = source.pixelsHigh
var maxX = 0
var maxY = 0
for y in 0..<source.pixelsHigh {
    for x in 0..<source.pixelsWide where (source.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}
guard maxX >= minX, maxY >= minY else { fatalError("Source image is transparent") }
let artworkSize = max(maxX - minX + 1, maxY - minY + 1)
let cropSize = min(min(source.pixelsWide, source.pixelsHigh), Int((Double(artworkSize) * 1.05).rounded(.up)))
let centerX = (minX + maxX) / 2
let centerY = (minY + maxY) / 2
let cropX = max(0, min(source.pixelsWide - cropSize, centerX - cropSize / 2))
let cropY = max(0, min(source.pixelsHigh - cropSize, centerY - cropSize / 2))
guard let croppedCGImage = sourceCGImage.cropping(to: CGRect(x: cropX, y: cropY, width: cropSize, height: cropSize)) else {
    fatalError("Could not crop artwork")
}
let cropped = NSImage(cgImage: croppedCGImage, size: NSSize(width: cropSize, height: cropSize))
cropped.draw(
    in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
    from: NSRect(x: 0, y: 0, width: cropSize, height: cropSize),
    operation: .sourceOver,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
