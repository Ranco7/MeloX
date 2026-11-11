import Foundation

/// At most eight probed mailboxes, one UUID, and one authoritative extension
/// acknowledgement. PCM is accepted only from that exact group/extension pair.
nonisolated struct BroadcastMailboxSet: Sendable {
    let environment: BroadcastRuntimeEnvironment
    private(set) var selectedGroup: String?

    init(environment: BroadcastRuntimeEnvironment) {
        self.environment = environment
        selectedGroup = nil
    }

    func binding(_ endpoint: BroadcastGroupEndpoint) -> BroadcastBinding {
        BroadcastBinding(extensionID: environment.extensionID, groupID: endpoint.candidate.identifier)
    }

    func prepare(duration: Int) throws -> BroadcastRequest {
        guard let first = environment.endpoints.first else { throw diagnostic(.noUsableGroup) }
        let request = BroadcastRequest(duration: duration, binding: binding(first))
        var prepared: [BroadcastGroupEndpoint] = []
        do {
            for endpoint in environment.endpoints {
                try endpoint.mailbox.prepare(request.bound(to: binding(endpoint)))
                prepared.append(endpoint)
            }
        } catch {
            for endpoint in prepared { try? endpoint.mailbox.send(.cancel, id: request.id, binding: binding(endpoint)) }
            throw diagnostic(.notWritable)
        }
        return request
    }

    mutating func state(_ request: BroadcastRequest, now: Date = Date()) throws -> BroadcastState {
        var acknowledged: [(BroadcastGroupEndpoint, BroadcastState)] = []
        var cancelledGroups = Set<String>()
        var matchingRequests = 0
        for endpoint in environment.endpoints {
            guard let current = try endpoint.mailbox.currentRequest() else { continue }
            if current.id != request.id {
                guard current.createdAt < request.createdAt else { throw diagnostic(.handshakeMismatch) }
                continue
            }
            matchingRequests += 1
            guard current.binding == binding(endpoint) else { throw diagnostic(.handshakeMismatch) }
            if let control = try endpoint.mailbox.control(request.id) {
                guard control.id == request.id, control.binding == binding(endpoint) else { throw diagnostic(.handshakeMismatch) }
                if control.command == .cancel { cancelledGroups.insert(endpoint.candidate.identifier) }
            }
            guard let state = try endpoint.mailbox.state(request.id), state.id == request.id,
                  state.binding == binding(endpoint) else { throw diagnostic(.handshakeMismatch) }
            if state.phase != .waiting && state.phase != .cancelled { acknowledged.append((endpoint, state)) }
        }
        guard matchingRequests > 0, acknowledged.count <= 1 else { throw diagnostic(.handshakeMismatch) }
        if let (endpoint, state) = acknowledged.first {
            if cancelledGroups.contains(endpoint.candidate.identifier) { throw CancellationError() }
            if let selectedGroup, selectedGroup != endpoint.candidate.identifier { throw diagnostic(.handshakeMismatch) }
            if selectedGroup == nil {
                selectedGroup = endpoint.candidate.identifier
                for unused in environment.endpoints where unused.candidate.identifier != selectedGroup {
                    if try unused.mailbox.currentRequest()?.id == request.id {
                        try unused.mailbox.send(.cancel, id: request.id, binding: binding(unused))
                    }
                }
            }
            return state
        }
        if !cancelledGroups.isEmpty { throw CancellationError() }
        guard selectedGroup == nil else { throw diagnostic(.handshakeMismatch) }
        guard request.permitsStart(at: now) else { throw diagnostic(.startNotConfirmed) }
        return BroadcastState(id: request.id, binding: request.binding, phase: .waiting, now: request.createdAt)
    }

    func recover(now: Date = Date()) throws -> BroadcastRequest? {
        // Consider the newest request before filtering terminal/handled states,
        // so an old group cannot resurrect audio after a newer session finishes.
        let requests = try environment.endpoints.compactMap { try $0.mailbox.currentRequest() }
        guard let latest = requests.max(by: {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }), (0..<600).contains(now.timeIntervalSince(latest.createdAt)) else { return nil }
        for endpoint in environment.endpoints {
            guard let request = try endpoint.mailbox.currentRequest(), request.id == latest.id else { continue }
            guard request.binding == binding(endpoint), let state = try endpoint.mailbox.state(request.id),
                  state.binding == request.binding else { throw diagnostic(.handshakeMismatch) }
            let control = try endpoint.mailbox.control(request.id)
            if let control, control.id != request.id || control.binding != request.binding { throw diagnostic(.handshakeMismatch) }
            guard state.phase != .waiting, state.phase != .cancelled,
                  state.phase != .completed || state.frameCount > 0,
                  control?.command != .cancel else { continue }
            return request
        }
        return nil
    }

    func send(_ command: BroadcastStop, request: BroadcastRequest) throws {
        var failure: BroadcastDiagnostic?
        for endpoint in environment.endpoints {
            do {
                guard let state = try endpoint.mailbox.state(request.id) else { continue }
                guard state.binding == binding(endpoint) else { throw diagnostic(.handshakeMismatch) }
                try endpoint.mailbox.send(command, id: request.id, binding: binding(endpoint))
            } catch let detail as BroadcastDiagnostic { failure = detail }
            catch { failure = failure ?? diagnostic(.notWritable) }
        }
        if let failure { throw failure }
    }

    func clearAudio(_ request: BroadcastRequest) throws {
        for endpoint in environment.endpoints { try endpoint.mailbox.clearAudio(request.id) }
    }

    func diagnostic(_ code: BroadcastDiagnosticCode) -> BroadcastDiagnostic {
        BroadcastDiagnostic(code: code, candidateCount: environment.diagnostic.candidateCount,
                            usableCount: environment.diagnostic.usableCount, profileIssue: environment.diagnostic.profileIssue)
    }

    /// Unused groups may contain foreign or undecodable old headers. They
    /// cannot nominate a request, but any evidence for the selected UUID still
    /// participates in the consumed/cancelled/mismatched-session checks.
    func requestForExtension(now: Date = Date()) throws -> (BroadcastGroupEndpoint, BroadcastRequest) {
        var headers: [(BroadcastGroupEndpoint, BroadcastRequest)] = []
        for endpoint in environment.endpoints {
            do {
                if let request = try endpoint.mailbox.currentRequest() { headers.append((endpoint, request)) }
            } catch {
                // This endpoint is ineligible for selection. Its selected-UUID
                // state/control, if present, is checked below instead of ignored.
                continue
            }
        }
        let matching = headers.filter { $0.1.binding == binding($0.0) }
        guard let newest = matching.max(by: {
            if $0.1.createdAt != $1.1.createdAt { return $0.1.createdAt < $1.1.createdAt }
            return $0.1.id.uuidString < $1.1.id.uuidString
        })?.1, newest.permitsStart(at: now) else { throw diagnostic(.startNotPrepared) }

        for endpoint in environment.endpoints {
            let header = headers.first { $0.0.candidate.identifier == endpoint.candidate.identifier }?.1
            let belongsToSession = header?.id == newest.id
            if belongsToSession, header != newest.bound(to: binding(endpoint)) {
                throw diagnostic(.handshakeMismatch)
            }
            let state = try endpoint.mailbox.state(newest.id)
            if let state {
                guard state.binding == binding(endpoint) else { throw diagnostic(.handshakeMismatch) }
                guard state.phase == .waiting else { throw diagnostic(.startNotPrepared) }
            } else if belongsToSession { throw diagnostic(.startNotPrepared) }
            if let control = try endpoint.mailbox.control(newest.id), control.id == newest.id {
                guard control.binding == binding(endpoint) else { throw diagnostic(.handshakeMismatch) }
                throw diagnostic(.startNotPrepared)
            }
        }
        guard let chosen = matching.first(where: { $0.1.id == newest.id }) else { throw diagnostic(.startNotPrepared) }
        return chosen
    }
}
