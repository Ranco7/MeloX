import Foundation
import OSLog

@MainActor
struct HomeRecommendationFallbackLoader {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MeloX",
        category: "HomeRecommendations"
    )

    private let api: NeteaseAPI
    private let serverFeed: HomeRecommendationFeed
    private let region: HomeMusicRegion
    private let isLoggedIn: Bool
    private let profile: AccountProfile?
    private let ownedPlaylists: [Playlist]
    private let favoritePlaylists: [Playlist]
    private let likedSong: Song?
    private let includesPodcasts: Bool

    init(
        api: NeteaseAPI,
        library: LibraryStore,
        serverFeed: HomeRecommendationFeed,
        region: HomeMusicRegion,
        includesPodcasts: Bool
    ) {
        self.api = api
        self.serverFeed = serverFeed
        self.region = region
        isLoggedIn = library.isLoggedIn
        profile = library.profile
        ownedPlaylists = library.ownedPlaylists
        favoritePlaylists = library.favoritePlaylists
        likedSong = library.favoriteSongs.first
        self.includesPodcasts = includesPodcasts
    }

    func load(
        charts: [Playlist]
    ) async -> [
        HomeRecommendationSlot: HomeRecommendationFallback
    ] {
        async let loadedRecommended = recommendedPlaylists()
        async let loadedTrending = trendingSongs()
        async let loadedTailored = tailoredSongs()
        async let loadedRoaming = roamingSongs()
        async let loadedSimilar = similarSongs()
        async let loadedPrograms = podcastPrograms()

        let (
            recommended,
            trending,
            tailored,
            roaming,
            similar,
            programs
        ) = await (
            loadedRecommended,
            loadedTrending,
            loadedTailored,
            loadedRoaming,
            loadedSimilar,
            loadedPrograms
        )
        guard !Task.isCancelled else { return [:] }

        return makeFallbacks(
            recommended: recommended,
            charts: charts,
            trending: trending,
            tailored: tailored,
            roaming: roaming,
            similar: similar,
            programs: programs
        )
    }

    private func recommendedPlaylists() async -> [Playlist] {
        guard !serverFeed.contains(.recommendedPlaylists) else {
            return []
        }
        do {
            return try await api.recommendedPlaylists(limit: 12)
        } catch {
            Self.logFailure("recommendedPlaylists", error: error)
            return []
        }
    }

    private func tailoredSongs() async -> [Song] {
        guard !serverFeed.contains(.tailoredRecommendation)
        else {
            return []
        }
        do {
            return try await api.personalizedNewSongs(
                region: region,
                limit: 12
            )
        } catch {
            Self.logFailure("personalizedNewSongs", error: error)
            return []
        }
    }

    private func roamingSongs() async -> [Song] {
        guard isLoggedIn,
              !serverFeed.contains(.likedSongRoaming) else {
            return []
        }
        do {
            return try await api.personalFM(
                mode: .explore,
                limit: 12
            )
        } catch {
            Self.logFailure("personalFM", error: error)
            return []
        }
    }

    private func similarSongs() async -> [Song] {
        guard let likedSong,
              !serverFeed.contains(
                  .likedSongRecommendations
              ) else {
            return []
        }
        do {
            return try await api.similarSongs(
                id: likedSong.id,
                limit: 12
            )
        } catch {
            Self.logFailure("similarSongs", error: error)
            return []
        }
    }

    private func podcastPrograms() async -> [PodcastProgram] {
        guard includesPodcasts,
              !serverFeed.contains(
            .listenedPodcastRecommendations
        ) else {
            return []
        }
        do {
            return try await api.recommendedPodcastPrograms(limit: 12)
        } catch {
            Self.logFailure("recommendedPodcastPrograms", error: error)
            return []
        }
    }

    private func trendingSongs() async -> HomeTrendingFallbacks {
        let needsRecent = !serverFeed.contains(
            .recentlyTrending
        )
        let needsRegional = !serverFeed.contains(.regionalHits)
        guard needsRecent || needsRegional else {
            return HomeTrendingFallbacks()
        }

        if region == .all {
            let requestedCount =
                needsRecent && needsRegional ? 24 : 12
            var songs: [Song] = []
            do {
                songs = try await api.topSongs(
                    region: .all,
                    limit: requestedCount
                )
            } catch {
                Self.logFailure("topSongs", error: error)
            }
            if needsRecent && needsRegional {
                return HomeTrendingFallbacks(
                    recent: Array(songs.prefix(12)),
                    regional: Array(
                        songs.dropFirst(12).prefix(12)
                    )
                )
            }
            return HomeTrendingFallbacks(
                recent: needsRecent ? songs : [],
                regional: needsRegional ? songs : []
            )
        }

        async let loadedRecent = topSongs(
            isNeeded: needsRecent,
            region: .all
        )
        async let loadedRegional = topSongs(
            isNeeded: needsRegional,
            region: region
        )
        return await HomeTrendingFallbacks(
            recent: loadedRecent,
            regional: loadedRegional
        )
    }

    private func topSongs(
        isNeeded: Bool,
        region: HomeMusicRegion
    ) async -> [Song] {
        guard isNeeded else { return [] }
        do {
            return try await api.topSongs(
                region: region,
                limit: 12
            )
        } catch {
            Self.logFailure("topSongs", error: error)
            return []
        }
    }

    private func makeFallbacks(
        recommended: [Playlist],
        charts: [Playlist],
        trending: HomeTrendingFallbacks,
        tailored: [Song],
        roaming: [Song],
        similar: [Song],
        programs: [PodcastProgram]
    ) -> [
        HomeRecommendationSlot: HomeRecommendationFallback
    ] {
        var result: [
            HomeRecommendationSlot: HomeRecommendationFallback
        ] = [:]

        result[.recommendedPlaylists] = fallback(
            .recommendedPlaylists,
            content: .playlists(recommended)
        )
        result[.recentlyTrending] = fallback(
            .recentlyTrending,
            content: .songs(trending.recent)
        )
        result[.tailoredRecommendation] =
            HomeRecommendationFallback(
                title: likedSong.map {
                    .tailoredForSong($0.name)
                } ?? .standard,
                content: .songs(tailored)
            )
        result[.charts] = fallback(
            .charts,
            content: .playlists(Array(charts.prefix(12)))
        )
        result[.personalPlaylists] =
            HomeRecommendationFallback(
                title: profile.map {
                    .userPlaylists($0.nickname)
                } ?? .standard,
                content: .playlists(
                    Array(ownedPlaylists.prefix(12))
                )
            )

        let radarPlaylists = favoritePlaylists.filter {
            $0.name.contains("雷达")
        }
        result[.radarPlaylists] =
            HomeRecommendationFallback(
                title: profile.map {
                    .userRadar($0.nickname)
                } ?? .standard,
                content: .playlists(
                    Array(radarPlaylists.prefix(12))
                )
            )
        result[.regionalHits] = HomeRecommendationFallback(
            title: .regionalHits(region),
            content: .songs(trending.regional)
        )
        result[.likedSongRoaming] = fallback(
            .likedSongRoaming,
            content: .songs(roaming)
        )
        result[.likedSongRecommendations] = fallback(
            .likedSongRecommendations,
            content: .songs(similar)
        )
        result[.listenedPodcastRecommendations] = fallback(
            .listenedPodcastRecommendations,
            content: .podcastPrograms(programs)
        )
        return result
    }

    private func fallback(
        _ slot: HomeRecommendationSlot,
        content: HomeRecommendationContent
    ) -> HomeRecommendationFallback {
        HomeRecommendationFallback(
            title: .standard,
            content: content
        )
    }

    private static func logFailure(
        _ endpoint: String,
        error: Error
    ) {
        guard !Task.isCancelled,
              (error as? URLError)?.code != .cancelled else {
            return
        }
        logger.error(
            "Home fallback \(endpoint, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}

private struct HomeTrendingFallbacks {
    var recent: [Song] = []
    var regional: [Song] = []
}
