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

            NowPlayingTransportControls(presentation: .tablet)
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
/// playback-dependent frames: artwork and controls receive the same width in
/// the same layout pass, including when fonts or badge visibility change.
private struct NowPlayingTabletColumnLayout: Layout {
    let layout: NowPlayingTabletLayout

    private func fittedLayout(subviews: Subviews) -> NowPlayingTabletLayout {
        // Tablet text is line-limited, so narrowing the column does not add
        // lines. Use the larger measurement to keep the entire band reserved.
        let fullWidthHeight = subviews[1].sizeThatFits(
            ProposedViewSize(width: layout.playerContainerWidth, height: nil)
        ).height
        let fitted = layout.fitting(controlsHeight: fullWidthHeight)
        let fittedWidthHeight = subviews[1].sizeThatFits(
            ProposedViewSize(width: fitted.playerWidth, height: nil)
        ).height
        return layout.fitting(controlsHeight: max(fullWidthHeight, fittedWidthHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fitted = fittedLayout(subviews: subviews)
        return CGSize(width: layout.playerContainerWidth, height: fitted.renderedStackHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fitted = fittedLayout(subviews: subviews)
        let x = bounds.midX - fitted.playerWidth * 0.5
        let y = bounds.minY + fitted.artworkTopInset
        subviews[0].place(
            at: CGPoint(x: x, y: y),
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
                    HeartModeNowPlayingBadge()
                    ListenTogetherNowPlayingBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            NowPlayingSongActions(song: song)
                .fixedSize()
        }
    }
}
