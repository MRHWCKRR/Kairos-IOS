import SwiftUI

/// Shared visual language for the Kairos iOS client.
enum KairosColors {
    static let accent = Color(red: 0.49, green: 0.27, blue: 0.96)
    static let accentSoft = Color(red: 0.68, green: 0.49, blue: 1.00)
    static let accentDeep = Color(red: 0.30, green: 0.15, blue: 0.64)
}

extension View {
    /// The soft purple atmosphere used behind the primary Kairos surfaces.
    func kairosBackground() -> some View {
        modifier(KairosBackgroundModifier())
    }

    /// A content surface. Liquid Glass is reserved for controls/navigation.
    func kairosCard(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
            }
    }

    /// Liquid Glass for compact interactive Kairos controls.
    func kairosGlass(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        self.glassEffect(
            tint.map { .regular.tint($0) } ?? .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

private struct KairosBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black, Color(red: 0.08, green: 0.04, blue: 0.13), Color(red: 0.13, green: 0.08, blue: 0.20)]
                    : [Color(.systemBackground), Color(red: 0.91, green: 0.86, blue: 1.00), Color(red: 0.75, green: 0.63, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(KairosColors.accent.opacity(colorScheme == .dark ? 0.12 : 0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 120, y: -260)

            Circle()
                .fill(KairosColors.accentSoft.opacity(colorScheme == .dark ? 0.10 : 0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -130, y: 420)

            content
        }
    }
}
