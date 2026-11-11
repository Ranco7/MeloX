import SwiftUI

struct LyricPressInteraction<Content: View>: View {
    let isSelected: Bool
    let allowsTap: Bool
    let allowsLongPress: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    private let content: (Double) -> Content

    @State private var suppressesTap = false

    init(
        isSelected: Bool,
        allowsTap: Bool = true,
        allowsLongPress: Bool = true,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        @ViewBuilder content: @escaping (Double) -> Content
    ) {
        self.isSelected = isSelected
        self.allowsTap = allowsTap
        self.allowsLongPress = allowsLongPress
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.content = content
    }

    var body: some View {
        Button(action: performTap) {
            LyricPressLabel(
                content: content
            )
            .contentShape(.rect)
        }
        .buttonStyle(
            LyricPressButtonStyle(
                isSelected: isSelected
            )
        )
        .simultaneousGesture(
            LongPressGesture()
            .onEnded { didComplete in
                guard didComplete, allowsLongPress else { return }
                suppressesTap = true
                onLongPress()
            },
            isEnabled: allowsLongPress
        )
        .accessibilityActions {
            if allowsLongPress {
                Button("ui.lyrics.share.title") { onLongPress() }
            }
        }
        .onChange(of: isSelected) { _, isSelected in
            if !isSelected {
                suppressesTap = false
            }
        }
        .allowsHitTesting(allowsTap || allowsLongPress)
    }

    private func performTap() {
        guard allowsTap else { return }
        guard !suppressesTap else {
            suppressesTap = false
            return
        }
        onTap()
    }
}

private struct LyricPressLabel<Content: View>: View {
    @Environment(\.lyricPressBackgroundProgress)
    private var backgroundProgress

    let content: (Double) -> Content

    var body: some View {
        content(backgroundProgress)
    }
}

private struct LyricPressButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.lyricPressBackgroundProgress, configuration.isPressed || isSelected ? 1 : 0)
    }
}

private struct LyricPressBackgroundProgressKey: EnvironmentKey {
    static let defaultValue = 0.0
}

private extension EnvironmentValues {
    var lyricPressBackgroundProgress: Double {
        get { self[LyricPressBackgroundProgressKey.self] }
        set { self[LyricPressBackgroundProgressKey.self] = newValue }
    }
}
