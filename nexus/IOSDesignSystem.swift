#if os(iOS)
    import SwiftUI
    import UIKit

    enum NexusIOSTheme {
        static let backgroundTop = dynamicColor(light: .rgb(0.972, 0.978, 0.992), dark: .rgb(0.063, 0.075, 0.102))
        static let backgroundBottom = dynamicColor(light: .rgb(0.928, 0.944, 0.972), dark: .rgb(0.031, 0.039, 0.055))
        static let panel = dynamicColor(
            light: .rgb(1.000, 1.000, 1.000, alpha: 0.84), dark: .rgb(0.102, 0.114, 0.153, alpha: 0.84))
        static let panelRaised = dynamicColor(
            light: .rgb(1.000, 1.000, 1.000, alpha: 0.94), dark: .rgb(0.129, 0.145, 0.192, alpha: 0.92))
        static let line = dynamicColor(
            light: .rgb(0.071, 0.086, 0.122, alpha: 0.09), dark: .rgb(1.000, 1.000, 1.000, alpha: 0.10))
        static let softLine = dynamicColor(
            light: .rgb(0.071, 0.086, 0.122, alpha: 0.05), dark: .rgb(1.000, 1.000, 1.000, alpha: 0.06))
        static let gold = dynamicColor(light: .rgb(0.165, 0.404, 0.906), dark: .rgb(0.427, 0.678, 1.000))
        static let teal = dynamicColor(light: .rgb(0.110, 0.612, 0.435), dark: .rgb(0.400, 0.890, 0.692))
        static let coral = dynamicColor(light: .rgb(0.788, 0.208, 0.212), dark: .rgb(1.000, 0.478, 0.478))
        static let mist = Color.primary
        static let mutedText = dynamicColor(
            light: .rgb(0.255, 0.294, 0.369, alpha: 0.78), dark: .rgb(0.871, 0.898, 0.945, alpha: 0.74))
        static let subtleText = dynamicColor(
            light: .rgb(0.255, 0.294, 0.369, alpha: 0.56), dark: .rgb(0.871, 0.898, 0.945, alpha: 0.52))
        static let textPrimary = Color.primary

        static let backdropGradient = LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static func overlay(_ opacity: Double) -> Color {
            dynamicColor(
                light: .rgb(0.071, 0.086, 0.122, alpha: min(opacity * 0.95, 1.0)),
                dark: .rgb(1.000, 1.000, 1.000, alpha: min(opacity, 1.0))
            )
        }

        static func shadow(_ opacity: Double) -> Color {
            dynamicColor(
                light: .rgb(0.071, 0.086, 0.122, alpha: min(opacity * 0.55, 1.0)),
                dark: .rgb(0.000, 0.000, 0.000, alpha: min(opacity, 1.0))
            )
        }

        static func displayFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }

        static func bodyFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular)
            -> Font
        {
            .system(size: size, weight: weight, design: .default)
        }

        static func monoFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular)
            -> Font
        {
            .system(size: size, weight: weight, design: .monospaced)
        }

        private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
            Color(
                uiColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark ? dark : light
                }
            )
        }
    }

    private extension UIColor {
        static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1.0) -> UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }

    struct NexusIOSBackdrop: View {
        var body: some View {
            ZStack {
                NexusIOSTheme.backdropGradient
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [NexusIOSTheme.overlay(0.030), .clear, NexusIOSTheme.overlay(0.018)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.overlay)
                .ignoresSafeArea()

                Circle()
                    .fill(NexusIOSTheme.gold.opacity(0.14))
                    .frame(width: 280)
                    .blur(radius: 96)
                    .offset(x: -120, y: -320)

                Circle()
                    .fill(NexusIOSTheme.teal.opacity(0.12))
                    .frame(width: 320)
                    .blur(radius: 132)
                    .offset(x: 200, y: 320)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [NexusIOSTheme.overlay(0.018), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
            }
        }
    }

    struct NexusIOSPanelModifier: ViewModifier {
        var tint: Color
        var radius: CGFloat
        var raised: Bool

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

            content
                .background {
                    shape
                        .fill((raised ? NexusIOSTheme.panelRaised : NexusIOSTheme.panel))
                        .overlay {
                            shape
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            NexusIOSTheme.overlay(0.070),
                                            .clear,
                                            tint.opacity(0.10),
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
                                        colors: [NexusIOSTheme.overlay(0.14), .clear],
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
                                .strokeBorder(NexusIOSTheme.line, lineWidth: 1)
                        }
                        .shadow(color: NexusIOSTheme.shadow(0.22), radius: raised ? 24 : 18, y: raised ? 14 : 10)
                }
        }
    }

    extension View {
        func nexusIOSPanel(tint: Color = .clear, radius: CGFloat = 24, raised: Bool = false) -> some View {
            modifier(NexusIOSPanelModifier(tint: tint, radius: radius, raised: raised))
        }

        func nexusIOSTextField(tint: Color = NexusIOSTheme.gold) -> some View {
            self
                .font(NexusIOSTheme.bodyFont(15))
                .foregroundStyle(NexusIOSTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(NexusIOSTheme.overlay(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                }
        }

        @ViewBuilder
        func nexusIOSGlassCapsule(tint: Color = NexusIOSTheme.gold, interactive: Bool = false) -> some View {
            if #available(iOS 26, *) {
                self.glassEffect(
                    (interactive
                        ? Glass.regular.tint(tint.opacity(0.16)).interactive()
                        : Glass.regular.tint(tint.opacity(0.12))),
                    in: .capsule
                )
            } else {
                self
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(tint.opacity(0.14), lineWidth: 1)
                    }
            }
        }

        @ViewBuilder
        func nexusIOSGlassRoundedRect(radius: CGFloat = 20, tint: Color = NexusIOSTheme.gold, interactive: Bool = false)
            -> some View
        {
            if #available(iOS 26, *) {
                self.glassEffect(
                    (interactive
                        ? Glass.regular.tint(tint.opacity(0.16)).interactive()
                        : Glass.regular.tint(tint.opacity(0.10))),
                    in: .rect(cornerRadius: radius)
                )
            } else {
                self
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(tint.opacity(0.14), lineWidth: 1)
                    }
            }
        }
    }

    struct NexusIOSSectionHeader: View {
        let eyebrow: String
        let title: String
        let detail: String?

        init(eyebrow: String, title: String, detail: String? = nil) {
            self.eyebrow = eyebrow
            self.title = title
            self.detail = detail
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow.uppercased())
                    .font(NexusIOSTheme.monoFont(11, relativeTo: .caption, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(NexusIOSTheme.gold)

                Text(title)
                    .font(NexusIOSTheme.displayFont(32, relativeTo: .largeTitle))
                    .foregroundStyle(NexusIOSTheme.textPrimary)

                if let detail {
                    Text(detail)
                        .font(NexusIOSTheme.bodyFont(14))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct NexusIOSStatusPill: View {
        let text: String
        let color: Color

        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(text)
                    .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
            }
            .foregroundStyle(NexusIOSTheme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .nexusIOSGlassCapsule(tint: color)
        }
    }

    struct NexusIOSMetaBadge: View {
        let icon: String
        let text: String

        var body: some View {
            Label(text, systemImage: icon)
                .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                .foregroundStyle(NexusIOSTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(NexusIOSTheme.overlay(0.045), in: Capsule())
                .overlay {
                    Capsule().stroke(NexusIOSTheme.softLine, lineWidth: 1)
                }
        }
    }

    struct NexusIOSInspectorRow: View {
        let title: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(NexusIOSTheme.monoFont(10, relativeTo: .caption2, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(NexusIOSTheme.gold)
                Text(value)
                    .font(NexusIOSTheme.bodyFont(13))
                    .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct NexusIOSPrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusIOSTheme.bodyFont(14, relativeTo: .callout, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NexusIOSTheme.gold.opacity(configuration.isPressed ? 0.84 : 0.96))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(NexusIOSTheme.gold.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: NexusIOSTheme.gold.opacity(configuration.isPressed ? 0.08 : 0.18), radius: 14, y: 8)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }

    struct NexusIOSSecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusIOSTheme.bodyFont(14, relativeTo: .callout, weight: .medium))
                .foregroundStyle(NexusIOSTheme.textPrimary.opacity(configuration.isPressed ? 0.82 : 0.94))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    NexusIOSTheme.overlay(configuration.isPressed ? 0.08 : 0.10),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NexusIOSTheme.softLine, lineWidth: 1)
                }
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }

    struct NexusIOSDangerButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusIOSTheme.bodyFont(14, relativeTo: .callout, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NexusIOSTheme.coral.opacity(configuration.isPressed ? 0.80 : 0.90))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(NexusIOSTheme.coral.opacity(0.18), lineWidth: 1)
                }
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }

    struct NexusIOSCardTitle: View {
        let eyebrow: String?
        let title: String
        let detail: String?
        var accent: Color

        init(eyebrow: String? = nil, title: String, detail: String? = nil, accent: Color = NexusIOSTheme.gold) {
            self.eyebrow = eyebrow
            self.title = title
            self.detail = detail
            self.accent = accent
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(NexusIOSTheme.monoFont(10, relativeTo: .caption2, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(NexusIOSTheme.displayFont(22, relativeTo: .title3))
                    .foregroundStyle(NexusIOSTheme.textPrimary)

                if let detail {
                    Text(detail)
                        .font(NexusIOSTheme.bodyFont(13))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
#endif
