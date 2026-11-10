import SwiftUI

struct TabletMiniPlayerView: View {
    static let controlWidth: CGFloat = 44
    static let playbackControlWidth: CGFloat = 48
    static let titleMinimumWidth: CGFloat = 140
    static let clusterSpacing: CGFloat = 10
    static let leadingPadding: CGFloat = 10
    static let trailingPadding: CGFloat = 6
    static let artworkSize: CGFloat = 40
    /// 44pt controls + 10pt on each side yield a 64pt capsule and 12pt
    /// of vertical space around the 40pt artwork.
    static let verticalPadding: CGFloat = 10
    // Transport cluster (4 controls + play) + title minimum + 3 actions,
    // the gaps between the three clusters, and the bar's own padding.
    static let minimumControlsWidth: CGFloat =
        controlWidth * 4 + playbackControlWidth
        + titleMinimumWidth
        + controlWidth * 3
        + clusterSpacing * 2
        + leadingPadding + trailingPadding

    @Environment(PlayerStore.self) private var player
    @Environment(\.colorScheme) private var colorScheme

    let collectionPalette: ArtworkDetailPalette?
    let usesWideLayout: Bool
    let onOpen: (NowPlayingPage?) -> Void

    var body: some View {
        if let song = player.currentSong {
            Group {
                if usesWideLayout {
                    controls(for: song)
                        .frame(
                            minWidth: Self.minimumControlsWidth,
                            maxWidth: .infinity
                        )
                        .padding(.leading, Self.leadingPadding)
                        .padding(.trailing, Self.trailingPadding)
                        .padding(.vertical, Self.verticalPadding)
                } else {
                    MiniPlayerView {
                        onOpen(nil)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: MusicCollectionLayout.miniPlayerMaximumWidth)
            // The glass is only the bar's backdrop. When the controls sat
            // inside the glass layer, opening the ⋯ menu morphed the whole
            // glass and hid the controls, and holding the bar let the press
            // effect darken the entire capsule.
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(glass, in: .capsule)
                    .allowsHitTesting(false)
            }
            .overlay {
                if let collectionPalette {
                    Capsule()
                        .strokeBorder(collectionPalette.edgeColor.opacity(0.18), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .background {
                Color.clear
                    .contentShape(.capsule)
                    .onTapGesture { onOpen(nil) }
            }
            .environment(\.colorScheme, collectionPalette?.colorScheme ?? colorScheme)
        }
    }

    private var glass: Glass {
        if let collectionPalette {
            return .regular.tint(collectionPalette.backgroundColor.opacity(0.32))
        }
        return .regular
    }

    private func controls(for song: Song) -> some View {
        HStack(spacing: Self.clusterSpacing) {
            HStack(spacing: 0) {
                control(
                    "shuffle", title: L10n.string(player.isShuffled ? "ui.player.shuffle_off" : "ui.player.shuffle_on"),
                    font: .footnote.weight(.semibold), isOn: player.isShuffled, action: player.toggleShuffle
                )
                control("backward.fill", title: L10n.string("ui.player.previous"), font: .title3.weight(.semibold)) {
                    Task { await player.previous() }
                }
                playbackButton
                control("forward.fill", title: L10n.string("ui.player.next"), font: .title3.weight(.semibold)) {
                    Task { await player.next() }
                }
                control(
                    player.repeatMode.systemImage, title: player.repeatMode.accessibilityTitle,
                    font: .footnote.weight(.semibold), isOn: player.repeatMode != .off, action: player.cycleRepeatMode
                )
            }

            Button {
                onOpen(nil)
            } label: {
                HStack(spacing: 12) {
                    ArtworkImage(url: song.album?.artworkURL, cornerRadius: 5)
                        .frame(width: Self.artworkSize, height: Self.artworkSize)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name)
                            .font(.subheadline.weight(.semibold))
                        Text(song.artistText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .frame(minWidth: Self.titleMinimumWidth, maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: song.name))
            .accessibilityValue(Text(verbatim: song.artistText))

            HStack(spacing: 0) {
                NowPlayingSongActions(song: song, showsFavoriteButton: false, usesCompactMenu: true)
                    .frame(width: Self.controlWidth, height: 44)
                if !song.isPodcastProgram {
                    control("quote.bubble", title: L10n.string("ui.settings.lyrics.title")) {
                        onOpen(.lyrics)
                    }
                }
                control("list.bullet", title: L10n.string("ui.player.queue")) {
                    onOpen(.queue)
                }
            }
        }
    }

    private var playbackButton: some View {
        Button(action: player.togglePlayback) {
            Group {
                if player.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle.weight(.semibold))
                }
            }
            .frame(width: Self.playbackControlWidth, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? L10n.string("ui.player.pause") : L10n.string("ui.common.play"))
    }

    private func control(
        _ icon: String, title: String, font: Font = .body.weight(.semibold), width: CGFloat = TabletMiniPlayerView.controlWidth,
        isOn: Bool? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(font)
                .foregroundStyle(isOn.map { $0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary) } ?? AnyShapeStyle(.primary))
                .frame(width: width, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
    }
}
