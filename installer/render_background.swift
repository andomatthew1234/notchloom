import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "installer/notchloom-background.png"
let size = NSSize(width: 640, height: 380)
let image = NSImage(size: size)

let ink = NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.11, alpha: 1)
let cyan = NSColor(calibratedRed: 0.20, green: 0.91, blue: 0.96, alpha: 1)
let violet = NSColor(calibratedRed: 0.69, green: 0.43, blue: 0.98, alpha: 1)

func label(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
           color: NSColor, tracking: CGFloat = 0) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking
    ]
    NSAttributedString(string: value, attributes: attributes).draw(at: NSPoint(x: x, y: y))
}

image.lockFocus()
ink.setFill()
NSRect(origin: .zero, size: size).fill()

// Soft color at the top echoes the app icon without distracting from Finder icons.
for (color, rect) in [
    (cyan.withAlphaComponent(0.12), NSRect(x: -80, y: 260, width: 360, height: 210)),
    (violet.withAlphaComponent(0.16), NSRect(x: 390, y: 210, width: 350, height: 240))
] {
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = 75
    shadow.set()
    NSBezierPath(ovalIn: rect).fill()
    NSShadow().set()
}

let topRule = NSBezierPath(rect: NSRect(x: 28, y: 278, width: 584, height: 1))
NSGradient(starting: cyan.withAlphaComponent(0.7), ending: violet.withAlphaComponent(0.7))?
    .draw(in: topRule, angle: 0)

// Finder uses dark icon labels in a light system appearance. Pale cards keep
// both the app and Applications labels legible against the charcoal canvas.
for (x, tint) in [(90.0, cyan), (380.0, violet)] {
    let card = NSBezierPath(roundedRect: NSRect(x: x, y: 93, width: 170, height: 165),
                            xRadius: 19, yRadius: 19)
    tint.withAlphaComponent(0.15).setStroke()
    card.lineWidth = 1.5
    card.stroke()
    NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.96, alpha: 0.90).setFill()
    card.fill()
}

if let icon = NSImage(contentsOfFile: "boringNotch/Assets.xcassets/AppIcon.appiconset/notchloom-128.png") {
    icon.draw(in: NSRect(x: 28, y: 301, width: 50, height: 50))
}
label("NOTCHLOOM", x: 88, y: 324, size: 17, weight: .bold, color: .white, tracking: 2.4)
label("YOUR NOTCH, WOVEN IN", x: 89, y: 301, size: 9, weight: .medium,
      color: NSColor.white.withAlphaComponent(0.63), tracking: 1.5)

// A simple directional cue sits between the app and Applications icons.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 273, y: 173))
arrow.line(to: NSPoint(x: 359, y: 173))
arrow.move(to: NSPoint(x: 343, y: 187))
arrow.line(to: NSPoint(x: 359, y: 173))
arrow.line(to: NSPoint(x: 343, y: 159))
arrow.lineWidth = 3.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
let arrowShadow = NSShadow()
arrowShadow.shadowColor = cyan.withAlphaComponent(0.6)
arrowShadow.shadowBlurRadius = 15
arrowShadow.set()
cyan.setStroke()
arrow.stroke()
NSShadow().set()

label("Drag Notchloom into Applications", x: 166, y: 69, size: 16,
      weight: .semibold, color: .white)
label("A little more room for everything.", x: 215, y: 47, size: 11,
      weight: .regular, color: NSColor.white.withAlphaComponent(0.55))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render installer background")
}
try png.write(to: URL(fileURLWithPath: output))
