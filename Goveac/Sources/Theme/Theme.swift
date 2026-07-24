import SwiftUI

enum Theme {
    static let bgTop = Color(red: 0.07, green: 0.09, blue: 0.12)
    static let bgBottom = Color(red: 0.11, green: 0.13, blue: 0.16)
    static let panel = Color(red: 0.14, green: 0.16, blue: 0.20).opacity(0.72)
    static let panelStroke = Color.white.opacity(0.08)
    static let textPrimary = Color(red: 0.94, green: 0.95, blue: 0.96)
    static let textSecondary = Color(red: 0.62, green: 0.66, blue: 0.72)
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.28)
    static let accentSoft = Color(red: 1.0, green: 0.78, blue: 0.42).opacity(0.18)
    static let danger = Color(red: 0.92, green: 0.38, blue: 0.34)
    static let online = Color(red: 0.42, green: 0.82, blue: 0.55)
    static let offline = Color(red: 0.52, green: 0.55, blue: 0.60)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [bgTop, bgBottom, Color(red: 0.09, green: 0.10, blue: 0.13)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glowGradient: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(0.22), accent.opacity(0.06), .clear],
            center: .topTrailing,
            startRadius: 20,
            endRadius: 420
        )
    }
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.panelStroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func panelStyle() -> some View {
        modifier(PanelBackground())
    }
}
