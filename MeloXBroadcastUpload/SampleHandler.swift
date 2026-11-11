import CoreMedia
import Foundation
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    // ReplayKit serializes callbacks; the independent deadline timer also uses
    // this process-local lock. No buffers/tasks accumulate behind another queue.
    private let lock = NSLock()
    private var mailbox: BroadcastMailbox?
    private var session: BroadcastSession?
    private var timer: DispatchSourceTimer?
    private var resampler: BroadcastResampler?
    private var format: BroadcastPCMFormat?
    private var expectedPTS: Double?
    private var lastPublish = 0.0
    private var finished = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        var reason: BroadcastPhase?
        lock.withLock {
            timer?.cancel()
            timer = nil
            session = nil
            mailbox = nil
            finished = false
            lastPublish = 0
            resetConversion()
            do {
                guard let group = Bundle.main.object(forInfoDictionaryKey: "MeloXBroadcastAppGroup") as? String else {
                    throw BroadcastCoreError.unavailable
                }
                let mailbox = try BroadcastMailbox(container: FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: group))
                guard let request = try mailbox.currentRequest() else { throw BroadcastCoreError.invalidSession }
                let session = try BroadcastSession(request: request, now: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                                                   initialState: mailbox.state(request.id), control: mailbox.control(request.id))
                self.mailbox = mailbox
                self.session = session
                try publish()
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "MeloX.broadcast.deadline", qos: .utility))
                timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
                timer.setEventHandler { [weak self] in self?.tick() }
                self.timer = timer
                timer.resume()
            } catch {
                finished = true
                reason = .failed
            }
        }
        if let reason { endBroadcast(reason) }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // System UI calls this a screen broadcast. Video and microphone buffers
        // are deliberately ignored before any copying, storage or conversion.
        guard sampleBufferType == .audioApp, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        var reason: BroadcastPhase?
        lock.withLock {
            guard !finished, session?.phase == .capturing else { return }
            do {
                let (newFormat, mono) = try BroadcastSamplePCM.decode(sampleBuffer)
                let pts = sampleBuffer.presentationTimeStamp.seconds
                // Allow timestamp rounding, not a missing callback-sized gap.
                let gap = expectedPTS.map { !pts.isFinite || abs(pts - $0) > 0.002 } ?? false
                if format != newFormat || gap {
                    session?.resetWindow(uptime: ProcessInfo.processInfo.systemUptime)
                    resampler = BroadcastResampler(inputRate: newFormat.rate)
                    format = newFormat
                }
                expectedPTS = pts.isFinite ? pts + Double(sampleBuffer.numSamples) / newFormat.rate : nil
                let samples = resampler?.append(mono) ?? []
                session?.append(samples, uptime: ProcessInfo.processInfo.systemUptime)
            } catch {
                reason = fail(.formatError)
                return
            }
            do { reason = try updateAndPublish(checkControl: false) }
            catch { reason = fail(.failed) }
        }
        if let reason { endBroadcast(reason) }
    }

    override func broadcastPaused() {
        lock.withLock {
            guard !finished else { return }
            session?.pause()
            resetConversion()
            do { try publish() } catch { session?.fail(.failed) }
        }
    }

    override func broadcastResumed() {
        lock.withLock {
            guard !finished else { return }
            session?.resume(uptime: ProcessInfo.processInfo.systemUptime)
            resetConversion()
        }
        tick()
    }

    override func broadcastFinished() {
        lock.withLock {
            timer?.cancel()
            timer = nil
            guard !finished else { return }
            session?.userFinished()
            try? publish()
            finished = true
            resetConversion()
        }
    }

    private func tick() {
        var reason: BroadcastPhase?
        lock.withLock {
            guard !finished else { return }
            do { reason = try updateAndPublish() }
            catch { reason = fail(.failed) }
        }
        if let reason { endBroadcast(reason) }
    }

    private func updateAndPublish(checkControl: Bool = true) throws -> BroadcastPhase? {
        guard let mailbox, let id = session?.request.id else { throw BroadcastCoreError.invalidSession }
        let uptime = ProcessInfo.processInfo.systemUptime
        if checkControl {
            session?.tick(uptime: uptime, control: try mailbox.control(id), currentID: try mailbox.currentRequest()?.id)
        }
        if session?.phase.terminal == true {
            try publish()
            finished = true
            timer?.cancel()
            timer = nil
            return session?.phase
        }
        if uptime - lastPublish >= 1 { try publish() }
        return nil
    }

    private func publish() throws {
        if let session, let mailbox {
            try mailbox.publish(session.state())
            lastPublish = ProcessInfo.processInfo.systemUptime
        }
    }

    private func fail(_ phase: BroadcastPhase) -> BroadcastPhase {
        session?.fail(phase)
        try? publish()
        finished = true
        timer?.cancel()
        timer = nil
        return phase
    }

    private func resetConversion() { resampler = nil; format = nil; expectedPTS = nil }

    private func endBroadcast(_ phase: BroadcastPhase) {
        let key: String
        switch phase {
        case .completed: key = "broadcast.finished"
        case .cancelled: key = "broadcast.cancelled"
        case .noAudio, .silent: key = "broadcast.no_audio"
        case .formatError: key = "broadcast.format_error"
        default: key = "broadcast.unavailable"
        }
        // ReplayKit's public stop API requires an Error, also on normal completion.
        let reason = NSLocalizedString(key, bundle: .main, comment: "Broadcast completion reason")
        finishBroadcastWithError(NSError(domain: "MeloX.Broadcast", code: 1,
                                         userInfo: [NSLocalizedDescriptionKey: reason]))
    }

    deinit { timer?.cancel() }
}
