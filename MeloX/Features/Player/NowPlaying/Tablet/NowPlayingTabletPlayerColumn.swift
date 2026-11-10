import SwiftUI

struct NowPlayingTabletPlayerColumn: View {
    let song: Song
    let layout: NowPlayingTabletLayout
    var onArtworkSizeChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        NowPlayingTabletColumnLayout(layout: layout) {
            NowPlayingPortraitArtwork(song: song, isArtworkPage: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { size in
                    onArtworkSizeChange(size)
                }

            controls
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            NowPlayingTabletMetadata(song: song)
                .padding(.top, layout.metadataTopInset)

            Spacer(minLength: 0)

            NowPlayingProgressControl(song: song)
                .padding(.top, layout.progressTopInset)

            Spacer(minLength: 0)

            NowPlayingTransportControls(presentation: .tablet, rowHeight: layout.transportHeight, availableWidth: layout.playerWidth)
                .padding(.top, layout.transportTopInset)

            Spacer(minLength: 0)

            NowPlayingVolumeControl()
                .padding(.top, NowPlayingTabletLayout.volumeTopInset)

            Spacer(minLength: 0)
        }
        .padding(.bottom, NowPlayingTabletLayout.playerBottomInset)
    }
}

/// Measure the native controls before sizing the square. No geometry state or
/// playback-dependent frames: artwork yields height while controls keep width in
/// the same layout pass, including when fonts or badge visibility change.
private struct NowPlayingTabletColumnLayout: Layout {
    let layout: NowPlayingTabletLayout

    private func fittedLayout(subviews: Subviews) -> NowPlayingTabletLayout {
        let height = subviews[1].sizeThatFits(
            ProposedViewSize(width: layout.playerWidth, height: nil)
        ).height
        return layout.fitting(controlsHeight: height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fitted = fittedLayout(subviews: subviews)
        return CGSize(width: layout.playerWidth, height: fitted.renderedStackHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fitted = fittedLayout(subviews: subviews)
        let x = bounds.midX - fitted.playerWidth * 0.5
        let artworkX = bounds.midX - fitted.artworkSize * 0.5
        let y = bounds.minY + fitted.artworkTopInset
        subviews[0].place(
            at: CGPoint(x: artworkX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: fitted.artworkSize, height: fitted.artworkSize)
        )
        subviews[1].place(
            at: CGPoint(x: x, y: y + fitted.artworkSize),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: fitted.playerWidth, height: fitted.resolvedControlsHeight + fitted.extraVerticalSpace)
        )
    }
}

private struct NowPlayingTabletMetadata: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            artist.frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
                            NowPlayingMetadataBadges(minimumTouchHeight: 44)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            artist
                            NowPlayingMetadataBadges(minimumTouchHeight: 44, stacksVertically: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NowPlayingSongActions(song: song)
                    .fixedSize()
            }
        }
    }

    private var artist: some View {
        Text(song.artistText)
            .font(.title3)
            .foregroundStyle(.white.opacity(0.64))
            .lineLimit(1)
    }
}
