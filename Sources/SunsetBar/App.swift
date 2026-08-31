import SwiftUI
import AppKit

/// The sunburst, rendered as a template image so it picks up the menu bar's
/// own tint in both light and dark appearances.
enum MenuIcon {
    static let sun: NSImage = {
        let size = NSSize(width: 17, height: 11)
        let image = NSImage(size: size, flipped: false) { rect in
            let origin = CGPoint(x: rect.midX, y: rect.minY + 0.75)
            let unit = rect.width / 2
            let path = NSBezierPath()
            path.lineWidth = 0.9
            path.lineCapStyle = .round

            path.appendArc(
                withCenter: origin,
                radius: unit * 0.30,
                startAngle: 0,
                endAngle: 180
            )

            let inner = unit * 0.50
            let outer = unit * 0.97
            for i in 0..<9 {
                let t = Double(i) / 8
                let angle = t * Double.pi
                let dx = cos(angle), dy = sin(angle)
                path.move(to: CGPoint(x: origin.x + dx * inner, y: origin.y + dy * inner))
                path.line(to: CGPoint(x: origin.x + dx * outer, y: origin.y + dy * outer))
            }

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// Development aid: `SUNSETBAR_SNAPSHOT=<path>` renders the panel to a PNG
/// once live data has landed, then exits. Used to eyeball the layout without
/// driving the menu bar by hand.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = ProcessInfo.processInfo.environment["SUNSETBAR_SNAPSHOT"] else { return }
        Task { @MainActor in
            let model = SunsetModel()
            try? await Task.sleep(for: .seconds(4))
            let base = URL(fileURLWithPath: path).deletingLastPathComponent()

            @MainActor func write<V: View>(_ view: V, to name: String) {
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                try? png.write(to: base.appendingPathComponent(name))
            }

            write(SunsetPanel(model: model), to: "panel_sunset.png")

            // The sky across the whole transition. Each frame is produced by
            // driving `animatableData`, exactly as SwiftUI does during an
            // animation - so this strip verifies the animation path itself, not
            // just that the keyframes look right.
            let quality = model.forecast.quality
            let phases = stride(from: 0.0, through: 1.0, by: 0.125).map { $0 }
            write(
                HStack(spacing: 0) {
                    ForEach(phases, id: \.self) { phase in
                        interpolatedSky(quality: quality, to: phase)
                            .frame(width: 104, height: 196)
                    }
                },
                to: "filmstrip.png"
            )

            model.mode = .sunrise
            model.displayedMode = .sunrise
            try? await Task.sleep(for: .milliseconds(400))
            write(SunsetPanel(model: model), to: "panel_sunrise.png")

            NSApplication.shared.terminate(nil)
        }
    }
}

/// A SkyView advanced to `phase` through its `animatableData`, the same way
/// SwiftUI drives it mid-animation.
@MainActor
private func interpolatedSky(quality: Double, to phase: Double) -> SkyView {
    var sky = SkyView(quality: quality, phase: 0)
    sky.animatableData = AnimatablePair(phase, quality)
    return sky
}

@main
struct SunsetBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SunsetModel()

    var body: some Scene {
        MenuBarExtra {
            SunsetPanel(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: MenuIcon.sun)
                Text(model.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
