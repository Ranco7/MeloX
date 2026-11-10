import SwiftUI

@available(iOS 27.1, *)
struct NowPlayingAdaptiveView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(AppSettings.self) private var settings
    @State private var fittedArtworkSize: CGFloat?

    @Binding var page: NowPlayingPage
    let pageTransition: NowPlayingTransitionCoordinator
    let song: Song
    let lyrics: [LyricLine]
    let lyricError: String?
    let highlightedLyricID: LyricLine.ID?
    let artworkNamespace: Namespace.ID
    let onDismiss: () -> Void
    let onExpandLyrics: () -> Void
    let onLyricsContentPrepared: () -> Void

    var body: some View {
        NavigationStack {
            ArrangementView {
                playerColumn
                    .splitArrangementLayoutRatio(page == .artwork ? 1 : 0.5)
            } secondary: {
                detailPanel
            }
            .arrangementViewStyle(.split)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
            .toolbar {
                playerToolbar
            }
        }
        .tint(.white)
    }

    private var playerColumn: some View {
        GeometryReader { proxy in
            let layout = NowPlayingTabletLayout(viewport: proxy.size, fillsRegion: true)

            ScrollView([.horizontal, .vertical]) {
                NowPlayingTabletPlayerColumn(song: song, layout: layout) { size in
                    if size.isFinite && size > 0 { fittedArtworkSize = size }
                }
                    .frame(width: layout.playerWidth)
                    .frame(minWidth: proxy.size.width)
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
            .scrollIndicators(.hidden)
            .scrollClipDisabled(layout.playerWidth <= layout.playerContainerWidth)
        }
    }

    private var detailPanel: some View {
        GeometryReader { proxy in
            let layout = NowPlayingTabletLayout(viewport: proxy.size, fillsRegion: true)

            NowPlayingTabletPanels(
                pageTransition: pageTransition,
                song: song,
                lyrics: lyrics,
                lyricError: lyricError,
                highlightedLyricID: highlightedLyricID,
                artworkNamespace: artworkNamespace,
                focusAnchorOffset: layout.artworkTopInset
                    + (fittedArtworkSize ?? layout.artworkSize) * 0.5
                    - NowPlayingTabletLayout.lyricsTopPadding,
                onLyricsContentPrepared: onLyricsContentPrepared
            )
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(page != .artwork)
        .accessibilityHidden(page == .artwork)
    }

    @ToolbarContentBuilder
    private var playerToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("ui.player.collapse", systemImage: "chevron.down", action: onDismiss)
        }
        .visibilityPriority(.high)

        ToolbarItem(placement: .bottomBar) {
            NowPlayingAirPlayControl()
                .frame(width: 44, height: 44)
        }
        .axisBehavior(.verticalPreferred)

        if page == .lyrics {
            if lyrics.contains(where: { $0.hasTranslation || $0.hasRomanization }) {
                ToolbarItem(placement: .bottomBar) {
                    NowPlayingLyricsLanguageButton(
                        hasTranslations: lyrics.contains(where: \.hasTranslation),
                        hasRomanizations: lyrics.contains(where: \.hasRomanization)
                    )
                }
                .axisBehavior(.verticalPreferred)
            }

            if !lyrics.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: onExpandLyrics) {
                        Label(
                            settings.lyricsStyle == .textPV
                                ? L10n.string("ui.settings.lyrics.style.text_pv")
                                : L10n.string("ui.settings.skyline.title"),
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                    }
                }
            }
        }

        if !song.isPodcastProgram {
            ToolbarItem(placement: .bottomBar) {
                pageButton(.lyrics, title: "ui.settings.lyrics.title", systemImage: "quote.bubble")
            }
            .visibilityPriority(.high)
        }

        ToolbarItem(placement: .bottomBar) {
            pageButton(.queue, title: "ui.player.queue", systemImage: "list.bullet")
        }
        .visibilityPriority(.high)
    }

    private func pageButton(
        _ destination: NowPlayingPage,
        title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Button {
            let target = page == destination ? .artwork : destination
            withAnimation(
                accessibilityReduceMotion
                    ? nil
                    : NowPlayingPageTransition.selectionAnimation(from: page, to: target)
            ) {
                page = target
            }
        } label: {
            Label(title, systemImage: systemImage)
                .symbolVariant(page == destination ? .fill : .none)
        }
        .accessibilityValue(
            page == destination
                ? L10n.string("ui.common.selected")
                : L10n.string("ui.common.not_selected")
        )
        .accessibilityAddTraits(page == destination ? .isSelected : [])
    }
}
