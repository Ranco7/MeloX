import Foundation

extension ListenTogetherStore {
    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            await self?.monitorSession()
        }
    }

    private func monitorSession() async {
        var tick = 0
        var consecutivePollFailures = 0
        while !Task.isCancelled, isInRoom {
            tick += 1
            let succeeded = await pollServer(
                includesRoomStatus: tick == 1
                    || tick.isMultiple(of: 5)
                    || (!player.listenTogetherReportedPlaying
                        && tick.isMultiple(of: 2))
            )
            guard !Task.isCancelled, isInRoom else { return }
            let delay: Duration
            if succeeded {
                consecutivePollFailures = 0
                delay = player.listenTogetherReportedPlaying
                    ? .seconds(1)
                    : .seconds(5)
            } else {
                consecutivePollFailures += 1
                delay = .seconds(1 << min(consecutivePollFailures, 3))
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    private func pollServer(
        includesRoomStatus: Bool
    ) async -> Bool {
        let session = sessionRevision
        do {
            try await synchronizeFromServer(initial: false)
            guard isInRoom, sessionRevision == session else { return false }

            if includesRoomStatus {
                try await refreshRoomStatus()
                guard isInRoom, sessionRevision == session else { return false }
                try await sendHeartbeat()
            }

            guard sessionRevision == session else { return false }
            consecutiveSyncFailures = 0
            connectionState = .connected
            lastSyncDate = .now
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled, sessionRevision == session else {
                return false
            }
            consecutiveSyncFailures += 1
            if consecutiveSyncFailures >= 2 {
                connectionState = .reconnecting
            }
            return false
        }
    }

    func refreshRoomStatus() async throws {
        guard let expectedRoom = room, operation != .leaving else { return }
        let session = sessionRevision
        let status = try await api.listenTogetherRoomStatus()
        try Task.checkCancellation()
        guard sessionRevision == session, operation != .leaving else { return }
        guard status.isInRoom else {
            clearSession(notice: L10n.string("ui.listen_together.notice.room_ended"))
            return
        }
        guard let updatedRoom = status.roomInfo else { return }
        // A status payload without a room ID is incomplete, not a room change.
        if !updatedRoom.id.isEmpty, updatedRoom.id != expectedRoom.id {
            clearSession(notice: L10n.string("ui.listen_together.notice.account_moved"))
            return
        }
        let resolvedRoom = updatedRoom.id.isEmpty ? expectedRoom : updatedRoom
        room = resolvedRoom
        if let localUserID {
            isHost = resolvedRoom.creatorID == String(localUserID)
        }
    }

    func synchronizeFromServer(initial: Bool) async throws {
        guard let room, operation != .leaving else { return }
        let session = sessionRevision
        guard synchronizingSession != session, transportReportTask == nil,
              queueReportTask == nil else { return }
        synchronizingSession = session
        defer {
            if synchronizingSession == session {
                synchronizingSession = nil
            }
        }
        let revision = localChangeRevision
        let payload = try await api.listenTogetherPlayback(roomID: room.id)
        try Task.checkCancellation()
        guard sessionRevision == session, localChangeRevision == revision,
              operation != .leaving else { return }
        let commandObservedAt = Date()

        let playlistSignature = signature(for: payload.playlist)
        let commandSignature = signature(for: payload.playCommand)
        let playlistChanged = playlistSignature != lastPlaylistSignature
        let commandChanged = commandSignature != lastCommandSignature
        guard initial || playlistChanged || commandChanged else { return }

        let command = payload.playCommand
        let appliesTransport = initial || (
            commandChanged && command != nil && !commandOriginatedLocally(command)
        )
        if !appliesTransport, !playlistChanged {
            lastCommandSignature = commandSignature
            return
        }
        if let command, let commandSignature {
            if observedPlayCommand?.signature != commandSignature {
                observedPlayCommand = ListenTogetherObservedPlayCommand(
                    signature: commandSignature,
                    isPlaying: command.shouldPlay ?? false,
                    observedAt: commandObservedAt
                )
            }
        } else {
            observedPlayCommand = nil
        }

        var songIDs = payload.playlist?.playbackSongIDs ?? []
        if songIDs.isEmpty {
            songIDs = player.queue.map(\.id)
        }
        let targetSongID = (appliesTransport ? command?.targetSongNumericID : nil)
            ?? player.currentSong?.id ?? songIDs.first
        guard let targetSongID else {
            lastPlaylistSignature = playlistSignature
            lastCommandSignature = commandSignature
            return
        }
        // Only a transport command may reintroduce its target into the room
        // playlist. A playlist-only update must not re-add a deleted song.
        if appliesTransport, !songIDs.contains(targetSongID) {
            songIDs.append(targetSongID)
        }

        let songs: [Song]
        if songIDs == player.queue.map(\.id),
           unresolvedSongIDs.isEmpty || !playlistChanged {
            songs = player.queue
        } else {
            songs = try await loadSongsPreservingOrder(ids: songIDs)
        }
        try Task.checkCancellation()
        guard sessionRevision == session, localChangeRevision == revision,
              operation != .leaving else { return }

        if appliesTransport {
            let transportTargetSongID: Int
            if songs.contains(where: { $0.id == targetSongID }),
               !unresolvedSongIDs.contains(targetSongID) {
                transportTargetSongID = targetSongID
            } else if let fallback = songs.first(where: {
                !unresolvedSongIDs.contains($0.id)
            }) {
                // The room is playing a song this device cannot resolve; keep
                // following the room instead of retrying it every poll.
                transportTargetSongID = fallback.id
            } else {
                lastPlaylistSignature = playlistSignature
                lastCommandSignature = commandSignature
                return
            }
            let usesFallbackTarget = transportTargetSongID != targetSongID

            let shouldPlay = command?.shouldPlay
                ?? player.listenTogetherReportedPlaying
            let progress: TimeInterval
            if usesFallbackTarget {
                // The command position belongs to a different song.
                progress = 0
            } else if let command {
                let reportedProgress =
                    TimeInterval(command.progressMilliseconds) / 1_000
                if let commandSignature,
                   let observed = observedPlayCommand,
                   observed.signature == commandSignature,
                   observed.isPlaying {
                    progress = reportedProgress + max(
                        0,
                        Date().timeIntervalSince(observed.observedAt)
                    )
                } else {
                    progress = reportedProgress
                }
            } else {
                progress = player.estimatedProgress()
            }
            await player.synchronizeListenTogetherPlayback(
                songs: songs,
                targetSongID: transportTargetSongID,
                progress: progress,
                isPlaying: shouldPlay,
                adoptsRoomPlayMode: initial || playlistChanged,
                playMode: payload.playlist?.playMode
            )
        } else if let currentSong = player.currentSong,
                  !songs.contains(where: { $0.id == currentSong.id }),
                  let alignmentTarget = songs.first(where: {
                      !unresolvedSongIDs.contains($0.id)
                  }) {
            // The room removed the song this device is playing. Align the
            // queue and pause instead of keeping a song the room no longer has
            // and republishing it on the next local queue edit.
            await player.synchronizeListenTogetherPlayback(
                songs: songs,
                targetSongID: alignmentTarget.id,
                progress: 0,
                isPlaying: false,
                adoptsRoomPlayMode: true,
                playMode: payload.playlist?.playMode
            )
        } else {
            player.synchronizeListenTogetherQueue(
                songs: songs,
                playMode: payload.playlist?.playMode
            )
        }
        guard sessionRevision == session, operation != .leaving else { return }
        lastPlaylistSignature = playlistSignature
        lastCommandSignature = commandSignature
    }

    private func loadSongsPreservingOrder(
        ids: [Int]
    ) async throws -> [Song] {
        var loadedByID: [Int: Song] = [:]
        for song in player.queue where !unresolvedSongIDs.contains(song.id) {
            loadedByID[song.id] = song
        }
        let missingIDs = ids.filter { loadedByID[$0] == nil }
        var start = 0
        while start < missingIDs.count {
            try Task.checkCancellation()
            let end = min(start + 100, missingIDs.count)
            let page = try await api.songDetails(
                ids: Array(missingIDs[start..<end])
            )
            for song in page {
                loadedByID[song.id] = song
            }
            start = end
        }
        // Keep unresolvable songs as placeholders. Dropping them would replace
        // the room playlist with a truncated queue, and the next local queue
        // edit would publish that truncation to every member.
        var unresolved: Set<Int> = []
        for id in ids where loadedByID[id] == nil {
            unresolved.insert(id)
            loadedByID[id] = Song(
                id: id,
                name: L10n.string("ui.metadata.unknown_song"),
                artists: []
            )
        }
        unresolvedSongIDs.subtract(ids)
        unresolvedSongIDs.formUnion(unresolved)
        return ids.compactMap { loadedByID[$0] }
    }

    private func signature(
        for playlist: ListenTogetherPlaylistSnapshot?
    ) -> String? {
        guard let playlist else { return nil }
        let ids = playlist.playbackSongIDs.map(String.init).joined(
            separator: ","
        )
        let versions = playlist.versions.map {
            "\($0.userID):\($0.version)"
        }.joined(separator: ",")
        return "\(playlist.playMode ?? "")|\(ids)|\(versions)"
    }

    private func signature(
        for command: ListenTogetherPlayCommand?
    ) -> String? {
        guard let command else { return nil }
        return [
            String(command.serverSequence),
            String(command.clientSequence),
            command.userID ?? "",
            command.commandType ?? "",
            command.targetSongID ?? "",
            String(command.progressMilliseconds),
            command.playStatus ?? "",
        ].joined(separator: "|")
    }
}
