import SwiftUI

struct NowPlayingBottomControls: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let song: Song
    @Binding var page: NowPlayingPage
    let layout: NowPlayingPortraitLayout
    let showsLyricsUtilities: Bool
    let hasLyricsTranslations: Bool
    let hasLyricsRomanizations: Bool
    let isInterfaceHidden: Bool
    let onProgressHeightChange: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsLyricsUtilities {
                NowPlayingLyricsUtilityControls(
                    isVisible: !isInterfaceHidden,
                    hasTranslations: hasLyricsTranslations,
                    hasRomanizations: hasLyricsRomanizations
                )
                .frame(
                    height: layout.utilityHeight,
                    alignment: .top
                )
            }

            coreControls
        }
        .padding(.horizontal, layout.horizontalMargin)
    }

    private var coreControls: some View {
        VStack(spacing: 0) {
            interfaceLayer(.progress) {
                NowPlayingProgressControl(song: song)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        onProgressHeightChange(height)
                    }
                    .frame(minHeight: layout.progressHeight)
            }

            Color.clear
                .frame(height: layout.progressTransportGap)

            interfaceLayer(.transport) {
                NowPlayingTransportControls(rowHeight: layout.transportHeight)
                    .frame(height: layout.transportHeight)
            }

            Color.clear
                .frame(height: layout.transportVolumeGap)

            interfaceLayer(.volume) {
                NowPlayingVolumeControl()
                    .frame(height: layout.volumeHeight)
            }

            Color.clear
                .frame(height: layout.volumeSelectorGap)

            interfaceLayer(.pageSelector) {
                NowPlayingPageSelector(page: $page)
                    .frame(height: layout.pageSelectorHeight)
            }
        }
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {}
        }
    }

    private func interfaceLayer<Content: View>(
        _ layer: NowPlayingInterfaceTransition.ControlLayer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .offset(
                y: isInterfaceHidden
                    ? NowPlayingInterfaceTransition.hiddenOffset(
                        for: layer
                    )
                    : 0
            )
            .opacity(isInterfaceHidden ? 0 : 1)
            .animation(
                NowPlayingInterfaceTransition.controlAnimation(
                    for: layer,
                    isVisible: !isInterfaceHidden,
                    reducesMotion: accessibilityReduceMotion
                ),
                value: isInterfaceHidden
            )
    }
}

private struct NowPlayingLyricsUtilityControls: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let isVisible: Bool
    let hasTranslations: Bool
    let hasRomanizations: Bool

    var body: some View {
        HStack {
            if hasTranslations || hasRomanizations {
                NowPlayingLyricsLanguageButton(
                    hasTranslations: hasTranslations,
                    hasRomanizations: hasRomanizations
                )
                    .scaleEffect(
                        isVisible
                            ? 1
                            : NowPlayingInterfaceTransition
                                .utilityHiddenScale
                    )
            }

            Spacer()
        }
        .offset(
            y: isVisible
                ? 0
                : NowPlayingInterfaceTransition
                    .utilityHiddenOffset
        )
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(
            NowPlayingInterfaceTransition.utilityAnimation(
                isVisible: isVisible,
                reducesMotion: accessibilityReduceMotion
            ),
            value: isVisible
        )
    }
}
