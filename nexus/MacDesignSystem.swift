#if os(macOS)
    import SwiftUI

    enum NexusMacTheme {
        static let backgroundTop = Color(red: 0.15, green: 0.16, blue: 0.19)
        static let backgroundBottom = Color(red: 0.10, green: 0.11, blue: 0.14)
        static let panel = Color(red: 0.16, green: 0.17, blue: 0.20)
        static let panelRaised = Color(red: 0.20, green: 0.21, blue: 0.25)
        static let line = Color.white.opacity(0.10)
        static let softLine = Color.white.opacity(0.05)
        static let gold = Color(red: 0.19, green: 0.55, blue: 0.96)
        static let teal = Color(red: 0.35, green: 0.79, blue: 0.61)
        static let coral = Color(red: 0.98, green: 0.46, blue: 0.43)
        static let mist = Color(red: 0.97, green: 0.98, blue: 1.00)
        static let mutedText = Color.white.opacity(0.64)

        static let backdropGradient = LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static func statusColor(_ state: String) -> Color {
            switch state.lowercased() {
            case "available", "ready", "enabled", "launchable":
                teal
            case "unavailable", "interrupted", "disabled", "blocked":
                gold
            case "broken", "failed", "misconfigured", "exited":
                coral
            default:
                Color.white.opacity(0.7)
            }
        }

        static func displayFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        static func bodyFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        static func monoFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }

    struct NexusBackdrop: View {
        var body: some View {
            ZStack {
                NexusMacTheme.backdropGradient
                    .ignoresSafeArea()

                Circle()
                    .fill(NexusMacTheme.gold.opacity(0.16))
                    .frame(width: 280)
                    .blur(radius: 90)
                    .offset(x: -220, y: -260)

                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 360)
                    .blur(radius: 120)
                    .offset(x: 260, y: -200)

                Circle()
                    .fill(NexusMacTheme.teal.opacity(0.08))
                    .frame(width: 320)
                    .blur(radius: 120)
                    .offset(x: 260, y: 260)
            }
        }
    }

    struct NexusPanelModifier: ViewModifier {
        var tint: Color
        var radius: CGFloat

        func body(content: Content) -> some View {
            content
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(NexusMacTheme.panel.opacity(0.95))
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.06), .clear, tint.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(NexusMacTheme.line, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
                )
        }
    }

    extension View {
        func nexusPanel(tint: Color = .clear, radius: CGFloat = 22) -> some View {
            modifier(NexusPanelModifier(tint: tint, radius: radius))
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
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(NexusMacTheme.monoFont(11, relativeTo: .caption))
                    .tracking(2.4)
                    .foregroundStyle(NexusMacTheme.gold)

                Text(title)
                    .font(NexusMacTheme.displayFont(28, relativeTo: .largeTitle))
                    .foregroundStyle(NexusMacTheme.mist)

                if let detail {
                    Text(detail)
                        .font(NexusMacTheme.bodyFont(14))
                        .foregroundStyle(NexusMacTheme.mutedText)
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
                    .tracking(2.2)
                    .foregroundStyle(accent)

                Text(value)
                    .font(NexusMacTheme.displayFont(24, relativeTo: .title))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(NexusMacTheme.bodyFont(13, relativeTo: .caption))
                    .foregroundStyle(NexusMacTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .nexusPanel(tint: accent, radius: 18)
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
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.18), in: Capsule())
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
                .foregroundStyle(NexusMacTheme.mist)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: Capsule())
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
                    .foregroundStyle(.white.opacity(0.92))
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
                .background(NexusMacTheme.gold.opacity(configuration.isPressed ? 0.76 : 0.96), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
        }
    }

    struct NexusSecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(NexusMacTheme.bodyFont(13, relativeTo: .callout).weight(.medium))
                .foregroundStyle(.white.opacity(configuration.isPressed ? 0.8 : 0.94))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(configuration.isPressed ? 0.07 : 0.10), in: Capsule())
                .overlay {
                    Capsule().stroke(NexusMacTheme.softLine, lineWidth: 1)
                }
        }
    }
#endif
