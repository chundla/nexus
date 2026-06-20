#if os(macOS)
    import AppKit
    import SwiftUI

    enum NexusMacTheme {
        static let backgroundTop = dynamicColor(light: .rgb(0.956, 0.964, 0.982), dark: .rgb(0.098, 0.110, 0.133))
        static let backgroundBottom = dynamicColor(light: .rgb(0.910, 0.928, 0.958), dark: .rgb(0.055, 0.063, 0.080))
        static let panel = dynamicColor(
            light: .rgb(0.985, 0.989, 0.998, alpha: 0.86), dark: .rgb(0.114, 0.125, 0.153, alpha: 0.86))
        static let panelRaised = dynamicColor(
            light: .rgb(0.998, 0.999, 1.000, alpha: 0.94), dark: .rgb(0.145, 0.157, 0.192, alpha: 0.94))
        static let line = dynamicColor(
            light: .rgb(0.059, 0.075, 0.102, alpha: 0.10), dark: .rgb(1.000, 1.000, 1.000, alpha: 0.10))
        static let softLine = dynamicColor(
            light: .rgb(0.059, 0.075, 0.102, alpha: 0.05), dark: .rgb(1.000, 1.000, 1.000, alpha: 0.05))
        static let gold = dynamicColor(light: .rgb(0.173, 0.412, 0.902), dark: .rgb(0.415, 0.655, 1.000))
        static let teal = dynamicColor(light: .rgb(0.102, 0.612, 0.424), dark: .rgb(0.392, 0.890, 0.681))
        static let coral = dynamicColor(light: .rgb(0.780, 0.200, 0.200), dark: .rgb(1.000, 0.474, 0.474))
        static let mist = Color.primary
        static let mutedText = dynamicColor(
            light: .rgb(0.247, 0.286, 0.357, alpha: 0.78), dark: .rgb(0.855, 0.884, 0.934, alpha: 0.74))
        static let subtleText = dynamicColor(
            light: .rgb(0.247, 0.286, 0.357, alpha: 0.56), dark: .rgb(0.855, 0.884, 0.934, alpha: 0.52))
        static let textPrimary = Color.primary
        static let terminalText = dynamicColor(light: .rgb(0.968, 0.975, 0.992), dark: .rgb(0.968, 0.975, 0.992))
        static let terminalSurface = dynamicColor(
            light: .rgb(0.071, 0.086, 0.122, alpha: 0.88), dark: .rgb(0.020, 0.024, 0.035, alpha: 0.92))
        static let terminalOverlay = dynamicColor(
            light: .rgb(0.071, 0.086, 0.122, alpha: 0.22), dark: .rgb(0.000, 0.000, 0.000, alpha: 0.30))

        static let backdropGradient = LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static func overlay(_ opacity: Double) -> Color {
            dynamicColor(
                light: .rgb(0.059, 0.075, 0.102, alpha: min(opacity * 0.95, 1.0)),
                dark: .rgb(1.000, 1.000, 1.000, alpha: min(opacity, 1.0))
            )
        }

        static func shadow(_ opacity: Double) -> Color {
            dynamicColor(
                light: .rgb(0.059, 0.075, 0.102, alpha: min(opacity * 0.60, 1.0)),
                dark: .rgb(0.000, 0.000, 0.000, alpha: min(opacity, 1.0))
            )
        }

        static func displayFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }

        static func bodyFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        static func monoFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }

        private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
            Color(
                nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                }
            )
        }
    }

    private extension NSColor {
        static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
            NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
    }

    struct NexusBackdrop: View {
        var body: some View {
            ZStack {
                NexusMacTheme.backdropGradient
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [NexusMacTheme.overlay(0.035), .clear, NexusMacTheme.overlay(0.018)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.overlay)
                .ignoresSafeArea()

                Circle()
                    .fill(NexusMacTheme.gold.opacity(0.12))
                    .frame(width: 420)
                    .blur(radius: 120)
                    .offset(x: -320, y: -320)

                Circle()
                    .fill(NexusMacTheme.teal.opacity(0.10))
                    .frame(width: 360)
                    .blur(radius: 140)
                    .offset(x: 300, y: 280)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [NexusMacTheme.overlay(0.020), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
            }
        }
    }

    struct NexusPanelModifier: ViewModifier {
        var tint: Color
        var radius: CGFloat
        var raised: Bool = false

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

            content
                .background {
                    shape
                        .fill((raised ? NexusMacTheme.panelRaised : NexusMacTheme.panel))
                        .overlay {
                            shape
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            NexusMacTheme.overlay(0.065),
                                            .clear,
                                            tint.opacity(0.08),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay(alignment: .top) {
                            shape
                                .fill(
                                    LinearGradient(
                                        colors: [NexusMacTheme.overlay(0.13), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .mask(alignment: .top) {
                                    Rectangle()
                                        .frame(height: 1)
                                        .clipShape(shape)
                                }
                        }
                        .overlay {
                            shape
                                .strokeBorder(NexusMacTheme.line, lineWidth: 1)
                        }
                        .shadow(color: NexusMacTheme.shadow(0.20), radius: raised ? 28 : 22, y: raised ? 14 : 10)
                }
        }
    }

    extension View {
        func nexusPanel(tint: Color = .clear, radius: CGFloat = 22, raised: Bool = false) -> some View {
            modifier(NexusPanelModifier(tint: tint, radius: radius, raised: raised))
        }
    }

    struct NexusSectionHeader: View {
        let eyebrow: String
        let title: String
        let detail: String?

        init(eyebrow: String, title: String, detail: String? = nil) {
            self.eyebrow = eyebrow
            self.title = title
            self.detail = detail
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow.uppercased())
                    .font(NexusMacTheme.monoFont(11, relativeTo: .caption))
                    .tracking(2.2)
                    .foregroundStyle(NexusMacTheme.gold)

                Text(title)
                    .font(NexusMacTheme.displayFont(28, relativeTo: .largeTitle))
                    .foregroundStyle(NexusMacTheme.textPrimary)

                if let detail {
                    Text(detail)
                        .font(NexusMacTheme.bodyFont(14))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct NexusMetricTile: View {
        let title: String
        let value: String
        let detail: String
        var accent: Color = NexusMacTheme.gold

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(NexusMacTheme.monoFont(11, relativeTo: .caption))
                    .tracking(2.0)
                    .foregroundStyle(accent)

                Text(value)
                    .font(NexusMacTheme.displayFont(24, relativeTo: .title))
                    .foregroundStyle(NexusMacTheme.textPrimary)

                Text(detail)
                    .font(NexusMacTheme.bodyFont(13, relativeTo: .caption))
                    .foregroundStyle(NexusMacTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .nexusPanel(tint: accent, radius: 18, raised: true)
        }
    }

    struct NexusStatusPill: View {
        let text: String
        var color: Color

        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(text)
                    .font(NexusMacTheme.bodyFont(12, relativeTo: .caption).weight(.medium))
            }
            .foregroundStyle(NexusMacTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(NexusMacTheme.overlay(0.055), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.28), lineWidth: 1)
            }
        }
    }

    struct NexusMetaBadge: View {
        let icon: String
        let text: String

        var body: some View {
            Label(text, systemImage: icon)
                .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                .foregroundStyle(NexusMacTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(NexusMacTheme.overlay(0.045), in: Capsule())
                .overlay {
                    Capsule().stroke(NexusMacTheme.softLine, lineWidth: 1)
                }
        }
    }

    struct NexusInspectorRow: View {
        let title: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(NexusMacTheme.monoFont(10, relativeTo: .caption2))
                    .tracking(1.8)
                    .foregroundStyle(NexusMacTheme.gold)
                Text(value)
                    .font(NexusMacTheme.bodyFont(13))
                    .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct NexusAccentButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusMacTheme.bodyFont(13, relativeTo: .callout).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(NexusMacTheme.gold.opacity(configuration.isPressed ? 0.84 : 0.96))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(NexusMacTheme.gold.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: NexusMacTheme.gold.opacity(configuration.isPressed ? 0.08 : 0.16), radius: 14, y: 8)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }

    struct NexusSecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusMacTheme.bodyFont(13, relativeTo: .callout).weight(.medium))
                .foregroundStyle(NexusMacTheme.textPrimary.opacity(configuration.isPressed ? 0.82 : 0.94))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    NexusMacTheme.overlay(configuration.isPressed ? 0.07 : 0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NexusMacTheme.softLine, lineWidth: 1)
                }
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
#endif
