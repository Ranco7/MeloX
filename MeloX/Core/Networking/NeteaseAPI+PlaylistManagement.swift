import Foundation

extension NeteaseAPI {
    func removeSong(id: Int, fromPlaylistID playlistID: Int) async throws {
        try await manipulatePlaylistTrack(id: id, playlistID: playlistID, operation: "del")
    }

    func manipulatePlaylistTrack(id: Int, playlistID: Int, operation: String) async throws {
        // The original route and parameters follow playlist_tracks.js;
        // use the authenticated versioned EAPI route, as for adding tracks.
        do {
            try await performPlaylistTrackMutation(id: id, playlistID: playlistID, operation: operation)
        } catch APIError.server(let statusCode, _) where statusCode == 502 {
            throw PlaylistTrackMutationError.gateway(operation: operation)
        } catch APIError.emptyResponse(let statusCode) where statusCode == 502 {
            throw PlaylistTrackMutationError.gateway(operation: operation)
        }
    }

    private func performPlaylistTrackMutation(id: Int, playlistID: Int, operation: String) async throws {
        let path = "/api/v1/playlist/manipulate/tracks"
        let trackID = String(id)
        var response: APIStatusResponse = try await client.eapi(
            path,
            data: ["op": operation, "pid": playlistID, "trackIds": "[\"\(trackID)\"]", "imme": "true"],
            authenticated: true
        )
        if response.code == 512 {
            response = try await client.eapi(
                path,
                data: ["op": operation, "pid": playlistID, "trackIds": "[\"\(trackID)\",\"\(trackID)\"]", "imme": "true"],
                authenticated: true
            )
        }
        try validate(responseCode: response.code, message: response.message)
    }

    func deletePlaylist(id: Int) async throws {
        // Mirrors @neteaseapireborn/api/module/playlist_delete.js.
        let response: APIStatusResponse = try await client.weapi(
            "/api/playlist/remove",
            data: ["ids": "[\(id)]"]
        )
        try validate(responseCode: response.code, message: response.message)
    }

    func createPlaylist(name: String, isPrivate: Bool) async throws -> Playlist {
        // Mirrors @neteaseapireborn/api/module/playlist_create.js.
        let response: PlaylistCreationResponse = try await client.weapi(
            "/api/playlist/create",
            data: ["name": name, "privacy": isPrivate ? "10" : "0", "type": "NORMAL"]
        )
        try validate(responseCode: response.code, message: response.message)
        guard let playlist = response.playlist, playlist.id > 0 else {
            throw APIError.invalidResponse
        }
        return playlist
    }
}

private struct PlaylistCreationResponse: Decodable {
    let code: Int
    let playlist: Playlist?
    let message: String?
}

private enum PlaylistTrackMutationError: LocalizedError {
    case gateway(operation: String)

    var errorDescription: String? {
        switch self {
        case .gateway(let operation):
            let action = operation == "add" ? "添加" : "移除"
            // A gateway failure can occur after the upstream accepted the write.
            // Never claim that it failed definitively or automatically duplicate it.
            return "网易云暂时无法确认歌曲是否已\(action)（502）。请先刷新歌单确认；若未生效，稍后重试。私密歌单也可先在网易云 App 中检查状态。"
        }
    }
}
