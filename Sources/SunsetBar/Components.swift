import SwiftUI

/// The hand-drawn half-sun from the mockup: a small dome with a fan of rays.
struct Sunburst: Shape {
    var rayCount: Int = 13

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let origin = CGPoint(x: rect.midX, y: rect.maxY)
        let unit = rect.width / 2

        let dome = unit * 0.30
        path.addArc(
            center: origin,
            radius: dome,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )

        let inner = unit * 0.47
        let outer = unit * 0.99
        for i in 0..<rayCount {
            let t = Double(i) / Double(rayCount - 1)
            let angle = (180 + t * 180) * .pi / 180
            let dx = cos(angle), dy = sin(angle)
            path.move(to: CGPoint(x: origin.x + dx * inner, y: origin.y + dy * inner))
            path.addLine(to: CGPoint(x: origin.x + dx * outer, y: origin.y + dy * outer))
        }
        return path
    }
}

/// The little vertical thermometer beside each stat: an orange-to-blue capsule
/// with a black tick marking the reading.
struct MiniGauge: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let y = height * (1 - min(1, max(0, fraction)))
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [GaugeInk.top, GaugeInk.mid, GaugeInk.bottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Capsule()
                    .fill(Ink.primary)
                    .frame(width: 13, height: 1.5)
                    .position(x: geo.size.width / 2, y: min(height - 1, max(1, y)))
                    .animation(.smooth(duration: 0.55), value: fraction)
            }
        }
        .frame(width: 13, height: 46)
    }
}

/// The wide "% full visibility" meter.
struct VisibilityBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Bar.track)

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Bar.fillStart, Bar.fillEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(58, geo.size.width * clamped))
                    .animation(.smooth(duration: 0.6), value: clamped)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((clamped * 100).rounded()))")
                        .font(Typo.value(21))
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 11, weight: .regular))
                }
                .foregroundStyle(Ink.primary)
                .padding(.leading, 13)
            }
        }
        .frame(height: 34)
    }
}

/// One label/value pair, with an optional gauge pinned to its trailing edge.
struct StatCell: View {
    let label: String
    let value: String
    var gauge: Double?
    /// Numerals roll; words cross-fade.
    var numeric: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .labelStyle()
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2, reservesSpace: true)
                    .contentTransition(.opacity)
                    .animation(.smooth(duration: 0.45), value: label)
                Text(value)
                    .font(Typo.value())
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(numeric ? .numericText() : .opacity)
                    .animation(.smooth(duration: 0.45), value: value)
            }
            Spacer(minLength: 0)
            if let gauge {
                MiniGauge(fraction: gauge)
                    .padding(.top, 1)
            }
        }
    }
}

/// Deterministic star positions, so the sky looks the same every time it opens.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct StarField: View {
    var opacity: Double
    @State private var twinkling = false

    private struct Star {
        let x, y, size, period, delay, brightness: Double
    }

    private static let stars: [Star] = {
        var rng = SplitMix64(seed: 0x5EED_5C0F_FEE5)
        return (0..<52).map { _ in
            // Biased toward the top, where the sky stays darkest.
            let v = Double.random(in: 0...1, using: &rng)
            return Star(
                x: Double.random(in: 0.02...0.98, using: &rng),
                y: v * v * 0.82,
                size: Double.random(in: 0.9...2.1, using: &rng),
                period: Double.random(in: 1.9...3.8, using: &rng),
                delay: Double.random(in: 0...2.4, using: &rng),
                brightness: Double.random(in: 0.45...1.0, using: &rng)
            )
        }
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(.white)
                        .frame(width: star.size, height: star.size)
                        .opacity(star.brightness * (twinkling ? 0.35 : 1.0))
                        .animation(
                            .easeInOut(duration: star.period)
                                .repeatForever(autoreverses: true)
                                .delay(star.delay),
                            value: twinkling
                        )
                        .offset(x: star.x * geo.size.width, y: star.y * geo.size.height)
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .onAppear { twinkling = true }
    }
}

/// The graded, grainy sky, plus the sun that carries it between sunset and
/// sunrise by dipping below the horizon and coming back up the other side.
struct SkyView: View, Animatable {
    var quality: Double
    var phase: Double

    /// Without this, SwiftUI re-renders at the destination phase rather than
    /// interpolating toward it, and the sky cross-fades straight from sunset to
    /// sunrise - skipping dusk, night and dawn entirely.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, quality) }
        set {
            phase = newValue.first
            quality = newValue.second
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(stops: gradientStops, startPoint: .top, endPoint: .bottom)

            StarField(opacity: Sky.nightness(phase))

            GeometryReader { geo in
                let glow = glowStrength
                if glow > 0.01 {
                    RadialGradient(
                        colors: [
                            .white.opacity(0.34 * glow),
                            .white.opacity(0.10 * glow),
                            .white.opacity(0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: geo.size.width * 0.17
                    )
                    .frame(width: geo.size.width * 0.34, height: geo.size.width * 0.34)
                    .position(
                        x: geo.size.width * sunX,
                        y: geo.size.height * sunY
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            }
        }
        .overlay {
            Image(nsImage: Grain.image)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(0.55)
                .allowsHitTesting(false)
        }
        .compositingGroup()
    }

    // Sets on the right, travels under, rises on the left.
    private var sunX: Double { 0.72 - 0.44 * phase }
    private var sunY: Double { 0.60 + 0.78 * sin(phase * .pi) }
    private var glowStrength: Double {
        max(0, 1 - sin(phase * .pi) / 0.40)
    }

    private var gradientStops: [Gradient.Stop] {
        zip(Sky.colors(phase: phase, quality: quality), Sky.positions)
            .map { Gradient.Stop(color: $0, location: $1) }
    }
}

/// The three palette dots, vertical over the sky and horizontal in the card.
struct PaletteDots: View {
    var colors: [UInt32]
    var axis: Axis = .horizontal
    var size: CGFloat = 5

    var body: some View {
        let content = ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
            Circle()
                .fill(Color(hex: hex))
                .frame(width: size, height: size)
        }
        return Group {
            if axis == .horizontal {
                HStack(spacing: 4) { content }
            } else {
                VStack(spacing: 12) { content }
            }
        }
    }
}
