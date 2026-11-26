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
                guard sessionRevision == session, operation != .leaving,
                      let pending = pendingTransportReport else { return }
                await sendTransportReportWithRetry(pending, session: session)
                guard !Task.isCancelled, sessionRevision == session else { return }
                if pendingTransportReport?.clientSequence == pending.clientSequence {
                    pendingTransportReport = nil
                }
            } catch {
                return
            }
        }
    }

    private func sendTransportReportWithRetry(
        _ report: PendingListenTogetherTransportReport,
        session: Int
    ) async {
        // A timeout can hide a successful write. Retry with the same client sequence.
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
        case .server(let statusCode, _): return (500..<600).contains(statusCode)
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
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self,
                      self.sessionRevision == session,
                      self.operation != .leaving else { return }
                try await self.sendPlaylistSnapshot()
            } catch {
                guard !Task.isCancelled, let self,
                      self.sessionRevision == session else { return }
                self.connectionState = .reconnecting
            }
        }
    }

    func sendPlaylistSnapshot() async throws {
        guard let room,
              let localUserID else {
            throw ListenTogetherSessionError.missingAccount
        }
        let displaySongIDs = player.listenTogetherDisplaySongIDs
        guard !displaySongIDs.isEmpty else {
            throw ListenTogetherSessionError.noCurrentSong
        }
        let randomSongIDs = player.listenTogetherRandomSongIDs
        clientSequence += 1
        try await api.reportListenTogetherPlaylist(
            roomID: room.id,
            userID: localUserID,
            version: clientSequence,
            displaySongIDs: displaySongIDs,
            randomSongIDs: randomSongIDs.isEmpty
                ? displaySongIDs
                : randomSongIDs
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
        if !locallyReportedCommandSequences.contains(report.clientSequence) {
            locallyReportedCommandSequences.append(report.clientSequence)
            if locallyReportedCommandSequences.count > 16 {
                locallyReportedCommandSequences.removeFirst()
            }
        }
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
        guard let room,
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
              let sequence = Int(exactly: command.clientSequence) else { return false }
        return locallyReportedCommandSequences.contains(sequence)
    }
}
