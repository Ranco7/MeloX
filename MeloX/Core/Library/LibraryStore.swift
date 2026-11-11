import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var profile: AccountProfile?
    private(set) var accountDetail: AccountDetail?
    private(set) var favoriteSongs: [Song] = []
    private(set) var playlistContentRevisions: [Int: Int] = [:]
    private(set) var favoritePlaylists: [Playlist] = []
    private(set) var favoriteAlbums: [Album] = []
    private(set) var favoriteArtists: [Artist] = []
    private(set) var subscribedPodcasts: [Podcast] = []
    private(set) var recentSongs: [Song] = []
    private(set) var likedPlaylistID: Int?
    private(set) var favoriteSongTotalCount = 0
    private(set) var favoriteSongsNextOffset = 0
    private(set) var isLoadingMoreFavoriteSongs = false
    private(set) var favoriteSongsLoadMoreError: String?
    private(set) var subscribedPodcastTotalCount = 0
    private(set) var subscribedPodcastsNextOffset = 0
    private(set) var hasMoreSubscribedPodcasts = false
    private(set) var isLoadingMoreSubscribedPodcasts = false
    private(set) var subscribedPodcastsLoadMoreError: String?
    private(set) var phase: LoadingPhase = .loaded
    private(set) var errorMessage: String?
    private(set) var favoriteFailureID: UUID?

    @ObservationIgnored
    private let api: NeteaseAPI

    @ObservationIgnored
    private let settings: AppSettings

    @ObservationIgnored
    private var loadedCookie: String?

    @ObservationIgnored
    private var lastSuccessfulRefresh: Date?

    @ObservationIgnored
    private var refreshingCookie: String?

    @ObservationIgnored
    private var favoriteSongIDs: [Int] = []

    private var favoriteSongIDSet: Set<Int> = []

    @ObservationIgnored
    private let favoriteSongPageSize = 100

    @ObservationIgnored
    private var favoriteSongPageLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var favoriteSongPageLoadID: UUID?

    @ObservationIgnored
    private let subscribedPodcastPageSize = 50

    @ObservationIgnored
    private var subscribedPodcastPageLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var subscribedPodcastPageLoadID: UUID?

    @ObservationIgnored
    private let favoriteActions = OptimisticFavoriteActions<LibraryFavoriteKey>()

    @ObservationIgnored
    private var favoriteAccountCookie: String?

    @ObservationIgnored
    private var favoriteAccountGeneration = UUID()

    init(api: NeteaseAPI, settings: AppSettings) {
        self.api = api
        self.settings = settings
        favoriteAccountCookie = settings.cookie
        favoriteActions.onFailure = { [weak self] _ in self?.favoriteFailureID = UUID() }
    }

    var isLoggedIn: Bool {
        !settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var ownedPlaylists: [Playlist] {
        guard let userID = profile?.id else { return [] }
        return favoritePlaylists.filter { $0.creator?.userID == userID }
    }

    var hasMoreFavoriteSongs: Bool {
        favoriteSongsNextOffset < favoriteSongTotalCount
    }

    var canStartHeartMode: Bool {
        likedPlaylistID != nil && favoriteSongTotalCount > 0
    }

    func randomHeartModeSeedSongID() -> Int? {
        favoriteSongIDs.randomElement()
    }

    func contains(song: Song) -> Bool {
        favoriteSongIDSet.contains(song.id)
    }

    func contains(playlist: Playlist) -> Bool {
        favoritePlaylists.contains { $0.id == playlist.id }
    }

    func contains(artist: Artist) -> Bool {
        favoriteArtists.contains { $0.id == artist.id }
    }

    func contains(album: Album) -> Bool {
        favoriteAlbums.contains { $0.id == album.id }
    }

    func contains(podcast: Podcast) -> Bool {
        subscribedPodcasts.contains { $0.id == podcast.id }
    }

    func recordRecentlyPlayed(_ song: Song) {
        guard settings.isContentFeatureEnabled(.listeningHistory) else {
            return
        }
        recentSongs.removeAll { $0.id == song.id }
        recentSongs.insert(song, at: 0)
        if recentSongs.count > 100 {
            recentSongs.removeLast(recentSongs.count - 100)
        }
        persistContentInBackground()
    }

    func canUnsubscribe(_ playlist: Playlist) -> Bool {
        playlist.creator?.userID != profile?.id
    }

    /// The server rejects subscribing to one's own playlist, and the liked
    /// songs playlist is owned implicitly. When the account identity is not
    /// available yet, keep the action visible instead of guessing.
    func canToggleSaved(_ playlist: Playlist) -> Bool {
        if playlist.id == likedPlaylistID {
            return false
        }
        guard let userID = profile?.id else { return true }
        return playlist.creator?.userID != userID
    }

    func refresh(force: Bool = false) async {
        let cookie = settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else {
            clearAccountData()
            return
        }
        synchronizeFavoriteAccount()
        guard refreshingCookie != cookie else { return }
        let isFresh = lastSuccessfulRefresh.map {
            Date().timeIntervalSince($0) < 300
        } ?? false
        guard force || loadedCookie != cookie || phase != .loaded || !isFresh else { return }
        let favoriteReadRevision = favoriteActions.revision
        refreshingCookie = cookie
        defer {
            if refreshingCookie == cookie {
                refreshingCookie = nil
            }
        }

        if loadedCookie != cookie {
            clearRemoteContent()
            loadedCookie = cookie
            if let snapshot: LibraryContentSnapshot = await api.pageContentCache.value(
                for: LibraryContentSnapshot.cacheKey
            ) {
                guard isCurrentRefresh(cookie) else { return }
                restoreContent(snapshot)
                reapplyFavoriteActions(readRevision: favoriteReadRevision) { _ in true }
            }
            guard isCurrentRefresh(cookie) else { return }
        }
        phase = .loading
        errorMessage = nil
        favoriteSongsLoadMoreError = nil
        subscribedPodcastsLoadMoreError = nil

        do {
            let loadedProfile = try await api.accountProfile()
            guard isCurrentRefresh(cookie) else { return }

            profile = loadedProfile
            loadedCookie = cookie

            var partialFailures: [String] = []
            do {
                let loadedAccountDetail = try await api.userDetail(
                    userID: loadedProfile.id
                )
                guard isCurrentRefresh(cookie) else { return }
                accountDetail = loadedAccountDetail
                profile = loadedAccountDetail.profile
            } catch is CancellationError {
                return
            } catch {
                // The account endpoint still provides enough identity data
                // for the settings row when extended profile details fail.
            }

            var loadedPlaylists: [Playlist] = []
            do {
                loadedPlaylists = try await api.userPlaylists(userID: loadedProfile.id)
                guard isCurrentRefresh(cookie) else { return }
                // 网易云把“我喜欢的音乐”作为返回列表的第一项；参考项目
                // 同样在歌单页隐藏这一项，歌曲页单独展示其中的歌曲。
                likedPlaylistID = loadedPlaylists.first?.id
                favoritePlaylists = Array(loadedPlaylists.dropFirst())
                reapplyFavoriteActions(readRevision: favoriteReadRevision) { if case .playlist = $0 { true } else { false } }
            } catch is CancellationError {
                return
            } catch {
                partialFailures.append(L10n.format("ui.library.error.playlists", error.localizedDescription))
            }

            do {
                let albums = try await api.subscribedAlbums()
                guard isCurrentRefresh(cookie) else { return }
                favoriteAlbums = albums
                reapplyFavoriteActions(readRevision: favoriteReadRevision) { if case .album = $0 { true } else { false } }
            } catch is CancellationError {
                return
            } catch {
                partialFailures.append(
                    L10n.format("ui.library.error.favorite_albums", error.localizedDescription)
                )
            }

            do {
                let artists = try await api.subscribedArtists()
                guard isCurrentRefresh(cookie) else { return }
                favoriteArtists = artists
                reapplyFavoriteActions(readRevision: favoriteReadRevision) { if case .artist = $0 { true } else { false } }
            } catch is CancellationError {
                return
            } catch {
                partialFailures.append(
                    L10n.format("ui.library.error.favorite_artists", error.localizedDescription)
                )
            }

            if settings.isContentFeatureEnabled(.podcasts) {
                do {
                    let page = try await api.subscribedPodcasts(
                        limit: subscribedPodcastPageSize
                    )
                    guard isCurrentRefresh(cookie) else { return }
                    subscribedPodcasts = normalizedSubscribedPodcasts(
                        page.podcasts
                    )
                    subscribedPodcastTotalCount = max(
                        page.totalCount ?? subscribedPodcasts.count,
                        subscribedPodcasts.count
                    )
                    subscribedPodcastsNextOffset = page.podcasts.count
                    hasMoreSubscribedPodcasts = page.hasMore
                    subscribedPodcastsLoadMoreError = nil
                    reapplyFavoriteActions(readRevision: favoriteReadRevision) { if case .podcast = $0 { true } else { false } }
                } catch is CancellationError {
                    return
                } catch {
                    partialFailures.append(
                        L10n.format("ui.library.error.subscribed_podcasts", error.localizedDescription)
                    )
                }
            }

            do {
                let loadedSongIDs = try await api.likedSongIDs(
                    userID: loadedProfile.id,
                    likedPlaylistID: likedPlaylistID
                )
                let firstPage = try await api.songDetailsPage(
                    ids: loadedSongIDs,
                    offset: 0,
                    limit: favoriteSongPageSize
                )
                guard isCurrentRefresh(cookie) else { return }
                guard loadedSongIDs.isEmpty || !firstPage.songs.isEmpty else {
                    throw APIError.invalidResponse
                }
                favoriteSongIDs = loadedSongIDs
                favoriteSongIDSet = Set(loadedSongIDs)
                favoriteSongTotalCount = loadedSongIDs.count
                favoriteSongs = firstPage.songs
                favoriteSongsNextOffset = firstPage.nextOffset
                favoriteSongsLoadMoreError = nil
                reapplyFavoriteActions(readRevision: favoriteReadRevision) { if case .song = $0 { true } else { false } }
            } catch is CancellationError {
                return
            } catch {
                partialFailures.append(L10n.format("ui.library.error.favorite_songs", error.localizedDescription))
            }

            if settings.isContentFeatureEnabled(.listeningHistory) {
                do {
                    let songs = try await api.recentSongs()
                    guard isCurrentRefresh(cookie) else { return }
                    recentSongs = songs
                } catch is CancellationError {
                    return
                } catch {
                    partialFailures.append(
                        L10n.format("ui.library.error.history", error.localizedDescription)
                    )
                }
            }

            guard isCurrentRefresh(cookie) else { return }
            if !partialFailures.isEmpty {
                errorMessage = L10n.format(
                    "ui.library.error.partial",
                    partialFailures.joined(separator: "\n")
                )
            }
            lastSuccessfulRefresh = partialFailures.isEmpty ? Date() : nil
            phase = .loaded
            await persistContent()
        } catch is CancellationError {
            return
        } catch APIError.notLoggedIn {
            guard isCurrentRefresh(cookie) else { return }
            settings.clearAccount()
            clearAccountData()
        } catch {
            guard isCurrentRefresh(cookie) else { return }
            lastSuccessfulRefresh = nil
            if profile == nil {
                phase = .failed(error.localizedDescription)
            } else {
                phase = .loaded
                errorMessage = L10n.format("ui.library.error.account_refresh", error.localizedDescription)
            }
        }
    }

    private func isCurrentRefresh(_ cookie: String) -> Bool {
        !Task.isCancelled && refreshingCookie == cookie
            && settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines) == cookie
    }

    func loadMoreFavoriteSongs() async {
        if let favoriteSongPageLoadTask {
            await favoriteSongPageLoadTask.value
            return
        }

        guard hasMoreFavoriteSongs else { return }

        let requestedOffset = favoriteSongsNextOffset
        let requestedIDs = favoriteSongIDs
        let loadID = UUID()
        let loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadFavoriteSongsPage(
                ids: requestedIDs,
                offset: requestedOffset
            )
        }
        favoriteSongPageLoadID = loadID
        favoriteSongPageLoadTask = loadTask

        await loadTask.value

        guard favoriteSongPageLoadID == loadID else { return }
        favoriteSongPageLoadTask = nil
        favoriteSongPageLoadID = nil
    }

    func loadFavoriteSongForLocation(_ songID: Int) async -> Bool {
        if favoriteSongs.contains(where: { $0.id == songID }) { return true }
        let requestedIDs = favoriteSongIDs
        guard let index = requestedIDs.firstIndex(of: songID) else { return false }

        while favoriteSongsNextOffset <= index, hasMoreFavoriteSongs {
            guard !Task.isCancelled else { return false }
            let previousOffset = favoriteSongsNextOffset
            await loadMoreFavoriteSongs()
            guard !Task.isCancelled,
                  favoriteSongIDs == requestedIDs,
                  favoriteSongsNextOffset > previousOffset else { return false }
        }
        return favoriteSongs.contains(where: { $0.id == songID })
    }

    func loadRemainingFavoriteSongs() async {
        while hasMoreFavoriteSongs {
            guard !Task.isCancelled else { return }
            let previousOffset = favoriteSongsNextOffset
            await loadMoreFavoriteSongs()
            guard favoriteSongsNextOffset > previousOffset else { return }
        }
    }

    func favoriteSongsForPlayback() async throws -> [Song] {
        if let favoriteSongPageLoadTask {
            await favoriteSongPageLoadTask.value
        }

        let requestedIDs = favoriteSongIDs
        let songs = try await api.songDetailsCollection(
            ids: requestedIDs,
            prefetched: favoriteSongs
        )
        try Task.checkCancellation()

        if favoriteSongIDs == requestedIDs {
            favoriteSongs = songs
            favoriteSongsNextOffset = requestedIDs.count
            favoriteSongsLoadMoreError = nil
        }
        return songs
    }

    private func loadFavoriteSongsPage(
        ids requestedIDs: [Int],
        offset requestedOffset: Int
    ) async {
        isLoadingMoreFavoriteSongs = true
        favoriteSongsLoadMoreError = nil
        defer { isLoadingMoreFavoriteSongs = false }

        do {
            let page = try await api.songDetailsPage(
                ids: requestedIDs,
                offset: requestedOffset,
                limit: favoriteSongPageSize
            )
            try Task.checkCancellation()
            guard favoriteSongIDs == requestedIDs,
                  favoriteSongsNextOffset == requestedOffset else {
                return
            }

            var loadedIDs = Set(favoriteSongs.map(\.id))
            favoriteSongs.append(
                contentsOf: page.songs.filter {
                    loadedIDs.insert($0.id).inserted
                }
            )
            favoriteSongsNextOffset = page.nextOffset
            await persistContent()
        } catch is CancellationError {
            return
        } catch {
            favoriteSongsLoadMoreError = error.localizedDescription
        }
    }

    func loadMoreSubscribedPodcasts() async {
        guard settings.isContentFeatureEnabled(.podcasts) else { return }
        if let subscribedPodcastPageLoadTask {
            await subscribedPodcastPageLoadTask.value
            return
        }

        guard hasMoreSubscribedPodcasts else { return }

        let requestedOffset = subscribedPodcastsNextOffset
        let loadID = UUID()
        let loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadSubscribedPodcastPage(
                offset: requestedOffset
            )
        }
        subscribedPodcastPageLoadID = loadID
        subscribedPodcastPageLoadTask = loadTask

        await loadTask.value

        guard subscribedPodcastPageLoadID == loadID else { return }
        subscribedPodcastPageLoadTask = nil
        subscribedPodcastPageLoadID = nil
    }

    func loadRemainingSubscribedPodcasts() async {
        while hasMoreSubscribedPodcasts {
            guard !Task.isCancelled else { return }
            let previousOffset = subscribedPodcastsNextOffset
            await loadMoreSubscribedPodcasts()
            guard subscribedPodcastsNextOffset > previousOffset else {
                return
            }
        }
    }

    private func loadSubscribedPodcastPage(
        offset requestedOffset: Int
    ) async {
        let favoriteReadRevision = favoriteActions.revision
        let accountRead = favoriteRead()
        isLoadingMoreSubscribedPodcasts = true
        subscribedPodcastsLoadMoreError = nil
        defer { isLoadingMoreSubscribedPodcasts = false }

        do {
            let page = try await api.subscribedPodcasts(
                offset: requestedOffset,
                limit: subscribedPodcastPageSize
            )
            try Task.checkCancellation()
            guard isCurrentFavoriteRead(accountRead), subscribedPodcastsNextOffset == requestedOffset else {
                return
            }

            var loadedIDs = Set(subscribedPodcasts.map(\.id))
            subscribedPodcasts.append(
                contentsOf: normalizedSubscribedPodcasts(
                    page.podcasts
                ).filter {
                    loadedIDs.insert($0.id).inserted
                }
            )
            subscribedPodcastsNextOffset =
                requestedOffset + page.podcasts.count
            subscribedPodcastTotalCount = max(
                page.totalCount ?? subscribedPodcastTotalCount,
                subscribedPodcasts.count
            )
            hasMoreSubscribedPodcasts =
                page.hasMore && !page.podcasts.isEmpty
            reapplyFavoriteActions(readRevision: favoriteReadRevision) { if case .podcast = $0 { true } else { false } }
            await persistContent()
        } catch is CancellationError {
            return
        } catch {
            subscribedPodcastsLoadMoreError =
                error.localizedDescription
        }
    }

    func favoriteRead() -> LibraryFavoriteRead {
        synchronizeFavoriteAccount()
        return LibraryFavoriteRead(cookie: settings.cookie, revision: favoriteActions.revision,
                            accountGeneration: favoriteAccountGeneration)
    }

    func acceptAlbumStatus(_ album: Album, isSubscribed: Bool, read: LibraryFavoriteRead) {
        guard isCurrentFavoriteRead(read) else { return }
        let value = favoriteActions.resolvedValue(for: .album(album.id), remoteValue: isSubscribed, readRevision: read.revision)
        setLocalAlbum(album, isSubscribed: value)
    }

    func acceptArtistStatus(_ artist: Artist, read: LibraryFavoriteRead) {
        guard isCurrentFavoriteRead(read) else { return }
        // Artist details may omit `followed`; the decoder defaults it to false.
        // Preserve membership known from the subscription list in that case.
        let value = favoriteActions.resolvedValue(for: .artist(artist.id), remoteValue: artist.isFollowed || contains(artist: artist), readRevision: read.revision)
        setLocalArtist(artist, isFollowed: value)
    }

    func acceptPodcastStatus(_ podcast: Podcast, read: LibraryFavoriteRead) {
        guard isCurrentFavoriteRead(read) else { return }
        let value = favoriteActions.resolvedValue(for: .podcast(podcast.id), remoteValue: podcast.isSubscribed, readRevision: read.revision)
        setLocalPodcast(podcast, isSubscribed: value, updatesTotalCount: false)
    }

    func toggle(song: Song) {
        guard prepareFavoriteAction() else { return }
        let cookie = settings.cookie
        let generation = favoriteAccountGeneration
        let likedPlaylist = likedPlaylistID
        favoriteActions.toggle(.song(song.id), currentValue: contains(song: song)) { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { return }
            setLocalSong(song, isLiked: value)
        } write: { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { throw CancellationError() }
            try await api.setSongLiked(id: song.id, isLiked: value)
            if let id = likedPlaylist, isCurrentFavoriteAccount(cookie, generation: generation) {
                await self.refreshPlaylistAfterMutation(id: id, cookie: cookie)
            }
        }
    }

    func toggle(playlist: Playlist) {
        guard prepareFavoriteAction(), canToggleSaved(playlist) else { return }
        let cookie = settings.cookie
        let generation = favoriteAccountGeneration
        favoriteActions.toggle(.playlist(playlist.id), currentValue: contains(playlist: playlist)) { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { return }
            setLocalPlaylist(playlist, isSubscribed: value)
        } write: { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { throw CancellationError() }
            try await api.setPlaylistSubscribed(id: playlist.id, isSubscribed: value)
        }
    }

    func toggle(album: Album) {
        guard prepareFavoriteAction() else { return }
        let cookie = settings.cookie
        let generation = favoriteAccountGeneration
        favoriteActions.toggle(.album(album.id), currentValue: contains(album: album)) { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { return }
            setLocalAlbum(album, isSubscribed: value)
        } write: { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { throw CancellationError() }
            try await api.setAlbumSubscribed(id: album.id, isSubscribed: value)
        }
    }

    func toggle(artist: Artist) {
        guard prepareFavoriteAction() else { return }
        let cookie = settings.cookie
        let generation = favoriteAccountGeneration
        favoriteActions.toggle(.artist(artist.id), currentValue: contains(artist: artist)) { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { return }
            setLocalArtist(artist, isFollowed: value)
        } write: { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { throw CancellationError() }
            try await api.setArtistFollowed(id: artist.id, isFollowed: value)
        }
    }

    func toggle(podcast: Podcast) {
        guard prepareFavoriteAction() else { return }
        let cookie = settings.cookie
        let generation = favoriteAccountGeneration
        favoriteActions.toggle(.podcast(podcast.id), currentValue: contains(podcast: podcast)) { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { return }
            setLocalPodcast(podcast, isSubscribed: value)
        } write: { [weak self] value in
            guard let self, isCurrentFavoriteAccount(cookie, generation: generation) else { throw CancellationError() }
            try await api.setPodcastSubscribed(id: podcast.id, isSubscribed: value)
        }
    }

    private func prepareFavoriteAction() -> Bool {
        guard isLoggedIn else {
            errorMessage = APIError.notLoggedIn.localizedDescription
            return false
        }
        synchronizeFavoriteAccount()
        return true
    }

    private func synchronizeFavoriteAccount() {
        guard favoriteAccountCookie != settings.cookie else { return }
        favoriteActions.reset()
        favoriteFailureID = nil
        favoriteAccountGeneration = UUID()
        favoriteAccountCookie = settings.cookie
        clearRemoteContent()
    }

    private func isCurrentFavoriteAccount(_ cookie: String, generation: UUID) -> Bool {
        cookie == settings.cookie && generation == favoriteAccountGeneration
    }

    private func isCurrentFavoriteRead(_ read: LibraryFavoriteRead) -> Bool {
        isCurrentFavoriteAccount(read.cookie, generation: read.accountGeneration)
    }

    private func setLocalPlaylist(_ playlist: Playlist, isSubscribed: Bool) {
        guard contains(playlist: playlist) != isSubscribed else { return }
        favoritePlaylists.removeAll { $0.id == playlist.id }
        if isSubscribed {
            var summary = playlist
            summary.tracks = []
            favoritePlaylists.insert(summary, at: 0)
        }
        persistContentInBackground()
    }

    private func setLocalAlbum(_ album: Album, isSubscribed: Bool) {
        guard contains(album: album) != isSubscribed else { return }
        favoriteAlbums.removeAll { $0.id == album.id }
        if isSubscribed { favoriteAlbums.insert(album, at: 0) }
        persistContentInBackground()
    }

    private func setLocalArtist(_ artist: Artist, isFollowed: Bool) {
        guard contains(artist: artist) != isFollowed else { return }
        favoriteArtists.removeAll { $0.id == artist.id }
        if isFollowed { favoriteArtists.insert(artist, at: 0) }
        persistContentInBackground()
    }

    private func reapplyFavoriteActions(readRevision: UInt64, includes: (LibraryFavoriteKey) -> Bool) {
        favoriteActions.reapply(where: includes, readRevision: readRevision) { key in
            switch key {
            case .song(let id): favoriteSongIDSet.contains(id)
            case .playlist(let id): favoritePlaylists.contains { $0.id == id }
            case .album(let id): favoriteAlbums.contains { $0.id == id }
            case .artist(let id): favoriteArtists.contains { $0.id == id }
            case .podcast(let id): subscribedPodcasts.contains { $0.id == id }
            }
        }
    }

    func canDelete(_ playlist: Playlist) -> Bool {
        guard isLoggedIn, let userID = profile?.id else { return false }
        return playlist.creator?.userID == userID && playlist.id != likedPlaylistID
    }

    func deletePlaylist(_ playlist: Playlist) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        guard canDelete(playlist) else { throw LibraryOperationError.playlistIsNotOwned }
        let cookie = settings.cookie
        try await api.deletePlaylist(id: playlist.id)
        await api.pageContentCache.remove(for: PlaylistContentSnapshot.cacheKey(id: playlist.id), cookie: cookie)
        guard cookie == settings.cookie else { return }
        favoritePlaylists.removeAll { $0.id == playlist.id }
        await persistContent()
    }

    func createPlaylist(name: String, isPrivate: Bool) async throws {
        guard isLoggedIn, let profile else { throw APIError.notLoggedIn }
        let cookie = settings.cookie
        let created = try await api.createPlaylist(name: name, isPrivate: isPrivate)
        guard cookie == settings.cookie else { return }
        let summary = Playlist(
            id: created.id,
            name: created.name,
            coverURLString: created.coverURLString,
            creator: UserSummary(userID: profile.id, nickname: profile.nickname)
        )
        favoritePlaylists.insert(summary, at: 0)
        await persistContent()
    }

    func remove(song: Song, from playlist: Playlist) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        guard canDelete(playlist) else { throw LibraryOperationError.playlistIsNotOwned }
        let cookie = settings.cookie
        do {
            try await api.removeSong(id: song.id, fromPlaylistID: playlist.id)
        } catch let error as PlaylistTrackMutationError {
            await refreshPlaylistAfterMutation(id: playlist.id, cookie: cookie)
            throw error
        }
        if cookie == settings.cookie, let index = favoritePlaylists.firstIndex(where: { $0.id == playlist.id }) {
            favoritePlaylists[index].removeSong(id: song.id)
        }
        await refreshPlaylistAfterMutation(id: playlist.id, cookie: cookie)
    }

    func add(song: Song, to playlist: Playlist) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        guard playlist.creator?.userID == profile?.id else {
            throw LibraryOperationError.playlistIsNotOwned
        }
        let cookie = settings.cookie
        do {
            try await api.addSong(id: song.id, toPlaylistID: playlist.id)
        } catch let error as PlaylistTrackMutationError {
            await refreshPlaylistAfterMutation(id: playlist.id, cookie: cookie)
            throw error
        }
        await refreshPlaylistAfterMutation(id: playlist.id, cookie: cookie)
    }

    // A successful write must not leave an old offline detail snapshot behind.
    // Summary refresh failure is not reported as a failed write (avoid duplicate retries).
    private func refreshPlaylistAfterMutation(id: Int, cookie: String) async {
        // Invalidate the account that performed the write, even after a switch.
        // Advance revision before suspension so in-flight detail reads are obsolete.
        if cookie == settings.cookie {
            playlistContentRevisions[id, default: 0] += 1
        }
        await api.pageContentCache.remove(for: PlaylistContentSnapshot.cacheKey(id: id), cookie: cookie)
        guard cookie == settings.cookie else { return }
        // Liked songs have no image summary in the sidebar; avoid an unused
        // potentially huge trackIds response for every heart toggle.
        if id != likedPlaylistID {
            do {
                let summary = try await api.playlist(id: id, trackLimit: 0)
                guard cookie == settings.cookie else { return }
                if let index = favoritePlaylists.firstIndex(where: { $0.id == id }) {
                    favoritePlaylists[index] = summary
                }
            } catch {
                // The write succeeded; do not invite a duplicate write by
                // reporting a summary fetch failure as a mutation failure.
            }
        }
        guard cookie == settings.cookie else { return }
        await persistContent()
    }

    func clearAccountData() {
        favoriteActions.reset()
        favoriteFailureID = nil
        favoriteAccountGeneration = UUID()
        favoriteAccountCookie = settings.cookie
        if let cookie = loadedCookie {
            let cache = api.pageContentCache
            Task { await cache.removeAccount(cookie: cookie) }
        }
        loadedCookie = nil
        clearRemoteContent()
        phase = .loaded
        errorMessage = nil
    }

    func dismissFavoriteFailure(_ id: UUID) {
        if favoriteFailureID == id { favoriteFailureID = nil }
    }

    func clearError() {
        errorMessage = nil
    }

    private func clearRemoteContent() {
        lastSuccessfulRefresh = nil
        favoriteSongPageLoadTask?.cancel()
        favoriteSongPageLoadTask = nil
        favoriteSongPageLoadID = nil
        subscribedPodcastPageLoadTask?.cancel()
        subscribedPodcastPageLoadTask = nil
        subscribedPodcastPageLoadID = nil
        profile = nil
        accountDetail = nil
        favoriteSongs = []
        favoritePlaylists = []
        playlistContentRevisions = [:]
        favoriteAlbums = []
        favoriteArtists = []
        subscribedPodcasts = []
        recentSongs = []
        likedPlaylistID = nil
        favoriteSongIDs = []
        favoriteSongIDSet = []
        favoriteSongTotalCount = 0
        favoriteSongsNextOffset = 0
        isLoadingMoreFavoriteSongs = false
        favoriteSongsLoadMoreError = nil
        subscribedPodcastTotalCount = 0
        subscribedPodcastsNextOffset = 0
        hasMoreSubscribedPodcasts = false
        isLoadingMoreSubscribedPodcasts = false
        subscribedPodcastsLoadMoreError = nil
    }

    private func setLocalSong(
        _ song: Song,
        isLiked: Bool
    ) {
        guard contains(song: song) != isLiked else { return }
        if let index = favoriteSongIDs.firstIndex(of: song.id) {
            favoriteSongIDs.remove(at: index)
            if index < favoriteSongsNextOffset {
                favoriteSongsNextOffset -= 1
            }
        }
        favoriteSongIDSet.remove(song.id)
        favoriteSongs.removeAll { $0.id == song.id }

        if isLiked {
            favoriteSongIDs.insert(song.id, at: 0)
            favoriteSongIDSet.insert(song.id)
            favoriteSongs.insert(song, at: 0)
            favoriteSongsNextOffset += 1
        }
        favoriteSongTotalCount = favoriteSongIDs.count
        persistContentInBackground()
    }

    private func setLocalPodcast(
        _ podcast: Podcast,
        isSubscribed: Bool,
        updatesTotalCount: Bool = true
    ) {
        let wasSubscribed = contains(podcast: podcast)
        guard wasSubscribed != isSubscribed else { return }
        subscribedPodcasts.removeAll { $0.id == podcast.id }

        if isSubscribed {
            var summary = podcast
            summary.isSubscribed = true
            subscribedPodcasts.insert(summary, at: 0)
        }

        if updatesTotalCount {
            subscribedPodcastTotalCount += isSubscribed ? 1 : -1
        }
        subscribedPodcastTotalCount = max(
            subscribedPodcastTotalCount,
            subscribedPodcasts.count
        )
        if updatesTotalCount { subscribedPodcastsNextOffset = subscribedPodcasts.count }
        hasMoreSubscribedPodcasts =
            subscribedPodcastsNextOffset < subscribedPodcastTotalCount
        persistContentInBackground()
    }

    private func restoreContent(_ snapshot: LibraryContentSnapshot) {
        profile = snapshot.profile
        accountDetail = snapshot.accountDetail
        favoriteSongs = snapshot.favoriteSongs
        favoriteSongIDs = snapshot.favoriteSongIDs
        favoriteSongIDSet = Set(snapshot.favoriteSongIDs)
        favoriteSongTotalCount = snapshot.favoriteSongIDs.count
        favoriteSongsNextOffset = snapshot.favoriteSongsNextOffset
        favoritePlaylists = snapshot.favoritePlaylists
        favoriteAlbums = snapshot.favoriteAlbums
        favoriteArtists = snapshot.favoriteArtists
        subscribedPodcasts = snapshot.subscribedPodcasts
        subscribedPodcastTotalCount = snapshot.subscribedPodcastTotalCount
        subscribedPodcastsNextOffset = snapshot.subscribedPodcastsNextOffset
        hasMoreSubscribedPodcasts = snapshot.hasMoreSubscribedPodcasts
        recentSongs = snapshot.recentSongs
        likedPlaylistID = snapshot.likedPlaylistID
    }

    private func persistContentInBackground() {
        Task { [weak self] in await self?.persistContent() }
    }

    private func persistContent() async {
        guard let profile,
              loadedCookie == settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        let snapshot = LibraryContentSnapshot(
            profile: profile,
            accountDetail: accountDetail,
            favoriteSongs: favoriteSongs,
            favoriteSongIDs: favoriteSongIDs,
            favoriteSongsNextOffset: favoriteSongsNextOffset,
            favoritePlaylists: favoritePlaylists,
            favoriteAlbums: favoriteAlbums,
            favoriteArtists: favoriteArtists,
            subscribedPodcasts: subscribedPodcasts,
            subscribedPodcastTotalCount: subscribedPodcastTotalCount,
            subscribedPodcastsNextOffset: subscribedPodcastsNextOffset,
            hasMoreSubscribedPodcasts: hasMoreSubscribedPodcasts,
            recentSongs: recentSongs,
            likedPlaylistID: likedPlaylistID
        )
        await api.pageContentCache.store(snapshot, for: LibraryContentSnapshot.cacheKey)
    }

    private func normalizedSubscribedPodcasts(
        _ podcasts: [Podcast]
    ) -> [Podcast] {
        var identifiers = Set<Int>()
        return podcasts.compactMap { podcast in
            guard podcast.id > 0,
                  identifiers.insert(podcast.id).inserted else {
                return nil
            }
            var subscribedPodcast = podcast
            subscribedPodcast.isSubscribed = true
            return subscribedPodcast
        }
    }
}

private enum LibraryOperationError: LocalizedError {
    case playlistIsNotOwned

    var errorDescription: String? {
        switch self {
        case .playlistIsNotOwned:
            L10n.string("ui.library.error.owned_playlist_only")
        }
    }
}
