import SwiftUI

struct SunsetPanel: View {
    @Bindable var model: SunsetModel
    /// Snapshot rendering only: pins the sky to a specific phase so the
    /// transition can be captured frame by frame.
    var phaseOverride: Double?

    private let sideInset: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            sky
            card
        }
        .frame(width: 344)
        .background(Ink.card)
        .animation(.smooth(duration: 0.5), value: model.forecast.conditions)
    }

    private var sky: some View {
        SkyView(quality: model.forecast.quality, phase: phaseOverride ?? model.skyPhase)
            .frame(height: 196)
            .overlay(alignment: .topLeading) {
                PaletteDots(colors: model.forecast.dots(for: model.displayedMode), axis: .vertical, size: 7)
                    .padding(.leading, sideInset)
                    .padding(.top, 20)
            }
            .overlay(alignment: .topTrailing) {
                modeToggle
                    .padding(.trailing, sideInset)
                    .padding(.top, 18)
            }
    }

    /// Switches the panel between sunset and sunrise. The sky animates the long
    /// way round - through dusk, night and dawn.
    private var modeToggle: some View {
        HStack(spacing: 7) {
            ForEach(Array(SkyMode.allCases.enumerated()), id: \.element) { index, mode in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.35))
                        .frame(width: 1, height: 8)
                }
                Button {
                    withAnimation(.easeInOut(duration: 1.7)) {
                        model.setMode(mode)
                    }
                } label: {
                    Text(mode.title)
                        .font(Typo.micro)
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(model.mode == mode ? 1 : 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
        .animation(.easeInOut(duration: 0.5), value: model.mode)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 16)

            headline
                .padding(.top, 10)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                StatCell(label: model.countdownLabel, value: model.countdown, numeric: true)
                StatCell(label: model.goldenHourLabel, value: model.goldenHour, numeric: true)

                StatCell(
                    label: model.conditionsLabel,
                    value: model.forecast.conditions,
                    gauge: model.forecast.quality
                )
                StatCell(
                    label: "Temperature",
                    value: model.temperature,
                    gauge: model.temperatureFraction,
                    numeric: true
                )

                StatCell(
                    label: "Cloud height",
                    value: model.cloudHeight,
                    gauge: model.weather?.cloudHeightFraction ?? 0.5
                )
                StatCell(
                    label: "Humidity",
                    value: model.humidity,
                    gauge: model.humidityFraction,
                    numeric: true
                )
            }
            .padding(.top, 14)

            Text("% Full visibility".uppercased())
                .labelStyle()
                .padding(.top, 18)

            VisibilityBar(fraction: model.visibilityFraction)
                .padding(.top, 8)

            footer
                .padding(.top, 14)
        }
        .padding(.horizontal, sideInset)
        .padding(.bottom, 14)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 22, alignment: .topLeading),
            GridItem(.flexible(), spacing: 22, alignment: .topLeading),
        ]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                Text(model.headline.uppercased())
                    .labelStyle()
                    .fixedSize()
                    // Long enough for TOMORROW'S SUNRISE, so the dots hold still.
                    .frame(minWidth: 126, alignment: .leading)
                PaletteDots(colors: model.forecast.dots(for: model.displayedMode))
                Spacer(minLength: 8)
                Text(model.dateLine)
                    .labelStyle(Ink.soft)
            }
            Text(model.forecast.palette(for: model.displayedMode).uppercased())
                .font(Typo.micro)
                .tracking(0.9)
                .foregroundStyle(Ink.soft)
        }
    }

    private var headline: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(model.sunsetClock)
                .font(.system(size: 52, weight: .light))
                .tracking(-1.5)
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
            Text(model.sunsetMeridiem)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Ink.muted)
                .padding(.bottom, 7)
                .padding(.leading, 3)

            Spacer(minLength: 12)

            Sunburst()
                .stroke(Ink.primary, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: 74, height: 38)
                .padding(.bottom, 6)
                .rotation3DEffect(
                    .degrees(model.displayedMode == .sunset ? 0 : 360),
                    axis: (x: 0, y: 1, z: 0)
                )
                .animation(.easeInOut(duration: 0.9), value: model.displayedMode)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let error = model.errorMessage {
                Text(error.uppercased())
                    .font(Typo.micro)
                    .tracking(0.8)
                    .foregroundStyle(Color(hex: 0xC2603A))
            } else if model.usingFallbackLocation {
                Text("Location off · using \(model.fallbackName)".uppercased())
                    .font(Typo.micro)
                    .tracking(0.8)
                    .foregroundStyle(Ink.muted)
            }

            Spacer(minLength: 0)

            Button {
                Task { await model.refresh() }
            } label: {
                Text((model.isRefreshing ? "Refreshing" : "Refresh").uppercased())
                    .font(Typo.micro)
                    .tracking(0.8)
                    .foregroundStyle(Ink.soft)
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit".uppercased())
                    .font(Typo.micro)
                    .tracking(0.8)
                    .foregroundStyle(Ink.soft)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
    }
}
