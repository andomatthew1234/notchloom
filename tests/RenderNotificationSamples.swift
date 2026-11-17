import AppKit
import SwiftUI

@main
struct RenderNotificationSamples {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases: [(String, String, String, CGFloat)] = [
            ("short", "Ready", "", 32),
            ("long", "A longer notification", "This longer message checks wrapping and truncation. It should stay readable inside the notch with two lines of text, even when the message contains much more detail.", 32),
            ("external", "Timer finished", "Your timer has ended.", 0)
        ]
        for (name, title, body, inset) in cases {
            let p = NotificationPresentation(timing: .init(display: 60, clockDisplay: 60), monitorClicks: false)
            let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
            p.updateSurface("snapshot", frame: screen, blocked: false)
            p.enqueue(.init(id: name, source: name == "external" ? "Clock" : "Notchloom", title: title, body: body))
            try await Task.sleep(for: .seconds(0.5))
            for isHovered in (name == "long" ? [false, true] : [false]) {
                p.setHovered(isHovered, on: "snapshot")
                for scale: CGFloat in [1, 2] {
                    let view = Color.clear.frame(width: 185, height: 32)
                        .modifier(NotificationNotchSurface(presentation: p, screenID: "snapshot", screenFrame: screen,
                            topInset: inset, blocked: false, normalShape: NotchShape(), normalShadow: false))
                        .frame(width: 470, height: 170, alignment: .top)
                        .background(Color(white: 0.24))
                        .environment(\.colorScheme, .dark)
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = scale
                    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        fatalError("Could not render \(name)")
                    }
                    let suffix = isHovered ? "-hover" : ""
                    try png.write(to: output.appendingPathComponent("\(name)\(suffix)-\(Int(scale))x.png"))
                    print("Rendered \(name)\(suffix) at \(Int(scale))x")
                }
            }
            p.reset()
        }
    }
}
