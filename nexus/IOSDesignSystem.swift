#if os(iOS)
    import SwiftUI

    enum NexusIOSTheme {
        static let backgroundTop = Color(red: 0.07, green: 0.09, blue: 0.13)
        static let backgroundBottom = Color(red: 0.03, green: 0.04, blue: 0.07)
        static let panel = Color(red: 0.11, green: 0.13, blue: 0.18)
        static let panelRaised = Color(red: 0.14, green: 0.16, blue: 0.22)
        static let line = Color.white.opacity(0.10)
        static let softLine = Color.white.opacity(0.06)
        static let gold = Color(red: 0.19, green: 0.55, blue: 0.96)
        static let teal = Color(red: 0.35, green: 0.79, blue: 0.61)
        static let coral = Color(red: 0.98, green: 0.46, blue: 0.43)
        static let mist = Color(red: 0.97, green: 0.98, blue: 1.0)
        static let mutedText = Color.white.opacity(0.68)

        static let backdropGradient = LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static func displayFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        static func bodyFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular)
            -> Font
        {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func monoFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular)
            -> Font
        {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    struct NexusIOSBackdrop: View {
        var body: some View {
            ZStack {
                NexusIOSTheme.backdropGradient
                    .ignoresSafeArea()

                Circle()
                    .fill(NexusIOSTheme.gold.opacity(0.18))
                    .frame(width: 260)
                    .blur(radius: 90)
                    .offset(x: -130, y: -320)

                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 260)
                    .blur(radius: 110)
                    .offset(x: 150, y: -210)

                Circle()
                    .fill(NexusIOSTheme.teal.opacity(0.14))
                    .frame(width: 320)
                    .blur(radius: 130)
                    .offset(x: 180, y: 300)

                LinearGradient(
                    colors: [Color.white.opacity(0.06), .clear, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.screen)
                .ignoresSafeArea()
            }
        }
    }

    struct NexusIOSPanelModifier: ViewModifier {
        var tint: Color
        var radius: CGFloat
        var raised: Bool

        func body(content: Content) -> some View {
            content
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill((raised ? NexusIOSTheme.panelRaised : NexusIOSTheme.panel).opacity(0.94))
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.08), .clear, tint.opacity(0.14)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(0.42), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 1)
                                .padding(.horizontal, 18)
                                .padding(.top, 1)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(NexusIOSTheme.line, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.24), radius: 20, y: 10)
                )
        }
    }

    extension View {
        func nexusIOSPanel(tint: Color = .clear, radius: CGFloat = 24, raised: Bool = false) -> some View {
            modifier(NexusIOSPanelModifier(tint: tint, radius: radius, raised: raised))
        }

        func nexusIOSTextField(tint: Color = NexusIOSTheme.gold) -> some View {
            self
                .font(NexusIOSTheme.bodyFont(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
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
                    .tracking(2.8)
                    .foregroundStyle(NexusIOSTheme.gold)

                Text(title)
                    .font(NexusIOSTheme.displayFont(32, relativeTo: .largeTitle))
                    .foregroundStyle(NexusIOSTheme.mist)

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
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(color.opacity(0.18), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.28), lineWidth: 1)
            }
        }
    }

    struct NexusIOSMetaBadge: View {
        let icon: String
        let text: String

        var body: some View {
            Label(text, systemImage: icon)
                .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                .foregroundStyle(NexusIOSTheme.mist)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: Capsule())
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
                    .foregroundStyle(.white.opacity(0.92))
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
                .background(NexusIOSTheme.gold.opacity(configuration.isPressed ? 0.76 : 0.96), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
        }
    }

    struct NexusIOSSecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusIOSTheme.bodyFont(14, relativeTo: .callout, weight: .medium))
                .foregroundStyle(.white.opacity(configuration.isPressed ? 0.82 : 0.94))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.11), in: Capsule())
                .overlay {
                    Capsule().stroke(NexusIOSTheme.softLine, lineWidth: 1)
                }
        }
    }

    struct NexusIOSDangerButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusIOSTheme.bodyFont(14, relativeTo: .callout, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(NexusIOSTheme.coral.opacity(configuration.isPressed ? 0.76 : 0.88), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
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
                    .foregroundStyle(.white)

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
