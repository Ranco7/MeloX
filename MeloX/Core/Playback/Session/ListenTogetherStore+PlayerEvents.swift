import Foundation

struct PendingListenTogetherTransportReport {
    let clientSequence: Int
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
        pendingTransportReport = makeTransportReport(
            type: preservesTrackChange ? .goTo : type,
            formerSongID: preservesTrackChange ? pending?.formerSongID : formerSongID,
            targetSongID: targetSongID,
            isPlaying: isPlaying
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
        while !Task.isCancelled, sessionRevision == session,
              pendingTransportReport != nil {
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                return
            }
            guard sessionRevision == session, operation != .leaving,
                  let report = pendingTransportReport else { return }
            await sendTransportReportWithRetry(report, session: session)
            guard !Task.isCancelled, sessionRevision == session else { return }
            if pendingTransportReport?.clientSequence == report.clientSequence {
                pendingTransportReport = nil
            }
        }
    }

    private func sendTransportReportWithRetry(
        _ report: PendingListenTogetherTransportReport,
        session: Int
    ) async {
        // Reuse the sequence if the request went through but its reply was lost.
        // Limit retries so a local failure cannot stop remote playback indefinitely.
        let retryDelays = [0, 250, 1_000]
        for (attempt, delay) in retryDelays.enumerated() {
            do {
                if delay > 0 {
                    try await Task.sleep(for: .milliseconds(delay))
                }
                guard sessionRevision == session, operation != .leaving,
                      pendingTransportReport?.clientSequence == report.clientSequence,
                      let room else { return }
                try await sendCommand(report, roomID: room.id)
                return
            } catch {
                guard !Task.isCancelled, sessionRevision == session,
                      pendingTransportReport?.clientSequence == report.clientSequence else { return }
                connectionState = .reconnecting
                guard attempt + 1 < retryDelays.count,
                      Self.isRetryableTransportReportError(error) else { return }
            }
        }
    }

    private static func isRetryableTransportReportError(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return error.code != .cancelled
        }
        switch error as? APIError {
        case .emptyResponse: return true
        case .server(let code, _):
            // The API also uses this error for a successful HTTP response
            // with a missing action acknowledgement.
            return (200..<300).contains(code) || (500..<600).contains(code)
        default: return false
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
        guard let room else { return }
        let report = makeTransportReport(
            type: type,
            formerSongID: songID,
            targetSongID: songID,
            isPlaying: player.listenTogetherReportedPlaying
        )
        try await sendCommand(report, roomID: room.id)
    }

    private func makeTransportReport(
        type: ListenTogetherCommandType,
        formerSongID: Int?,
        targetSongID: Int,
        isPlaying: Bool
    ) -> PendingListenTogetherTransportReport {
        clientSequence += 1
        return PendingListenTogetherTransportReport(
            clientSequence: clientSequence,
            type: type,
            formerSongID: formerSongID,
            targetSongID: targetSongID,
            isPlaying: isPlaying,
            progressMilliseconds: Int64((player.estimatedProgress() * 1_000).rounded())
        )
    }

    private func sendCommand(
        _ report: PendingListenTogetherTransportReport,
        roomID: String
    ) async throws {
        // Record the sequence before the request so an echo cannot be applied
        // as a remote command if the response is lost.
        lastLocallyReportedCommandSequence = max(
            lastLocallyReportedCommandSequence, Int64(report.clientSequence)
        )
        try await api.reportListenTogetherCommand(
            roomID: roomID,
            commandType: report.type,
            progressMilliseconds: report.progressMilliseconds,
            isPlaying: report.isPlaying,
            formerSongID: report.formerSongID,
            targetSongID: report.targetSongID,
            clientSequence: report.clientSequence
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
