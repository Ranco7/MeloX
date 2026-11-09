import SwiftUI

struct NowPlayingArtworkPage: View {
    static let pausedArtworkScale: CGFloat = 0.74

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    let song: Song
    let layout: NowPlayingPortraitLayout
    let artworkNamespace: Namespace.ID
    let usesArtworkTransition: Bool
    let showsArtwork: Bool
    let onArtworkFrameChange: (CGRect) -> Void

    @State private var artworkBounceScale: CGFloat = 1

    init(
        song: Song,
        layout: NowPlayingPortraitLayout,
        artworkNamespace: Namespace.ID,
        usesArtworkTransition: Bool = true,
        showsArtwork: Bool = true,
        onArtworkFrameChange:
            @escaping (CGRect) -> Void = { _ in }
    ) {
        self.song = song
        self.layout = layout
        self.artworkNamespace = artworkNamespace
        self.usesArtworkTransition = usesArtworkTransition
        self.showsArtwork = showsArtwork
        self.onArtworkFrameChange = onArtworkFrameChange
    }

    private var isArtworkExpanded: Bool {
        player.isPlaying || !settings.shrinksPausedArtwork
    }

    var body: some View {
        GeometryReader { proxy in
            // Always size-based scroll: real two-line titles, active badges and
            // large Dynamic Type can exceed the conservative metadata budget
            // used for artwork sizing. basedOnSize keeps bounce off when the
            // content already fits, and avoids swapping view trees on resize.
            ScrollView {
                content(availableHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    private func content(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.artworkTopSpacing)

            artwork

            Spacer(minLength: layout.artworkBottomSpacing)

            metadata
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
                ArtworkImage(
                    url: song.album?.artworkURL,
                    cornerRadius: 12
                )
                .frame(
                    width: displayedArtworkSize,
                    height: displayedArtworkSize
                )
                .scaleEffect(artworkBounceScale)
                .nowPlayingArtworkTransition(
                    id: song.id,
                    in: artworkNamespace,
                    isEnabled: usesArtworkTransition,
                    isSource: true
                )
                .shadow(
                    color: .black.opacity(
                        player.isPlaying ? 0.34 : 0.18
                    ),
                    radius: player.isPlaying ? 26 : 14,
                    y: player.isPlaying ? 15 : 8
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
        .animation(
            accessibilityReduceMotion
                ? nil
                : .smooth(duration: 0.48),
            value: isArtworkExpanded
        )
        .animation(
            accessibilityReduceMotion
                ? nil
                : .easeInOut(duration: 0.3),
            value: player.isPlaying
        )
        .accessibilityElement()
        .accessibilityLabel(
            L10n.format(
                "ui.song.artwork_accessibility",
                song.name
            )
        )
        .accessibilityHidden(!showsArtwork)
        .task(id: player.isPlaying) {
            await animateArtworkBounce(
                whenPlaying: player.isPlaying
            )
        }
    }

    private var displayedArtworkSize: CGFloat {
        layout.artworkSide
            * (isArtworkExpanded ? 1 : Self.pausedArtworkScale)
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

    private func animateArtworkBounce(
        whenPlaying isPlaying: Bool
    ) async {
        artworkBounceScale = 1
        guard showsArtwork,
              isPlaying,
              !accessibilityReduceMotion else {
            return
        }

        await Task.yield()
        withAnimation(.easeOut(duration: 0.17)) {
            artworkBounceScale = 1.055
        }

        do {
            try await Task.sleep(for: .milliseconds(170))
        } catch {
            return
        }

        withAnimation(.spring(duration: 0.42, bounce: 0.24)) {
            artworkBounceScale = 1
        }
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
