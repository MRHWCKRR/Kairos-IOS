import SwiftUI
import UIKit

/// Shared visual language for the Kairos iOS client.
enum KairosColors {
    static let accent = Color(red: 0.49, green: 0.27, blue: 0.96)
    static let accentSoft = Color(red: 0.68, green: 0.49, blue: 1.00)
    static let accentDeep = Color(red: 0.30, green: 0.15, blue: 0.64)

    static func accent(for theme: String?) -> Color {
        switch theme {
        case "blue": return Color(red: 0.20, green: 0.45, blue: 0.95)
        case "green": return Color(red: 0.18, green: 0.62, blue: 0.40)
        default: return accent
        }
    }
}

extension View {
    func kairosBackground() -> some View { modifier(KairosBackgroundModifier()) }

    func kairosCard(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
            }
    }

    func kairosGlass(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        self.glassEffect(
            tint.map { .regular.tint($0) } ?? .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
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
                .overlay { accent.opacity(colorScheme == .dark ? 0.20 : 0.14) }
        case "minimal":
            Color(.systemBackground)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(accent.opacity(colorScheme == .dark ? 0.10 : 0.07))
                        .frame(width: 280, height: 280)
                        .blur(radius: 80)
                        .offset(x: 90, y: -100)
                }
        default:
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black, accent.opacity(0.30), accent.opacity(0.16)]
                    : [Color(.systemBackground), accent.opacity(0.16), accent.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.12 : 0.10))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: 120, y: -260)
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.09 : 0.14))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: -130, y: 420)
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
