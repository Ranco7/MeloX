import Foundation

struct Song {
    let id: Int
    init(id: Int, name: String = "", artists: [Int] = []) { self.id = id }
}

struct Profile { let id = 1 }
enum L10n {
    static func string(_ key: String) -> String { key }
    static func format(_ key: String, _ arguments: CVarArg...) -> String { key }
}
func makeArtworkURL(from text: String?, dimension: Int) -> URL? { nil }
enum APIError: Error {
    case invalidResponse, requestEncoding
    case emptyResponse(statusCode: Int)
    case server(statusCode: Int, message: String)
}

@MainActor final class Client {
    var roomSnapshots: [Data] = []
    var startedPresenceRequest = false
    var transportErrors: [Error] = []
    var reports: [String] = []
    var onTransportReport: (() -> Void)?

    func eapi<T: Decodable>(
        _ path: String, data: [String: Any] = [:], authenticated: Bool
    ) async throws -> T {
        if path == "/api/listen/together/play/command/report" {
            reports.append(data["commandInfo"] as? String ?? "")
            onTransportReport?()
            if !transportErrors.isEmpty { throw transportErrors.removeFirst() }
            return try JSONDecoder().decode(T.self, from: Data(#"{"code":200,"data":{"success":true}}"#.utf8))
        }
        guard path == "/api/listen/together/sync/playlist/get", !roomSnapshots.isEmpty else {
            throw APIError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: roomSnapshots.removeFirst())
    }

    func weapi<T: Decodable>(_ path: String) async throws -> T {
        startedPresenceRequest = true
        // The next playback snapshot must arrive before this status request finishes.
        try await Task.sleep(for: .seconds(20))
        throw APIError.invalidResponse
    }
}

@MainActor final class NeteaseAPI {
    let client = Client()
    func validate(responseCode: Int, message: String?) throws {}
    func accountProfile() async throws -> Profile { Profile() }
    func songDetails(ids: [Int]) async throws -> [Song] { ids.map { Song(id: $0) } }
}

@MainActor final class PlayerStore {
    var onListenTogetherTransport: ((ListenTogetherCommandType, Int?) -> Void)?
    var onListenTogetherQueueEdit: (() -> Void)?
    var currentSong: Song? = Song(id: 1)
    var queue = [Song(id: 1), Song(id: 9)]
    var listenTogetherReportedPlaying = false
    var position: TimeInterval = 0
    var listenTogetherDisplaySongIDs: [Int] { queue.map(\.id) }
    var listenTogetherRandomSongIDs: [Int] { listenTogetherDisplaySongIDs }
    var listenTogetherPublishedSongIDs: [Int] { listenTogetherDisplaySongIDs }
    var updates: [(Int, Double, Bool)] = []
    func estimatedProgress() -> TimeInterval { position }
    func beginListenTogetherSession() {}
    func endListenTogetherSession() {}
    func restore() async {}

#if IOS_LISTEN_TOGETHER
    func synchronizeListenTogetherPlayback(
        songs: [Song], targetSongID: Int, progress: Double, isPlaying: Bool,
        adoptsRoomPlayMode: Bool, playMode: String?
    ) {
        apply(songs: songs, targetSongID: targetSongID, progress: progress, isPlaying: isPlaying)
    }
#else
    func synchronizeListenTogetherPlayback(
        songs: [Song], targetSongID: Int, progress: Double, isPlaying: Bool, playMode: String?
    ) {
        apply(songs: songs, targetSongID: targetSongID, progress: progress, isPlaying: isPlaying)
    }
#endif

    func synchronizeListenTogetherQueue(songs: [Song], playMode: String?) { queue = songs }

    private func apply(songs: [Song], targetSongID: Int, progress: Double, isPlaying: Bool) {
        queue = songs
        currentSong = songs.first { $0.id == targetSongID }
        listenTogetherReportedPlaying = isPlaying
        updates.append((targetSongID, progress, isPlaying))
    }
}

@main struct ListenTogetherSyncChecks {
    @MainActor static func main() async throws {
        try await playbackContinuesWhilePresenceWaits()
        try await pendingPlaylistDoesNotBlockTransport()
        try await reportsRetryWithoutReplayingOlderIntent()
        print("PASS: paused polling, slow presence, pending playlist, transient retries, and latest transport")
    }

    @MainActor static func makeRoom() throws -> (NeteaseAPI, PlayerStore, ListenTogetherStore) {
        let api = NeteaseAPI()
        let player = PlayerStore()
        let store = ListenTogetherStore(api: api, player: player)
        let room = try JSONDecoder().decode(
            ListenTogetherRoom.self, from: Data(#"{"roomId":"test","creatorId":"2"}"#.utf8)
        )
        store.establishSession(room: room, localUserID: 1)
        return (api, player, store)
    }

    @MainActor static func playbackContinuesWhilePresenceWaits() async throws {
        let (api, player, store) = try makeRoom()
        defer { store.clearSession() }
        api.client.roomSnapshots = [
            snapshot(sequence: 1, position: 0, playing: false),
            snapshot(sequence: 2, position: 55_000, playing: true),
        ]
        store.startMonitoring()
        let deadline = ContinuousClock.now + .seconds(3)
        while player.updates.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(api.client.startedPresenceRequest && player.updates.count == 2)
        precondition(player.updates[1].2 && player.updates[1].1 >= 55)
    }

    @MainActor static func pendingPlaylistDoesNotBlockTransport() async throws {
        let (api, player, store) = try makeRoom()
        defer { store.clearSession() }
        store.queueReportTask = Task { try? await Task.sleep(for: .seconds(20)) }
        api.client.roomSnapshots = [snapshot(sequence: 1, position: 42_000, playing: false)]
        try await store.synchronizeFromServer(initial: false)
        precondition(player.updates.count == 1 && player.updates[0] == (1, 42, false))
        precondition(player.queue.map(\.id) == [1, 9] && store.lastPlaylistSignature == nil)
    }

    @MainActor static func reportsRetryWithoutReplayingOlderIntent() async throws {
        let (api, player, store) = try makeRoom()
        defer { store.clearSession() }
        api.client.transportErrors = [URLError(.networkConnectionLost)]
        player.position = 42
        store.playerTransportDidChange(type: .progress, formerSongID: 1)
        await store.transportReportTask?.value
        precondition(api.client.reports.count == 2 && api.client.reports[0] == api.client.reports[1])

        api.client.reports = []
        api.client.transportErrors = [URLError(.timedOut)]
        api.client.onTransportReport = { [weak store] in
            guard api.client.reports.count == 1 else { return }
            player.position = 18
            store?.playerTransportDidChange(type: .pause, formerSongID: 1)
        }
        store.playerTransportDidChange(type: .goTo, formerSongID: 3)
        await store.transportReportTask?.value
        api.client.onTransportReport = nil
        precondition(api.client.reports.count == 2)
        let latest = try JSONSerialization.jsonObject(with: Data(api.client.reports[1].utf8)) as? [String: Any]
        precondition(latest?["commandType"] as? String == "GOTO")
        precondition(latest?["playStatus"] as? String == "PAUSE")
        precondition(latest?["progress"] as? Int == 18_000)

        api.client.reports = []
        api.client.transportErrors = [APIError.server(statusCode: 403, message: "Denied")]
        store.playerTransportDidChange(type: .play, formerSongID: 1)
        await store.transportReportTask?.value
        precondition(api.client.reports.count == 1 && store.pendingTransportReport == nil)
    }

    static func snapshot(sequence: Int, position: Int, playing: Bool) -> Data {
        Data("""
        {"code":200,"data":{"playlist":{"displayList":{"result":["1"]}},
        "playCommand":{"userId":2,"serverSeq":\(sequence),"targetSongId":"1",
        "playStatus":"\(playing ? "PLAY" : "PAUSE")","progress":\(position)}}}
        """.utf8)
    }
}
