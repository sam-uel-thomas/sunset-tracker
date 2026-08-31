import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Push a colour toward or away from grey. Used to make the sky respond to
    /// sunset quality without ever leaving the mockup's palette.
    func saturated(by factor: Double, brightness bFactor: Double = 1) -> Color {
        guard let base = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let ns = NSColor(
            hue: h,
            saturation: min(1, max(0, s * factor)),
            brightness: min(1, max(0, b * bFactor)),
            alpha: a
        )
        return Color(nsColor: ns)
    }
}

enum Ink {
    static let card = Color(hex: 0xF1F1EF)
    static let primary = Color(hex: 0x141414)
    static let soft = Color(hex: 0x8C8C8C)
    static let muted = Color(hex: 0xB0B0AE)
    static let hairline = Color(hex: 0xDCDCD9)
}

enum Bar {
    static let track = Color(hex: 0xDBE3F4)
    static let fillStart = Color(hex: 0xF5E7C2)
    static let fillEnd = Color(hex: 0xA6BDEA)
}

enum GaugeInk {
    static let top = Color(hex: 0xF0742B)
    static let mid = Color(hex: 0xEFEFEF)
    static let bottom = Color(hex: 0x7B96D8)
}

enum Typo {
    /// The wide-tracked monospace used for every label in the mockup.
    static let label = Font.system(size: 9, weight: .regular, design: .monospaced)
    static let micro = Font.system(size: 8, weight: .regular, design: .monospaced)
    static func value(_ size: CGFloat = 21) -> Font { .system(size: size, weight: .light) }
}

extension View {
    /// Uppercase mono label, matching the mockup's letter-spacing.
    func labelStyle(_ color: Color = Ink.primary) -> some View {
        font(Typo.label).tracking(1.1).foregroundStyle(color)
    }
}

/// The sky, as five keyframes the panel interpolates between. Phase 0 is the
/// mockup's sunset; phase 1 is sunrise; the route between them runs through
/// dusk, night and dawn, so switching modes reads as time passing.
enum Sky {
    static let phases: [Double] = [0, 0.30, 0.55, 0.78, 1.0]

    /// Nine stops each, top of the sky to the horizon.
    static let keyframes: [[UInt32]] = [
        // Sunset - read straight off the mockup.
        [0x9EAFD9, 0xAEB7D8, 0xCFC6CE, 0xE9D3B4, 0xF6DCB0, 0xF8C88E, 0xF9A860, 0xF6913F, 0xF2882F],
        // Dusk.
        [0x3E4A72, 0x4E5680, 0x6A6790, 0x8E7B94, 0xB08A8C, 0xC98F72, 0xD98F5A, 0xD9834A, 0xC9713C],
        // Night.
        [0x080C20, 0x0C1230, 0x11173C, 0x161D48, 0x1B2352, 0x1F295B, 0x242F64, 0x28356B, 0x2C3A71],
        // Dawn.
        [0x2C3358, 0x3B4270, 0x565480, 0x7A6488, 0xA0798C, 0xC08F86, 0xD8A583, 0xE8B884, 0xF0C48C],
        // Sunrise - cooler and rosier than sunset.
        [0x8FA3D6, 0xA3B0DC, 0xC2C2D8, 0xDCC9C6, 0xF0D6BC, 0xF8DCB4, 0xF9C79A, 0xF7B583, 0xF4A76F],
    ]

    static let positions: [Double] = [0, 0.20, 0.37, 0.49, 0.59, 0.70, 0.82, 0.93, 1.0]

    /// How night-like a phase is: 1 at deep night, 0 at either end.
    static func nightness(_ phase: Double) -> Double {
        let t = (phase - 0.55) / 0.30
        return max(0, min(1, exp(-t * t)))
    }

    private static func lerp(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let av = Double((a >> shift) & 0xFF)
            let bv = Double((b >> shift) & 0xFF)
            return av + (bv - av) * t
        }
        return Color(.sRGB,
                     red: channel(16) / 255,
                     green: channel(8) / 255,
                     blue: channel(0) / 255,
                     opacity: 1)
    }

    static func colors(phase: Double, quality: Double) -> [Color] {
        let p = max(0, min(1, phase))
        var index = 0
        while index < phases.count - 2, p > phases[index + 1] { index += 1 }
        let span = phases[index + 1] - phases[index]
        let t = span > 0 ? (p - phases[index]) / span : 0

        let from = keyframes[index]
        let to = keyframes[index + 1]

        // Quality desaturates the sky, but only where there is colour to lose -
        // night should stay night regardless of the forecast.
        let daylit = 1 - nightness(p)
        let sat = 1 - daylit * (1 - (0.45 + 0.80 * quality))
        let bright = 1 - daylit * (1 - (1.02 - 0.05 * quality))

        return zip(from, to).map { lerp($0, $1, t).saturated(by: sat, brightness: bright) }
    }
}

/// Film grain. Generated once, then tiled and overlay-blended over the sky.
enum Grain {
    static let image: NSImage = {
        let side = 150
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let v = UInt8.random(in: 96...162)
            bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
        }
        let cg = bytes.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
        guard let cg else { return NSImage(size: .zero) }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }()
}
