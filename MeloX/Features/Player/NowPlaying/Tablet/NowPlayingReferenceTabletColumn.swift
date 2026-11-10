import SwiftUI

struct NowPlayingReferenceTabletColumn: View {
    let song: Song
    let layout: NowPlayingReferenceTabletLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NowPlayingPortraitArtwork(song: song, isArtworkPage: true, usesReferenceAppearance: true)
                .frame(width: layout.playingArtworkSize, height: layout.playingArtworkSize)
                .frame(width: layout.artworkSize, height: layout.artworkSize)
                .frame(maxWidth: .infinity)
                .padding(.top, layout.artworkTopInset)

            NowPlayingReferenceTabletMetadata(song: song)
                .padding(.top, layout.metadataTopInset)

            NowPlayingProgressControl(song: song, usesReferenceLayout: true)
                .padding(.top, 23 * layout.elementScale)

            NowPlayingTransportControls(presentation: .referenceTablet)
                .padding(.top, 22 * layout.elementScale)

            NowPlayingVolumeControl(usesReferenceLayout: true)
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

                // Borrow hit space from passive metadata above, leaving the
                // following 23pt gap available to the progress slider.
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
