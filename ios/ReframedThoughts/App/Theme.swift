import SwiftUI

/// Semantic design tokens. Colours live in Assets.xcassets with light/dark variants; names here must match.
enum Theme {
    static let colorNames = ["Forest", "OnForest", "Clay", "OnClay", "Sand", "Surface", "Bark", "Muted", "Border"]

    static let radius: CGFloat = 16
    static let spacing: CGFloat = 20
}

extension Color {
    static let forest = Color("Forest")      // primary: buttons, tint, progress
    static let onForest = Color("OnForest")  // text on forest
    static let clay = Color("Clay")          // accent: record button, highlights
    static let onClay = Color("OnClay")
    static let sand = Color("Sand")          // screen background
    static let surface = Color("Surface")    // cards
    static let bark = Color("Bark")          // primary text
    static let muted = Color("Muted")        // secondary text
    static let border = Color("Border")
}

extension Font {
    /// Serif display for the words that matter (affirmations, titles); system sans for everything else. Scales with Dynamic Type.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font { .system(style, design: .serif, weight: weight) }
    /// Fixed-size serif; only for a number driven by `@ScaledMetric` (countdowns).
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .serif) }
}

/// Rounded, warm card surface.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(Theme.spacing)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}
extension View { func card() -> some View { modifier(CardStyle()) } }

/// Full-width forest-green primary action.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).foregroundStyle(Color.onForest)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.forest.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
/// Quiet secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium)).foregroundStyle(Color.forest)
            .frame(maxWidth: .infinity, minHeight: 48)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
/// The big round record control, in clay.
struct RecordButtonStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.labelStyle(.iconOnly).font(.system(size: 36, weight: .semibold)).foregroundStyle(Color.onClay)
            .frame(width: 104, height: 104)
            .background(Circle().fill(active ? Color.forest : Color.clay))
            .shadow(color: (active ? Color.forest : Color.clay).opacity(0.35), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
