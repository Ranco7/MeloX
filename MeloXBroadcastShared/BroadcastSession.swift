import Foundation

nonisolated struct BroadcastRequest: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let startBefore: Date
    let duration: Int

    init(duration: Int, now: Date = Date()) {
        id = UUID()
        createdAt = now
        startBefore = now.addingTimeInterval(60)
        self.duration = max(3, min(9, duration))
    }

    func permitsStart(at now: Date) -> Bool {
        (3...9).contains(duration) && now >= createdAt && now < startBefore
    }
}

nonisolated enum BroadcastPhase: String, Codable, Sendable {
    case waiting, capturing, paused, completed, cancelled, noAudio, silent, formatError, failed
    var terminal: Bool { self != .waiting && self != .capturing && self != .paused }
}

nonisolated enum BroadcastStop: String, Codable, Sendable { case cancel, complete, matched }
nonisolated struct BroadcastControl: Codable, Sendable {
    let id: UUID
    let command: BroadcastStop
}

nonisolated struct BroadcastState: Codable, Sendable {
    let id: UUID
    var phase: BroadcastPhase
    var heartbeat: Date
    var frameCount: Int
    /// Fixed little-endian float32. Metadata and PCM are one atomic envelope.
    var pcm: Data

    init(id: UUID, phase: BroadcastPhase, now: Date = Date(), samples: [Float] = []) {
        self.id = id
        self.phase = phase
        heartbeat = now
        frameCount = samples.count
        pcm = Data(capacity: samples.count * 4)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { pcm.append(contentsOf: $0) }
        }
    }

    func samples() throws -> [Float] {
        guard (0...9 * BroadcastResampler.rate).contains(frameCount), pcm.count == frameCount * 4 else {
            throw BroadcastCoreError.invalidPCM
        }
        return stride(from: 0, to: pcm.count, by: 4).map { offset in
            let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(pcm[offset + $1]) << ($1 * 8) }
            return Float(bitPattern: bits)
        }
    }
}

/// Pure session policy, tested without ReplayKit or an App Group entitlement.
nonisolated struct BroadcastSession {
    let request: BroadcastRequest
    let startedAt: TimeInterval
    private(set) var phase: BroadcastPhase = .capturing
    private(set) var ring = BroadcastRing(capacity: 9 * BroadcastResampler.rate)
    private var windowStartedAt: TimeInterval
    private var lastAudioAt: TimeInterval?
    private var receivedAudio = false

    init(request: BroadcastRequest, now: Date, uptime: TimeInterval,
         initialState: BroadcastState?, control: BroadcastControl?) throws {
        guard request.permitsStart(at: now), initialState?.id == request.id,
              initialState?.phase == .waiting, control?.id != request.id else {
            throw BroadcastCoreError.invalidSession
        }
        self.request = request
        startedAt = uptime
        windowStartedAt = uptime
    }

    mutating func append(_ samples: [Float], uptime: TimeInterval) {
        guard phase == .capturing, !samples.isEmpty else { return }
        lastAudioAt = uptime
        receivedAudio = true
        if ring.count == 0, !samples.contains(where: { abs($0) > 0.0001 }) { return }
        ring.append(Array(samples.prefix(max(0, request.duration * BroadcastResampler.rate - ring.count))))
        if ring.count >= request.duration * BroadcastResampler.rate { finish() }
    }

    mutating func tick(uptime: TimeInterval, control: BroadcastControl?, currentID: UUID?) {
        guard !phase.terminal else { return }
        if currentID != request.id { phase = .cancelled; return }
        if let control, control.id == request.id {
            if control.command == .cancel { phase = .cancelled }
            else { finish() }
        } else if uptime - startedAt >= Double(request.duration + 15) {
            finish()
        } else if phase == .capturing,
                  (ring.count == 0 && uptime - windowStartedAt >= 12) || uptime - (lastAudioAt ?? startedAt) >= 12 {
            finish()
        }
    }

    mutating func pause() {
        guard !phase.terminal else { return }
        phase = .paused
        ring = BroadcastRing(capacity: 9 * BroadcastResampler.rate)
    }

    mutating func resume(uptime: TimeInterval) {
        guard phase == .paused else { return }
        phase = .capturing
        resetWindow(uptime: uptime)
    }

    mutating func resetWindow(uptime: TimeInterval) {
        ring = BroadcastRing(capacity: 9 * BroadcastResampler.rate)
        windowStartedAt = uptime
        lastAudioAt = uptime
    }
    mutating func fail(_ failure: BroadcastPhase) { if !phase.terminal { phase = failure } }
    mutating func userFinished() { if !phase.terminal { finish() } }

    private mutating func finish() {
        phase = ring.count < BroadcastResampler.rate ? (receivedAudio ? .silent : .noAudio) : (ring.hasSound ? .completed : .silent)
    }

    func state(now: Date = Date()) -> BroadcastState {
        BroadcastState(id: request.id, phase: phase, now: now,
                       samples: phase == .cancelled || phase == .formatError || phase == .failed ? [] : ring.samples)
    }
}
