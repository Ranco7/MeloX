import SwiftUI

/// The search overlay owns scroll state so scrolling doesn't re-filter tracks
/// or write a new offset into the album/playlist data owner on every frame.
struct MusicCollectionScrollView<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Binding var query: String
    let prompt: String
    let usesInlineSearch: Bool
    let searchInset: CGFloat
    let heroTopInset: CGFloat
    @ViewBuilder let content: () -> Content

    @ScaledMetric(relativeTo: .body) private var searchFontSize: CGFloat = 17
    @State private var scroll: Double = 0
    @FocusState private var searchFocused: Bool

    private var keepsSearchExpanded: Bool {
        searchFocused || !query.isEmpty || dynamicTypeSize.isAccessibilitySize || voiceOverEnabled
    }

    private var expandedHeight: CGFloat {
        CGFloat(MusicCollectionSearchLayout.expandedHeight(fontSize: Double(searchFontSize)))
    }

    var body: some View {
        ScrollView {
            content()
                // A fixed inset is intentional: reducing it as well as moving
                // the scroll content would count the collapse distance twice.
                .padding(.top, usesInlineSearch ? MusicCollectionSearchLayout.topInset + expandedHeight + MusicCollectionSearchLayout.artworkGap - heroTopInset : 0)
        }
        .onScrollGeometryChange(for: Double.self) { geometry in
            usesInlineSearch ? min(max(Double(geometry.contentOffset.y + geometry.contentInsets.top), 0), Double(expandedHeight)) : 0
        } action: { _, value in
            scroll = value
        }
        .overlay(alignment: .top) {
            if usesInlineSearch {
                searchField
                    .padding(.horizontal, searchInset)
                    .padding(.top, MusicCollectionSearchLayout.topInset)
                    .accessibilitySortPriority(1)
            }
        }
    }

    private var searchField: some View {
        let offset = keepsSearchExpanded ? 0 : scroll
        let height = keepsSearchExpanded ? Double(expandedHeight) : MusicCollectionSearchLayout.height(scroll: offset, expandedHeight: Double(expandedHeight))
        let opacity = MusicCollectionSearchLayout.glyphOpacity(scroll: offset)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .accessibilityHidden(true)
            TextField(prompt, text: $query)
                .font(.body)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel(prompt)
                .accessibilitySortPriority(1)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ui.common.clear")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 0)
        .opacity(opacity)
        .frame(height: CGFloat(height))
        .background(.ultraThinMaterial, in: .capsule)
        .clipShape(.capsule)
        .contentShape(.capsule)
        .allowsHitTesting(height > 0 && opacity > 0)
        .accessibilityHidden(height == 0 || opacity == 0)
        .transaction { $0.animation = nil }
    }
}

extension View {
    @ViewBuilder
    func musicCollectionNativeSearch(text: Binding<String>, prompt: Text, enabled: Bool) -> some View {
        if enabled {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
        } else {
            self
        }
    }
}
