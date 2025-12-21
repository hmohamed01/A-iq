import SwiftUI

// MARK: - A-IQ Design System
// Clean, minimal design aesthetic with paper-white backgrounds and soft shadows

// MARK: - Design Tokens

/// Color palette for A-IQ
enum AIQColors {
    // Backgrounds
    static let paperWhite = Color(white: 0.995)
    static let cardBackground = Color.white
    static let sidebarBackground = Color(white: 0.97).opacity(0.85)

    // Accent - matches app icon blue
    static let accent = Color(red: 0.18, green: 0.49, blue: 0.82) // #2D7DD2
    static let accentLight = Color(red: 0.29, green: 0.62, blue: 1.0) // #4A9EFF

    // Text
    static let primaryText = Color(white: 0.15)
    static let secondaryText = Color(white: 0.45)
    static let tertiaryText = Color(white: 0.65)

    // Status colors
    static let authentic = Color(red: 0.2, green: 0.7, blue: 0.4)
    static let uncertain = Color(red: 0.95, green: 0.7, blue: 0.2)
    static let aiGenerated = Color(red: 0.9, green: 0.35, blue: 0.35)

    // Borders & Shadows
    static let subtleBorder = Color(white: 0.9)
    static let dropShadow = Color.black.opacity(0.06)
}

/// Spacing system
enum AIQSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Corner radius system
enum AIQRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let card: CGFloat = 14
}

// MARK: - Card Style

struct AIQCardStyle: ViewModifier {
    var padding: CGFloat = AIQSpacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AIQColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AIQRadius.card, style: .continuous))
            .shadow(color: AIQColors.dropShadow, radius: 8, x: 0, y: 2)
    }
}

extension View {
    func aiqCard(padding: CGFloat = AIQSpacing.lg) -> some View {
        modifier(AIQCardStyle(padding: padding))
    }
}

// MARK: - Button Styles

struct AIQPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, AIQSpacing.lg)
            .padding(.vertical, AIQSpacing.sm + 2)
            .background(AIQColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: AIQRadius.sm, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AIQSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(AIQColors.accent)
            .padding(.horizontal, AIQSpacing.md)
            .padding(.vertical, AIQSpacing.sm)
            .background(AIQColors.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AIQRadius.sm, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
