import SwiftUI

/// A background only: no layout, hit-testing, gestures or per-frame state.
struct SoftPressSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    let opacity: Double
    var tint: Color = .primary
    var cornerRadius: CGFloat = CGFloat(PressFeedbackPolicy.rowCornerRadius)

    var body: some View {
        let duration = PressFeedbackPolicy.animationDuration(isActive: opacity > 0, reducesMotion: reducesMotion)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            .opacity(opacity)
            .animation(duration == 0 ? nil : .easeOut(duration: duration), value: opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// SwiftUI owns scroll cancellation and context-menu arbitration. Adding a
/// zero-distance drag recognizer here would compete with both.
struct MusicTrackPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                SoftPressSurface(opacity: configuration.isPressed ? PressFeedbackPolicy.rowOpacity : 0)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
    }
}
