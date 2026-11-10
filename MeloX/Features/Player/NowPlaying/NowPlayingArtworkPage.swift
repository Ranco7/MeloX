import SwiftUI

struct NowPlayingArtworkPage: View {
    static let pausedArtworkScale: CGFloat = 0.82

    let song: Song
    let layout: NowPlayingPortraitLayout
    let artworkNamespace: Namespace.ID
    let usesArtworkTransition: Bool
    let showsArtwork: Bool
    let onArtworkFrameChange: (CGRect) -> Void
    let onMetadataHeightChange: (CGFloat) -> Void

    init(
        song: Song,
        layout: NowPlayingPortraitLayout,
        artworkNamespace: Namespace.ID,
        usesArtworkTransition: Bool = true,
        showsArtwork: Bool = true,
        onArtworkFrameChange:
            @escaping (CGRect) -> Void = { _ in },
        onMetadataHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.song = song
        self.layout = layout
        self.artworkNamespace = artworkNamespace
        self.usesArtworkTransition = usesArtworkTransition
        self.showsArtwork = showsArtwork
        self.onArtworkFrameChange = onArtworkFrameChange
        self.onMetadataHeightChange = onMetadataHeightChange
    }

    var body: some View {
        GeometryReader { proxy in
            // Keep the existing page identity while resizing. Metadata reports
            // its full-width intrinsic height so artwork yields space first;
            // basedOnSize leaves fitted windows static.
            ScrollView {
                content(availableHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    private func content(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.artworkTopSpacing)

            artwork

            Color.clear.frame(height: layout.artworkBottomSpacing)

            metadata
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    onMetadataHeightChange(height)
                }

            Color.clear.frame(height: layout.metadataBottomSpacing)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: availableHeight,
            alignment: .top
        )
    }

    private var artwork: some View {
        ZStack {
            if showsArtwork {
                NowPlayingPortraitArtwork(song: song, isArtworkPage: true)
                    .frame(width: layout.artworkSide, height: layout.artworkSide)
                    .nowPlayingArtworkTransition(
                        id: song.id, in: artworkNamespace,
                        isEnabled: usesArtworkTransition, isSource: true
                    )
            } else {
                Color.clear
                    .frame(
                        width: layout.artworkSide,
                        height: layout.artworkSide
                    )
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(
                            in: .named(
                                NowPlayingPortraitCoordinateSpace.name
                            )
                        )
                    } action: { newFrame in
                        onArtworkFrameChange(newFrame)
                    }
            }
        }
        .frame(
            width: layout.artworkSide,
            height: layout.artworkSide
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(
            L10n.format(
                "ui.song.artwork_accessibility",
                song.name
            )
        )
        .accessibilityHidden(!showsArtwork)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(song.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .layoutPriority(1)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                NowPlayingSongActions(
                    song: song,
                    showsFavoriteButton: false
                )
                .fixedSize()
            }

            Text(song.artistText)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            NowPlayingMetadataBadges()
        }
        .padding(.horizontal, layout.horizontalMargin)
    }
}

/// The heart-mode and listen-together capsules get their own row so they can
/// never compete with the song title or the trailing actions.
private struct NowPlayingMetadataBadges: View {
    @Environment(PlayerStore.self) private var player
    @Environment(ListenTogetherStore.self) private var listenTogether

    var body: some View {
        if player.isHeartModeActive || listenTogether.room != nil {
            HStack(spacing: 8) {
                HeartModeNowPlayingBadge()
                ListenTogetherNowPlayingBadge()
            }
            .padding(.top, 2)
        }
    }
}
