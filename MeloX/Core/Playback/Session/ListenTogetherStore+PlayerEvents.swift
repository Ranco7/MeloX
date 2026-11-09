import Foundation

struct PendingListenTogetherTransportReport {
    let type: ListenTogetherCommandType
    let formerSongID: Int?
    let targetSongID: Int
    let isPlaying: Bool
    let progressMilliseconds: Int64
}

extension ListenTogetherStore {
    func playerTransportDidChange(
        type: ListenTogetherCommandType,
        formerSongID: Int?
    ) {
        guard isInRoom, operation != .leaving,
              let targetSongID = player.currentSong?.id else { return }
        localChangeRevision += 1
        let pending = pendingTransportReport
        let preservesTrackChange = pending?.type == .goTo
            && pending?.targetSongID == targetSongID
        let isPlaying: Bool
        switch type {
        case .play: isPlaying = true
        case .pause: isPlaying = false
        default: isPlaying = player.listenTogetherReportedPlaying
        }
        pendingTransportReport = PendingListenTogetherTransportReport(
            type: preservesTrackChange ? .goTo : type,
            formerSongID: preservesTrackChange ? pending?.formerSongID : formerSongID,
            targetSongID: targetSongID,
            isPlaying: isPlaying,
            progressMilliseconds: Int64((player.estimatedProgress() * 1_000).rounded())
        )
        guard transportReportTask == nil else { return }
        let session = sessionRevision
        transportReportTask = Task { @MainActor [weak self] in
            await self?.sendPendingTransportReports(session: session)
        }
    }

    private func sendPendingTransportReports(session: Int) async {
        defer {
            if sessionRevision == session {
                transportReportTask = nil
            }
        }
        // Merge nearby actions before sending. Once sent, finish that request
        // before starting the next one so it cannot overtake the newer action.
        var retryDelayMilliseconds = 1_000
        while !Task.isCancelled, sessionRevision == session {
            guard operation != .leaving,
                  let pending = pendingTransportReport else { return }
            var failedReport = pending
            do {
                try await Task.sleep(for: .milliseconds(40))
                guard sessionRevision == session, operation != .leaving,
                      let report = pendingTransportReport else { return }
                failedReport = report
                pendingTransportReport = nil
                try await sendCommand(
                    type: report.type,
                    formerSongID: report.formerSongID,
                    targetSongID: report.targetSongID,
                    isPlaying: report.isPlaying,
                    progressMilliseconds: report.progressMilliseconds
                )
                retryDelayMilliseconds = 1_000
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, sessionRevision == session else { return }
                // Keep the failed action unless a newer one is already queued;
                // otherwise the room would never learn about this pause/seek.
                if pendingTransportReport == nil {
                    pendingTransportReport = failedReport
                }
                connectionState = .reconnecting
                do {
                    try await Task.sleep(
                        for: .milliseconds(retryDelayMilliseconds)
                    )
                } catch {
                    return
                }
                retryDelayMilliseconds = min(
                    retryDelayMilliseconds * 2,
                    8_000
                )
            }
        }
    }

    func playerQueueDidChange() {
        guard isInRoom, operation != .leaving else { return }
        localChangeRevision += 1
        queueReportTask?.cancel()
        queueReportRevision += 1
        let session = sessionRevision
        let revision = queueReportRevision
        queueReportTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.sessionRevision == session,
                   self.queueReportRevision == revision {
                    self.queueReportTask = nil
                }
            }
            var retryDelayMilliseconds = 1_000
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, let self,
                          self.sessionRevision == session,
                          self.queueReportRevision == revision,
                          self.operation != .leaving else { return }
                    try await self.sendPlaylistSnapshot()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, let self,
                          self.sessionRevision == session,
                          self.queueReportRevision == revision else { return }
                    self.connectionState = .reconnecting
                    do {
                        try await Task.sleep(
                            for: .milliseconds(retryDelayMilliseconds)
                        )
                    } catch {
                        return
                    }
                    retryDelayMilliseconds = min(
                        retryDelayMilliseconds * 2,
                        8_000
                    )
                }
            }
        }
    }

    func sendPlaylistSnapshot() async throws {
        guard let room,
              let localUserID else {
            throw ListenTogetherSessionError.missingAccount
        }
        let displaySongIDs = player.listenTogetherDisplaySongIDs
        // An empty queue is a normal state, not a connection failure.
        guard !displaySongIDs.isEmpty else { return }
        let publishedSongIDs = player.listenTogetherPublishedSongIDs
        clientSequence += 1
        try await api.reportListenTogetherPlaylist(
            roomID: room.id,
            userID: localUserID,
            version: clientSequence,
            displaySongIDs: displaySongIDs,
            randomSongIDs: publishedSongIDs.isEmpty
                ? displaySongIDs
                : publishedSongIDs
        )
    }

    func sendCurrentPlaybackCommand(
        type: ListenTogetherCommandType
    ) async throws {
        guard let songID = player.currentSong?.id else {
            throw ListenTogetherSessionError.noCurrentSong
        }
        try await sendCommand(
            type: type,
            formerSongID: songID,
            targetSongID: songID
        )
    }

    private func sendCommand(
        type: ListenTogetherCommandType,
        formerSongID: Int?,
        targetSongID: Int,
        isPlaying: Bool? = nil,
        progressMilliseconds: Int64? = nil
    ) async throws {
        guard let room else { return }
        clientSequence += 1
        // Record the sequence before the request so an echo cannot be applied
        // as a remote command if the response is lost.
        lastLocallyReportedCommandSequence = Int64(clientSequence)
        try await api.reportListenTogetherCommand(
            roomID: room.id,
            commandType: type,
            progressMilliseconds: progressMilliseconds ?? Int64(
                (player.estimatedProgress() * 1_000).rounded()
            ),
            isPlaying: isPlaying ?? player.listenTogetherReportedPlaying,
            formerSongID: formerSongID,
            targetSongID: targetSongID,
            clientSequence: clientSequence
        )
    }

    func sendHeartbeat() async throws {
        guard operation != .leaving,
              let room,
              let songID = player.currentSong?.id else {
            return
        }
        try await api.sendListenTogetherHeartbeat(
            roomID: room.id,
            songID: songID,
            isPlaying: player.listenTogetherReportedPlaying,
            progressMilliseconds: Int64(
                (player.estimatedProgress() * 1_000).rounded()
            )
        )
    }

    func commandOriginatedLocally(_ command: ListenTogetherPlayCommand?) -> Bool {
        guard let command,
              let localUserID,
              command.userID == String(localUserID),
              command.clientSequence > 0 else { return false }
        return command.clientSequence <= lastLocallyReportedCommandSequence
    }
}
