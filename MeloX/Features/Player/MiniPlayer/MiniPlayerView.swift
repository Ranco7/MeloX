import SwiftUI

struct MiniPlayerView: View {
    /// Keeps every transport control at the HIG minimum touch size.
    static let minimumTouchTarget: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(PlayerStore.self) private var player

    let onExpand: () -> Void

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: isInline ? 8 : 10) {
                Button(action: onExpand) {
                    HStack(spacing: isInline ? 8 : 10) {
                        ArtworkImage(url: song.album?.artworkURL, cornerRadius: 6)
                            .frame(width: artworkSize, height: artworkSize)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if !isInline {
                                Text(song.artistText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: song.name))
                .accessibilityValue(Text(verbatim: song.artistText))

                if player.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: Self.minimumTouchTarget, height: Self.minimumTouchTarget)
                        .accessibilityHidden(true)
                } else {
                    Button {
                        player.togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(
                                        .replace.downUp.wholeSymbol,
                                        options: .speed(1.6)
                                    )
                            )
                            .animation(
                                accessibilityReduceMotion
                                    ? nil
                                    : .snappy(duration: 0.2, extraBounce: 0),
                                value: player.isPlaying
                            )
                            .frame(width: Self.minimumTouchTarget, height: Self.minimumTouchTarget)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        player.isPlaying
                            ? L10n.string("ui.player.pause")
                            : L10n.string("ui.common.play")
                    )
                }

                if !isInline {
                    Button {
                        Task { await player.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: Self.minimumTouchTarget, height: Self.minimumTouchTarget)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ui.player.next")
                }
            }
            .padding(.horizontal, isInline ? 8 : 12)
            .padding(.vertical, isInline ? 3 : 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .background {
                // Fill the gaps without turning transport buttons into expand actions.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: onExpand)
            }
            .simultaneousGesture(trackSwipeGesture)
            .accessibilityAction(named: L10n.string("ui.player.previous")) {
                Task { await player.previous() }
            }
            .accessibilityAction(named: L10n.string("ui.player.next")) {
                Task { await player.next() }
            }
        }
    }

    private var isInline: Bool {
        placement == .inline
    }

    private var artworkSize: CGFloat {
        isInline ? 30 : 40
    }

    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    Task { await player.next() }
                } else {
                    Task { await player.previous() }
                }
            }
    }
}
