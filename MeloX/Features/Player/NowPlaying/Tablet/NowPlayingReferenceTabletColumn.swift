import SwiftUI

struct NowPlayingReferenceTabletColumn: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    let song: Song
    let layout: NowPlayingReferenceTabletLayout

    private var isArtworkExpanded: Bool {
        player.isPlaying || !settings.shrinksPausedArtwork
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NowPlayingReferenceArtwork(song: song, artworkSize: layout.artworkSize)
                .frame(maxWidth: .infinity)
                .padding(.top, layout.artworkTopInset)
                .animation(
                    accessibilityReduceMotion ? nil : .smooth(duration: 0.48),
                    value: isArtworkExpanded
                )

            NowPlayingReferenceTabletMetadata(song: song)
                .padding(.top, layout.metadataTopInset)

            NowPlayingReferenceProgressControl(song: song)
                .padding(.top, 23 * layout.elementScale)

            NowPlayingReferenceTransportControls(presentation: .tablet)
                .padding(.top, 22 * layout.elementScale)

            NowPlayingReferenceVolumeControl()
                .padding(.top, 12)
        }
        .padding(.bottom, 20)
        .foregroundStyle(.white)
    }
}

private struct NowPlayingReferenceTabletMetadata: View {
    let song: Song

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(song.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    [song.artistText, song.album?.name]
                        .compactMap { $0 }
                        .joined(separator: L10n.string("ui.common.title_detail_separator"))
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)

                HStack(spacing: 8) {
                    HeartModeNowPlayingBadge(expandsTouchTarget: true)
                    ListenTogetherNowPlayingBadge(expandsTouchTarget: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            NowPlayingSongActions(song: song, offersAirPlayMenu: true)
                .fixedSize()
        }
    }
}
