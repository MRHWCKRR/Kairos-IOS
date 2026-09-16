import SwiftUI
import UIKit

/// Shared visual language for the Kairos iOS client.
///
/// The visual system intentionally follows familiar iOS conventions while giving
/// Kairos a distinct content layer: quiet chrome, expressive data, restrained
/// accent colour, generous spacing, and translucent controls.
enum KairosColors {
    static let accent = Color(red: 0.49, green: 0.27, blue: 0.96)
    static let accentSoft = Color(red: 0.68, green: 0.49, blue: 1.00)
    static let accentDeep = Color(red: 0.30, green: 0.15, blue: 0.64)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary

    static func accent(for theme: String?) -> Color {
        switch theme {
        case "blue": return Color(red: 0.20, green: 0.45, blue: 0.95)
        case "green": return Color(red: 0.18, green: 0.62, blue: 0.40)
        case "orange": return Color(red: 0.95, green: 0.42, blue: 0.16)
        case "pink": return Color(red: 0.90, green: 0.25, blue: 0.58)
        case "red": return Color(red: 0.92, green: 0.24, blue: 0.28)
        default: return accent
        }
    }
}

enum KairosMetrics {
    static let pageHorizontal: CGFloat = 20
    static let sectionSpacing: CGFloat = 30
    static let cardRadius: CGFloat = 26
    static let smallRadius: CGFloat = 16
}

extension View {
    func kairosBackground() -> some View { modifier(KairosBackgroundModifier()) }

    /// A quieter material surface for primary content. Prefer this over custom
    /// shadows/borders so every screen shares the same depth language.
    func kairosCard(cornerRadius: CGFloat = KairosMetrics.cardRadius) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
            }
    }

    /// Native iOS 26 Liquid Glass surface for controls and floating UI.
    func kairosGlass(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        self.glassEffect(
            tint.map { .regular.tint($0) } ?? .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    func kairosPill(tint: Color? = nil) -> some View {
        self.glassEffect(
            tint.map { .regular.tint($0) } ?? .regular,
            in: Capsule()
        )
    }

    func kairosSectionTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .tracking(-0.2)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct KairosBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(UserProfileRepository.self) private var profileRepo

    private var settings: KairosAppearanceSettings? { profileRepo.appearanceSettings }
    private var accent: Color { KairosColors.accent(for: settings?.theme) }

    func body(content: Content) -> some View {
        ZStack {
            background.ignoresSafeArea()
            content
                .font(kairosFont(settings?.font))
                .foregroundStyle(kairosTextColor(settings?.textColor))
        }
    }

    @ViewBuilder
    private var background: some View {
        if let value = settings?.customBackground, !value.isEmpty,
           let url = URL(string: value), url.scheme != nil {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    styledBackground
                }
            }
        } else if let value = settings?.customBackground, !value.isEmpty,
                  let image = UIImage(named: value) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            styledBackground
        }
    }

    @ViewBuilder
    private var styledBackground: some View {
        switch settings?.background {
        case "solid":
            Color(.systemBackground)
        case "minimal":
            Color(.systemBackground)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(accent.opacity(colorScheme == .dark ? 0.11 : 0.07))
                        .frame(width: 300, height: 300)
                        .blur(radius: 90)
                        .offset(x: 100, y: -120)
                }
        default:
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black, accent.opacity(0.24), Color.black]
                    : [Color(.systemBackground), accent.opacity(0.08), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.10 : 0.08))
                    .frame(width: 320, height: 320)
                    .blur(radius: 100)
                    .offset(x: 130, y: -150)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.07 : 0.05))
                    .frame(width: 260, height: 260)
                    .blur(radius: 100)
                    .offset(x: -110, y: 130)
            }
        }
    }
}

func kairosFont(_ value: String?) -> Font {
    switch value {
    case "rounded": return .system(.body, design: .rounded)
    case "serif": return .system(.body, design: .serif)
    case "monospaced": return .system(.body, design: .monospaced)
    default: return .system(.body, design: .default)
    }
}

func kairosTextColor(_ value: String?) -> Color {
    switch value {
    case "white": return .white
    case "black": return .black
    default: return .primary
    }
}
