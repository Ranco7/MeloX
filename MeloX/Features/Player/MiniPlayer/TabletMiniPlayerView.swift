import SwiftUI

struct TabletMiniPlayerView: View {
    // 240pt icon cluster + 180pt title minimum + 162pt action cluster + spacing and padding.
    static let minimumControlsWidth: CGFloat = 618

    @Environment(PlayerStore.self) private var player
    @Environment(\.colorScheme) private var colorScheme

    let artworkTransitionID: String
    let artworkTransitionNamespace: Namespace.ID
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
                        .padding(.leading, 10)
                        .padding(.trailing, 6)
                        .padding(.vertical, 10)
                } else {
                    MiniPlayerView(
                        artworkTransitionID: artworkTransitionID,
                        artworkTransitionNamespace:
                            artworkTransitionNamespace
                    ) {
                        onOpen(nil)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: MusicCollectionLayout.miniPlayerMaximumWidth)
            .glassEffect(glass, in: .capsule)
            .overlay {
                if let collectionPalette {
                    Capsule()
                        .strokeBorder(collectionPalette.edgeColor.opacity(0.18), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .environment(\.colorScheme, collectionPalette?.colorScheme ?? colorScheme)
        }
    }

    private var glass: Glass {
        if let collectionPalette {
            return .regular.tint(collectionPalette.backgroundColor.opacity(0.32))
        }
        return .regular.interactive()
    }

    private func controls(for song: Song) -> some View {
        HStack(spacing: 10) {
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
                HStack(spacing: 9) {
                    ArtworkImage(url: song.album?.artworkURL, cornerRadius: 7)
                        .frame(width: 44, height: 44)
                        .matchedTransitionSource(id: artworkTransitionID, in: artworkTransitionNamespace)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name)
                            .font(.subheadline.weight(.semibold))
                        Text(song.artistText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: song.name))
            .accessibilityValue(Text(verbatim: song.artistText))

            HStack(spacing: 0) {
                NowPlayingSongActions(song: song, showsFavoriteButton: false, usesCompactMenu: true)
                    .frame(width: 54, height: 44)
                if !song.isPodcastProgram {
                    control("quote.bubble", title: L10n.string("ui.settings.lyrics.title"), width: 54) {
                        onOpen(.lyrics)
                    }
                }
                control("list.bullet", title: L10n.string("ui.player.queue"), width: 54) {
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
            .frame(width: 48, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? L10n.string("ui.player.pause") : L10n.string("ui.common.play"))
    }

    private func control(
        _ icon: String, title: String, font: Font = .body.weight(.semibold), width: CGFloat = 48,
        isOn: Bool? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(font)
                .foregroundStyle(isOn.map { $0 ? Color.accentColor : .secondary } ?? .primary)
                .frame(width: width, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
    }
}
