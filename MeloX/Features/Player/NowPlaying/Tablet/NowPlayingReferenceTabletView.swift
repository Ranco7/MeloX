import SwiftUI

/// The iPadOS 26 screen from 9d5d354. Its ideal size includes the complete
/// measured column, so ViewThatFits rejects it before any controls are clipped.
struct NowPlayingReferenceTabletView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(AppSettings.self) private var settings
    @Binding var page: NowPlayingPage
    let pageTransition: NowPlayingTransitionCoordinator
    let song: Song
    let lyrics: [LyricLine]
    let lyricError: String?
    let highlightedLyricID: LyricLine.ID?
    let artworkNamespace: Namespace.ID
    let layout: NowPlayingReferenceTabletLayout
    let onDismiss: () -> Void
    let onExpandLyrics: () -> Void
    let onLyricsContentPrepared: () -> Void

    var body: some View {
        NowPlayingReferenceScreenLayout(layout: layout, centersColumn: page == .artwork) {
            NowPlayingReferenceTabletColumn(song: song, layout: layout)
            NowPlayingTabletPanels(
                pageTransition: pageTransition, song: song, lyrics: lyrics,
                lyricError: lyricError, highlightedLyricID: highlightedLyricID,
                artworkNamespace: artworkNamespace,
                focusAnchorOffset: layout.lyricsFocusAnchorOffset,
                onLyricsContentPrepared: onLyricsContentPrepared
            )
            chrome
        }
        .animation(
            accessibilityReduceMotion ? nil : NowPlayingPageTransition.motion.artworkResize.animation,
            value: page
        )
        .clipped()
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: .circle)
                .accessibilityLabel("ui.player.collapse")

                Spacer()
            }
            .frame(height: NowPlayingReferenceTabletLayout.chromeHeight)

            Spacer(minLength: 0)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    FloatingLyricsButton()

                    if page == .lyrics {
                        if lyrics.contains(where: { $0.hasTranslation || $0.hasRomanization }) {
                            NowPlayingLyricsLanguageButton(
                                hasTranslations: lyrics.contains(where: \.hasTranslation),
                                hasRomanizations: lyrics.contains(where: \.hasRomanization)
                            )
                        }

                        if !lyrics.isEmpty {
                            Button(action: onExpandLyrics) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 17, weight: .medium))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.clear.interactive(), in: .circle)
                            .accessibilityLabel(
                                settings.lyricsStyle == .textPV
                                    ? L10n.string("ui.settings.lyrics.style.text_pv")
                                    : L10n.string("ui.settings.skyline.title")
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    NowPlayingTabletPageSwitcher(page: $page)
                }
            }
            .frame(height: NowPlayingReferenceTabletLayout.bottomBarHeight)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(.white)
    }
}

private struct NowPlayingReferenceScreenLayout: Layout {
    let layout: NowPlayingReferenceTabletLayout
    let centersColumn: Bool

    private func columnSize(_ subviews: Subviews) -> CGSize {
        subviews[0].sizeThatFits(ProposedViewSize(width: layout.playerWidth, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout.requiredSize(measuredColumnSize: columnSize(subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnSize(subviews)
        subviews[0].place(
            at: CGPoint(x: bounds.minX + (centersColumn ? layout.centeredPlayerLeading : layout.playerLeading),
                        y: bounds.minY + NowPlayingReferenceTabletLayout.chromeHeight),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: layout.playerWidth, height: column.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + layout.panelLeading, y: bounds.minY + NowPlayingReferenceTabletLayout.chromeHeight),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: layout.panelWidth, height: layout.contentHeight)
        )
        subviews[2].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: layout.viewport.width, height: layout.viewport.height))
    }
}
