import Nuke
import Observation
import SwiftUI
import UIKit

private enum ContentSheet: String, Identifiable {
    case settings

    var id: String { rawValue }
}

private enum ContentRoute: Hashable {
    case privateMessages
    case songRecognition
}

private enum ContentTab: Hashable {
    case page(AppTab)
    case playlist(Int)
}

@Observable
private final class ContentColumnGeometryStore {
    private(set) var storedBounds: [ContentTab: ContentColumnHorizontalBounds] = [:]

    func update(_ tab: ContentTab, bounds: ContentColumnHorizontalBounds?) {
        if let bounds {
            guard storedBounds[tab] != bounds else { return }
            storedBounds[tab] = bounds
        } else if storedBounds[tab] != nil {
            storedBounds[tab] = nil
        }
    }

    func bounds(for tab: ContentTab) -> ContentColumnHorizontalBounds? {
        storedBounds[tab]
    }

    func retainTabs(_ tabs: Set<ContentTab>) {
        let retained = storedBounds.filter { tabs.contains($0.key) }
        guard retained.count != storedBounds.count else { return }
        storedBounds = retained
    }

    func reset() {
        guard !storedBounds.isEmpty else { return }
        storedBounds.removeAll()
    }
}

private struct SidebarArtworkRequest: Hashable {
    let id: Int
    let url: URL
}

// Only read on the main actor after the task group completes.
private struct SidebarArtworkResult: @unchecked Sendable {
    let request: SidebarArtworkRequest
    let image: UIImage?
}

private struct HeartModeLaunchReadiness: Equatable {
    let hasRestoredPlayback: Bool
    let isLoggedIn: Bool
    let canStartHeartMode: Bool
}

struct ContentView: View {
    private static let sidebarArtworkSize = CGSize(width: 24, height: 24)
    private static let floatingMiniPlayerClearance = MusicCollectionLayout.miniPlayerClearance
    fileprivate static let floatingMiniPlayerOuterPadding = MusicCollectionLayout.miniPlayerInset
    fileprivate static let floatingMiniPlayerWideContentPadding: CGFloat = 16
    fileprivate static let contentColumnCoordinateSpace = "content-column-bounds"

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @Environment(LyricsStore.self) private var lyrics
    @Environment(FloatingLyricsController.self) private var floatingLyrics
    @Environment(\.displayScale) private var displayScale

    @State private var selectedTab: ContentTab
    @State private var navigationPaths: [ContentTab: NavigationPath] = [:]
    @State private var tabletCollectionChrome: [ContentTab: TabletCollectionChrome] = [:]
    @State private var contentColumnGeometry = ContentColumnGeometryStore()
    @State private var sidebarArtwork: [SidebarArtworkRequest: UIImage] = [:]
    @State private var presentedSheet: ContentSheet?
    @State private var playerPresentation: PlayerPresentation?
    @State private var isPlayerPresentationActive = false
    @State private var playerUsesReducedMotion = false
    @State private var isPlayerDismissalRequested = false
    @State private var requestedPlayerPage: NowPlayingPage?
    @State private var neteaseSharePresentation: NeteaseSharePresentation?
    @State private var nowPlayingSharePresentation: NeteaseSharePresentation?
    @State private var pendingMusicRoute: MusicRoute?
    @State private var isTabViewBottomAccessorySuppressed = false
    @State private var hasRestoredPlayback = false
    @State private var hasHandledHeartModeLaunch = false
    @State private var heartModeLaunchErrorMessage: String?
    @Namespace private var musicNavigationNamespace

    init(initialTab: AppTab = .home) {
        _selectedTab = State(initialValue: .page(initialTab))
    }

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                mainExperience
            } else {
                OnboardingView()
            }
        }
    }

    private var mainExperience: some View {
        playerAwareTabView
            .environment(
                \.openMusicRoute,
                OpenMusicRouteAction(action: openMusicRoute)
            )
            .environment(
                \.openNeteaseShare,
                OpenNeteaseShareAction(action: openNeteaseShare)
            )
            .environment(
                \.setTabViewBottomAccessorySuppressed,
                SetTabViewBottomAccessorySuppressedAction {
                    isTabViewBottomAccessorySuppressed = $0
                }
            )
            .fullScreenCover(
                item: $playerPresentation,
                onDismiss: finishPendingSongNavigation
            ) { destination in
                switch destination {
                case .nowPlaying:
                    NowPlayingPresentationView(
                        initialPage: requestedPlayerPage ?? initialNowPlayingPage,
                        reducesMotion: playerUsesReducedMotion,
                        dismissalRequested: isPlayerDismissalRequested,
                        onDismiss: dismissPlayer
                    )
                        .ignoresSafeArea()
                        .preferredColorScheme(.dark)
                        .environment(
                            \.openMusicRoute,
                            OpenMusicRouteAction(action: openMusicRoute)
                        )
                        .environment(
                            \.openNeteaseShare,
                            OpenNeteaseShareAction { presentation in
                                presentNeteaseShare(
                                    presentation,
                                    fromNowPlaying: true
                                )
                            }
                        )
                        .sheet(item: $nowPlayingSharePresentation) {
                            presentation in
                            NeteaseShareSheet(presentation: presentation)
                        }
                        .presentationBackground(.clear)
                }
            }
            .sheet(item: $neteaseSharePresentation) { presentation in
                NeteaseShareSheet(presentation: presentation)
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .settings:
                    NavigationStack {
                        SettingsView()
                            .musicDestinations(
                                in: musicNavigationNamespace
                            )
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(32)
                }
            }
            .task {
                await player.restore()
                guard !Task.isCancelled else { return }
                hasRestoredPlayback = true
            }
            .task(
                id: HeartModeLaunchReadiness(
                    hasRestoredPlayback: hasRestoredPlayback,
                    isLoggedIn: library.isLoggedIn,
                    canStartHeartMode: library.canStartHeartMode
                )
            ) {
                await startHeartModeOnLaunchIfNeeded()
            }
            .task(id: player.currentSong?.album?.artworkURL) {
                guard let url = player.currentSong?.album?.artworkURL else { return }
                _ = await ArtworkBackdropImageProvider.shared.image(for: url, pixelDimension: 1024)
            }
            .task(id: player.currentSong?.id) {
                await synchronizeLyrics()
            }
            .onChange(of: settings.lyricsSourcePreference) { _, _ in
                Task { await synchronizeLyrics() }
            }
            .task {
                await floatingLyrics.monitor()
            }
            .onChange(of: settings.cookie) { _, _ in
                navigationPaths = [:]
                tabletCollectionChrome = [:]
                contentColumnGeometry.reset()
                sidebarArtwork = [:]
                if case .playlist = selectedTab {
                    selectedTab = .page(settings.fallbackNavigationTab)
                }
            }
            .task(id: settings.cookie) {
                await library.refresh()
            }
            .background(alignment: .topLeading) {
                FloatingLyricsPictureInPictureSource(
                    controller: floatingLyrics
                )
                .frame(
                    width:
                        FloatingLyricsPictureInPictureSource
                            .sourceSize.width,
                    height:
                        FloatingLyricsPictureInPictureSource
                            .sourceSize.height
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: selectedTab) { _, tab in rememberTab(tab) }
            .onChange(of: availableTabs) { _, tabs in updateTabSelection(available: tabs) }
            .onChange(of: scenePhase) { _, phase in
                player.refreshLyricsNotification()
                guard phase == .active else { return }
                player.refreshLyricsLiveActivity()
            }
            .onChange(of: floatingLyrics.restorationRequestID) {
                guard floatingLyrics.restorationRequestID > 0,
                      player.currentSong != nil else {
                    floatingLyrics.completeRestoration(success: false)
                    return
                }

                openPlayer()
                Task { @MainActor in
                    await Task.yield()
                    floatingLyrics.completeRestoration(success: true)
                }
            }
            .alert(
                "ui.error.playback.title",
                isPresented: Binding(
                    get: { player.playbackIssue != nil },
                    set: { isPresented in
                        if !isPresented {
                            player.dismissPlaybackIssue()
                        }
                    }
                )
            ) {
                if player.canPlayNext {
                    Button("ui.player.play_next") {
                        player.dismissPlaybackIssue()
                        Task { await player.next() }
                    }
                }
                Button("ui.common.ok", role: .cancel) {
                    player.dismissPlaybackIssue()
                }
            } message: {
                Text(player.playbackIssue?.message ?? L10n.string("ui.error.playback.current_unavailable"))
            }
            .alert(
                "ui.error.heart_mode_launch.title",
                isPresented: Binding(
                    get: { heartModeLaunchErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            heartModeLaunchErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("ui.common.ok", role: .cancel) {
                    heartModeLaunchErrorMessage = nil
                }
            } message: {
                Text(heartModeLaunchErrorMessage ?? L10n.string("ui.error.try_again_later"))
            }
            .alert(
                "ui.error.download.title",
                isPresented: Binding(
                    get: {
                        AppFeatureAvailability.downloads
                            && downloads.errorMessage != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            downloads.clearError()
                        }
                    }
                )
            ) {
                Button("ui.common.ok", role: .cancel) {
                    downloads.clearError()
                }
            } message: {
                Text(downloads.errorMessage ?? L10n.string("ui.error.download.operation_failed"))
            }
            .alert(
                "ui.error.floating_lyrics.title",
                isPresented: Binding(
                    get: { floatingLyrics.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            floatingLyrics.dismissError()
                        }
                    }
                )
            ) {
                Button("ui.common.ok", role: .cancel) {
                    floatingLyrics.dismissError()
                }
            } message: {
                Text(
                    floatingLyrics.errorMessage
                        ?? L10n.string("ui.error.picture_in_picture.unavailable")
                )
            }
            .coordinateListenTogether()
            .recognizesClipboardLinksOnLaunch { song in
                openMusicRoute(.song(song))
            }
            .appLaunchExperience()
    }

    private func synchronizeLyrics() async {
        let song = player.currentSong
        let lyricSong = song?.isPodcastProgram == true ? nil : song
        await lyrics.load(for: lyricSong)
        guard !Task.isCancelled else { return }
        player.setNowPlayingLyrics(lyrics.lyrics, for: lyricSong?.id)
    }

    private func startHeartModeOnLaunchIfNeeded() async {
        guard !hasHandledHeartModeLaunch,
              hasRestoredPlayback else {
            return
        }
        guard settings.startsHeartModeOnLaunch else {
            hasHandledHeartModeLaunch = true
            return
        }
        guard library.isLoggedIn else {
            hasHandledHeartModeLaunch = true
            return
        }
        guard library.canStartHeartMode,
              let playlistID = library.likedPlaylistID,
              let seedSongID = library.randomHeartModeSeedSongID() else {
            return
        }

        hasHandledHeartModeLaunch = true
        do {
            try await player.playHeartMode(
                playlistID: playlistID,
                seedSongID: seedSongID
            )
        } catch is CancellationError {
            return
        } catch {
            heartModeLaunchErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var playerAwareTabView: some View {
        Group {
            if #available(iOS 26.1, *) {
                tabs.tabViewBottomAccessory(isEnabled: showsMiniPlayer && !usesFloatingMiniPlayer) {
                    if showsMiniPlayer && !usesFloatingMiniPlayer {
                        miniPlayer
                    }
                }
            } else {
                tabs.tabViewBottomAccessory {
                    if showsMiniPlayer && !usesFloatingMiniPlayer {
                        miniPlayer
                    }
                }
            }
        }
        // Root-level overlay: a tab's NavigationStack frame is shortened by
        // the keyboard and Stage Manager transitions, which is what could
        // leave the bar in the middle of the window. Ignoring the keyboard
        // safe area here keeps the bar at the window's bottom edge.
        .overlay(alignment: .bottom) {
            if usesFloatingMiniPlayer && showsMiniPlayer {
                FloatingMiniPlayerBar(
                    geometry: contentColumnGeometry,
                    tab: selectedTab,
                    collectionPalette:
                        tabletCollectionChrome[selectedTab]?.palette,
                    onOpen: openPlayer
                )
            }
        }
        .coordinateSpace(.named(Self.contentColumnCoordinateSpace))
    }

    private var showsMiniPlayer: Bool {
        player.currentSong != nil && !isTabViewBottomAccessorySuppressed
    }

    private var usesFloatingMiniPlayer: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    private var miniPlayer: some View {
        MiniPlayerView {
            openPlayer()
        }
    }

    private func prepareArtworkForPresentation() {
        guard let artworkURL = player.currentSong?.album?.artworkURL else {
            return
        }
        // The mini player already uses this exact URL. Warm one bounded Nuke
        // decode so the full-player artwork and backdrop share its encoded
        // data instead of starting a duplicate full-size request.
        if settings.playerBackgroundStyle == .flowingLight {
            Task {
                _ = await ArtworkAccentColorProvider.shared.detailAssets(
                    for: artworkURL
                )
            }
        }
    }

    private func openPlayer(_ page: NowPlayingPage? = nil) {
        // Keep the presentation locked until onDismiss, including an interactive exit.
        guard player.currentSong != nil, !isPlayerPresentationActive else { return }
        prepareArtworkForPresentation()
        requestedPlayerPage = page
        playerUsesReducedMotion = accessibilityReduceMotion
        isPlayerDismissalRequested = false
        isPlayerPresentationActive = true
        setPlayerPresentation(.nowPlaying)
    }

    private func dismissPlayer() {
        setPlayerPresentation(nil)
    }

    private func setPlayerPresentation(_ presentation: PlayerPresentation?) {
        // The cover is only a presentation host; its card owns all motion.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            playerPresentation = presentation
        }
    }

    private var tabs: some View {
        let libraryTabs = displayedSidebarLibraryTabs.filter { $0 != .libraryPlaylists }
        let showsPlaylistDirectory = displayedSidebarLibraryTabs.contains(.libraryPlaylists)
        let playlists = displayedSidebarPlaylists

        return TabView(selection: $selectedTab) {
            ForEach(settings.visibleTabs) { tab in
                navigationTab(for: tab)

                if tab == .library, !libraryTabs.isEmpty {
                    TabSection(L10n.string("ui.library.category_picker")) {
                        ForEach(libraryTabs) { shortcut in
                            navigationTab(for: shortcut).defaultVisibility(shortcutVisibility, for: .tabBar)
                        }
                    }
                }
            }

            if showsPlaylistDirectory || !playlists.isEmpty {
                TabSection(L10n.string("ui.common.playlists")) {
                    if showsPlaylistDirectory {
                        navigationTab(for: .libraryPlaylists, title: L10n.string("ui.library.all_playlists"))
                            .defaultVisibility(shortcutVisibility, for: .tabBar)
                    }
                    ForEach(playlists) { playlist in
                        playlistTab(for: playlist).defaultVisibility(shortcutVisibility, for: .tabBar)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(.sidebar)
        .tabViewSidebarBottomBar {
            Button {
                presentedSheet = .settings
            } label: {
                HStack(spacing: 10) {
                    accountToolbarIcon(avatarSize: 32)
                    Text(library.profile?.nickname ?? L10n.string("ui.account.login_settings"))
                        .font(.subheadline.weight(.regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accountToolbarAccessibilityLabel)
            .padding(.bottom, 6)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .background {
            if horizontalSizeClass == .regular,
               let palette = tabletCollectionChrome[selectedTab]?.palette {
                palette.backgroundColor.ignoresSafeArea()
            }
        }
        .environment(\.musicNavigationNamespace, musicNavigationNamespace)
        .task(id: sidebarArtworkRequests) {
            await loadSidebarArtwork(sidebarArtworkRequests)
        }
    }

    private var sidebarLibraryTabs: [AppTab] {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              settings.visibleTabs.contains(.library) else { return [] }
        return settings.embeddedLibraryPages.map(AppTab.init(libraryPage:))
    }

    private var displayedSidebarLibraryTabs: [AppTab] {
        // Keep the active shortcut and its navigation stack when a window narrows.
        if horizontalSizeClass == .compact {
            return sidebarLibraryTabs.filter { .page($0) == selectedTab }
        }
        return sidebarLibraryTabs
    }

    private var sidebarPlaylists: [Playlist] {
        guard UIDevice.current.userInterfaceIdiom == .pad, library.isLoggedIn else { return [] }
        var playlists: [Playlist] = []
        if let likedPlaylistID = library.likedPlaylistID {
            playlists.append(Playlist(
                id: likedPlaylistID,
                name: L10n.string("ui.library.liked_playlist"),
                trackCount: library.favoriteSongTotalCount
            ))
        }
        // Keep the full collection in the directory instead of creating up to 2,000 tabs.
        var seen = Set(playlists.map(\.id))
        var remaining = 40
        for playlist in library.favoritePlaylists where seen.insert(playlist.id).inserted {
            playlists.append(playlist)
            remaining -= 1
            if remaining == 0 { break }
        }
        return playlists
    }

    private var displayedSidebarPlaylists: [Playlist] {
        if horizontalSizeClass == .compact {
            return sidebarPlaylists.filter { .playlist($0.id) == selectedTab }
        }
        return sidebarPlaylists
    }

    private var sidebarArtworkRequests: [SidebarArtworkRequest] {
        guard horizontalSizeClass != .compact else { return [] }
        return sidebarPlaylists.compactMap { playlist in
            playlist.artworkURL.map { SidebarArtworkRequest(id: playlist.id, url: $0) }
        }
    }

    private func loadSidebarArtwork(_ requests: [SidebarArtworkRequest]) async {
        let activeRequests = Set(requests)
        sidebarArtwork = sidebarArtwork.filter { activeRequests.contains($0.key) }
        let missingRequests = requests.filter { sidebarArtwork[$0] == nil }
        guard !missingRequests.isEmpty else { return }

        let size = Self.sidebarArtworkSize
        let loadedImages = await withTaskGroup(
            of: SidebarArtworkResult.self,
            returning: [SidebarArtworkRequest: UIImage].self
        ) { group in
            for request in missingRequests {
                group.addTask {
                    var imageRequest = ImageRequest(url: request.url)
                    imageRequest.thumbnail = ImageRequest.ThumbnailOptions(
                        size: size,
                        contentMode: .aspectFill
                    )
                    let image = try? await ImagePipeline.shared.image(for: imageRequest)
                    return SidebarArtworkResult(request: request, image: image)
                }
            }

            var images: [SidebarArtworkRequest: UIImage] = [:]
            for await result in group {
                guard let image = result.image,
                      image.size.width > 0,
                      image.size.height > 0 else { continue }
                images[result.request] = image
            }
            return images
        }
        guard !Task.isCancelled, !loadedImages.isEmpty else { return }

        let renderer = UIGraphicsImageRenderer(size: size)
        let bounds = CGRect(origin: .zero, size: size)
        var rendered: [SidebarArtworkRequest: UIImage] = [:]
        for (request, image) in loadedImages {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let width = image.size.width * scale
            let height = image.size.height * scale
            rendered[request] = renderer.image { _ in
                UIBezierPath(roundedRect: bounds, cornerRadius: 4).addClip()
                image.draw(in: CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                                      width: width, height: height))
            }
        }
        guard !rendered.isEmpty else { return }
        sidebarArtwork.merge(rendered) { _, new in new }
    }

    private var shortcutVisibility: Visibility {
        horizontalSizeClass == .compact ? .visible : .hidden
    }

    private var availableTabs: [ContentTab] {
        (settings.visibleTabs + sidebarLibraryTabs).map(ContentTab.page)
            + sidebarPlaylists.map { .playlist($0.id) }
    }

    private func rememberTab(_ tab: ContentTab) {
        switch tab {
        case .page(let page):
            settings.lastSelectedTab = sidebarLibraryTabs.contains(page) ? .library : page
        case .playlist:
            settings.lastSelectedTab = settings.visibleTabs.contains(.libraryPlaylists) ? .libraryPlaylists
                : settings.visibleTabs.contains(.library) ? .library : settings.fallbackNavigationTab
        }
    }

    private func updateTabSelection(available tabs: [ContentTab]) {
        let activeTabs = Set(tabs)
        navigationPaths = navigationPaths.filter { tab, _ in
            if case .playlist = tab { return activeTabs.contains(tab) }
            return true
        }
        tabletCollectionChrome = tabletCollectionChrome.filter { activeTabs.contains($0.key) }
        contentColumnGeometry.retainTabs(activeTabs)
        guard !activeTabs.contains(selectedTab) else { return }
        switch selectedTab {
        case .page(let page) where settings.homeTabs.contains(page) && activeTabs.contains(.page(.home)):
            selectedTab = .page(.home)
        case .page(let page) where page.libraryPage != nil && activeTabs.contains(.page(.library)):
            selectedTab = .page(.library)
        case .playlist where activeTabs.contains(.page(.libraryPlaylists)):
            selectedTab = .page(.libraryPlaylists)
        default:
            selectedTab = .page(settings.fallbackNavigationTab)
        }
    }

    private func navigationTab(for tab: AppTab, title: String? = nil) -> some TabContent<ContentTab> {
        Tab(
            title ?? tab.title,
            systemImage: tab.systemImage,
            value: ContentTab.page(tab),
            role: tab == .search ? .search : nil
        ) {
            tabNavigation(.page(tab)) {
                tabRoot(for: tab)
                    .toolbar { primaryToolbar(for: .page(tab)) }
            }
        }
    }

    private func playlistTab(for playlist: Playlist) -> some TabContent<ContentTab> {
        let tab = ContentTab.playlist(playlist.id)
        let artwork = playlist.artworkURL.flatMap { sidebarArtwork[SidebarArtworkRequest(id: playlist.id, url: $0)] }
        return Tab(value: tab) {
            tabNavigation(tab) {
                PlaylistDetailView(playlist: PlaylistRouteContext(playlist))
            }
        } label: {
            Label {
                Text(playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? L10n.string("ui.common.playlist") : playlist.name)
            } icon: {
                if let artwork {
                    Image(uiImage: artwork).renderingMode(.original)
                } else {
                    Image(systemName: playlist.id == library.likedPlaylistID ? "heart.fill" : "music.note.list")
                }
            }
        }
    }

    private func tabNavigation<Root: View>(_ tab: ContentTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: navigationPathBinding(for: tab)) {
            root()
                .navigationDestination(for: ContentRoute.self) { route in
                    contentDestination(for: route)
                }
                .musicDestinations(in: musicNavigationNamespace)
        }
        .id(settings.cookie)
        .onGeometryChange(for: ContentColumnHorizontalBounds?.self) { proxy in
            guard proxy.size.width > 0 else { return nil }
            let frame = proxy.frame(in: .named(Self.contentColumnCoordinateSpace))
            return ContentColumnGeometryMath.horizontalBounds(
                minX: Double(frame.minX),
                maxX: Double(frame.maxX),
                displayScale: Double(displayScale)
            )
        } action: { bounds in
            contentColumnGeometry.update(tab, bounds: bounds)
        }
        .environment(
            \.tabletCollectionChrome,
            Binding(
                get: { tabletCollectionChrome[tab] },
                set: { tabletCollectionChrome[tab] = $0 }
            )
        )
        // The floating bar lives at the root (see `playerAwareTabView`); this
        // transparent inset only reserves scroll clearance in the selected
        // tab, so it never moves the bar or keeps a stale inset height.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTab == tab && usesFloatingMiniPlayer && showsMiniPlayer {
                Color.clear
                    .frame(
                        height: Self.floatingMiniPlayerClearance
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func tabRoot(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .recommended:
            HomeRecommendedView()
                .navigationTitle("ui.navigation.recommended")
                .navigationBarTitleDisplayMode(.large)
        case .music:
            ExploreView(navigationTitle: L10n.string("ui.navigation.music"))
        case .podcasts:
            PodcastHomeView()
        case .explore:
            ExploreView()
        case .library:
            LibraryView()
        case .search:
            SearchView()
        case .librarySongs,
             .libraryPlaylists,
             .libraryAlbums,
             .libraryArtists,
             .libraryPodcasts,
             .libraryDownloads,
             .libraryCloud,
             .libraryHistory:
            if let page = tab.libraryPage {
                LibraryView(fixedPage: page)
            }
        }
    }

    @ToolbarContentBuilder
    private func primaryToolbar(
        for tab: ContentTab
    ) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if library.isLoggedIn {
                Button {
                    navigate(to: .privateMessages, in: tab)
                } label: {
                    Label("ui.messages.private.title", systemImage: "bubble.left.and.bubble.right")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("ui.messages.private.title")
                .accessibilityHint("ui.messages.private.open_hint")
            }

            Button {
                navigate(to: .songRecognition, in: tab)
            } label: {
                Label("ui.recognition.title", systemImage: "waveform")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("ui.recognition.title")

            Button {
                presentedSheet = .settings
            } label: {
                accountToolbarIcon(avatarSize: 28)
            }
            .accessibilityLabel(accountToolbarAccessibilityLabel)
        }
    }

    @ViewBuilder
    private func contentDestination(
        for route: ContentRoute
    ) -> some View {
        switch route {
        case .privateMessages:
            NeteasePrivateMessagesView()
        case .songRecognition:
            SongRecognitionView()
        }
    }

    @ViewBuilder
    private func accountToolbarIcon(avatarSize: CGFloat) -> some View {
        if let profile = library.profile {
            AsyncImage(url: profile.artworkURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .background(.quaternary, in: .circle)
            .clipShape(.circle)
        } else {
            Image(
                systemName: library.isLoggedIn
                    ? "person.crop.circle.fill"
                    : "person.crop.circle"
            )
        }
    }

    private var accountToolbarAccessibilityLabel: String {
        if let profile = library.profile {
            return L10n.format("ui.account.settings_for_user", profile.nickname)
        }
        return library.isLoggedIn
            ? L10n.string("ui.account.settings")
            : L10n.string("ui.account.login_settings")
    }

    private func navigationPathBinding(
        for tab: ContentTab
    ) -> Binding<NavigationPath> {
        Binding(
            get: {
                navigationPaths[tab] ?? NavigationPath()
            },
            set: {
                navigationPaths[tab] = $0
            }
        )
    }

    private var initialNowPlayingPage: NowPlayingPage {
        guard settings.rememberNowPlayingPage else { return .artwork }
        return NowPlayingPage(rawValue: settings.rememberedNowPlayingPage) ?? .artwork
    }

    private func openMusicRoute(_ route: MusicRoute) {
        guard !isPlayerPresentationActive else {
            pendingMusicRoute = route
            isPlayerDismissalRequested = true
            return
        }
        navigate(to: route)
    }

    private func openNeteaseShare(
        _ presentation: NeteaseSharePresentation
    ) {
        presentNeteaseShare(presentation, fromNowPlaying: false)
    }

    private func presentNeteaseShare(
        _ presentation: NeteaseSharePresentation,
        fromNowPlaying: Bool
    ) {
        Task { @MainActor in
            // Menu actions can fire before the system has completed
            // dismissing the menu. Present on the next settled UI turn.
            try? await Task.sleep(for: .milliseconds(140))
            if fromNowPlaying {
                nowPlayingSharePresentation = presentation
            } else {
                neteaseSharePresentation = presentation
            }
        }
    }

    private func finishPendingSongNavigation() {
        isPlayerPresentationActive = false
        isPlayerDismissalRequested = false
        requestedPlayerPage = nil
        nowPlayingSharePresentation = nil
        guard let route = pendingMusicRoute else { return }
        pendingMusicRoute = nil
        navigate(to: route)
    }

    private func navigate(
        to route: ContentRoute,
        in tab: ContentTab
    ) {
        var path = navigationPaths[tab] ?? NavigationPath()
        path.append(route)
        navigationPaths[tab] = path
    }

    private func navigate(to route: MusicRoute) {
        var path = navigationPaths[selectedTab] ?? NavigationPath()
        path.append(route)
        navigationPaths[selectedTab] = path
    }
}

/// The floating bar is the only reader of the measured per-tab horizontal
/// bounds. A bounds update re-evaluates this leaf, not `ContentView`, its tabs
/// or their content.
private struct FloatingMiniPlayerBar: View {
    let geometry: ContentColumnGeometryStore
    let tab: ContentTab
    let collectionPalette: ArtworkDetailPalette?
    let onOpen: (NowPlayingPage?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let rootWidth = proxy.size.width
            let bounds = geometry.bounds(for: tab)
            let leading = CGFloat(
                max(0, min(bounds?.minX ?? 0, Double(rootWidth)))
            )
            let trailing = CGFloat(
                max(
                    0,
                    min(
                        Double(rootWidth) - (bounds?.maxX ?? Double(rootWidth)),
                        Double(rootWidth) - Double(leading)
                    )
                )
            )
            let columnWidth = max(0, rootWidth - leading - trailing)
            TabletMiniPlayerView(
                collectionPalette: collectionPalette,
                usesWideLayout:
                    columnWidth
                    - ContentView.floatingMiniPlayerOuterPadding * 2
                    - ContentView.floatingMiniPlayerWideContentPadding
                    >= TabletMiniPlayerView.minimumControlsWidth,
                onOpen: onOpen
            )
            .padding(
                .leading,
                leading + ContentView.floatingMiniPlayerOuterPadding
            )
            .padding(
                .trailing,
                trailing + ContentView.floatingMiniPlayerOuterPadding
            )
            .padding(
                .bottom,
                MusicCollectionLayout.miniPlayerScreenBottomInset
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
        }
        // The overlay ignores the bottom safe area and the keyboard, so the bar
        // stays at the window's bottom edge instead of an inset tab frame.
        .ignoresSafeArea(.all, edges: .bottom)
    }
}
