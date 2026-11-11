// Synthetic XML envelopes and sandbox-free group directories only. No real
// profiles, certificate/device data, signatures, capture devices or network.
import Foundation

@main
struct BroadcastRuntimeChecks {
    static let actualID = "example.rewritten.AudioUpload"
    static let common = "TEAMTEST.group.shared"

    static func main() throws {
        try profiles()
        try discovery()
        try resolution()
        try handshake()
        try unusedEndpointIsolation()
    }

    static func envelope(_ groups: [String]) throws -> Data {
        try envelopeRoot(["Entitlements": ["com.apple.security.application-groups": groups]])
    }

    static func envelopeRoot(_ root: [String: Any]) throws -> Data {
        let xml = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        return Data([0x30, 0x82, 0, 0]) + xml + Data([0, 0, 0])
    }

    static func expect(_ code: BroadcastDiagnosticCode, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected safe diagnostic \(code)") }
        catch let diagnostic as BroadcastDiagnostic { precondition(diagnostic.code == code) }
        catch { fatalError("Unexpected error type") }
    }

    static func profiles() throws {
        let parsed = BroadcastProfileGroups.parse(try envelope([common, "group.synthetic.other", common]))
        precondition(parsed.status == .available && parsed.groups == [common, "group.synthetic.other"].sorted())
        precondition(BroadcastProfileGroups.parse(nil).status == .absent)
        precondition(BroadcastProfileGroups.parse(Data([0, 1])).status == .noXML)
        precondition(BroadcastProfileGroups.parse(Data("<?xml truncated".utf8)).status == .noXML)
        precondition(BroadcastProfileGroups.parse(Data(repeating: 0, count: BroadcastProfileGroups.maximumBytes + 1)).status == .oversized)
        precondition(BroadcastProfileGroups.parse(Data("<?xml version=\"1.0\"?><plist><dict>broken</plist>".utf8)).status == .malformed)
        let missing = BroadcastProfileGroups.parse(try envelopeRoot(["Synthetic": true]))
        precondition(missing.status == .missingEntitlements)
        let unsafe = BroadcastProfileGroups.parse(try envelope(["group.*", "../group.bad", "group.a/b", "group..bad", "group.a\\b", "group.with space", "", common]))
        precondition(unsafe.groups == [common])
        let noGroups = BroadcastProfileGroups.parse(try envelopeRoot(["Entitlements": [:] as [String: Any]]))
        precondition(noGroups.status == .available && noGroups.groups.isEmpty)
        print("PASS: bounded synthetic CMS XML extraction, absent/truncated/oversized/malformed profiles, missing entitlements and unsafe groups")
    }

    static func descriptor(id: String? = actualID, point: String = "com.apple.broadcast-services-upload",
                           mode: String = "RPBroadcastProcessModeSampleBuffer", executable: Bool = true,
                           marker: Int? = 1) -> BroadcastExtensionDescriptor {
        BroadcastExtensionDescriptor(url: URL(fileURLWithPath: "/synthetic/MeloX.app/PlugIns/Renamed.appex"),
            identifier: id, marker: marker, point: point, mode: mode,
            principal: "MeloXBroadcastUpload.SampleHandler", hasExecutable: executable,
            configuredGroup: "group.stale.build")
    }

    static func discovery() throws {
        let chosen = try BroadcastRuntime.chooseExtension([descriptor(marker: nil), descriptor()])
        precondition(chosen.identifier == actualID, "Use actual rewritten ID, not an Info cache or folder name")
        expect(.missingExtension) { _ = try BroadcastRuntime.chooseExtension([descriptor(marker: nil)]) }
        expect(.ambiguousExtension) { _ = try BroadcastRuntime.chooseExtension([descriptor(), descriptor(id: "example.second.Upload")]) }
        expect(.invalidExtensionID) { _ = try BroadcastRuntime.chooseExtension([descriptor(id: nil)]) }
        expect(.invalidExtensionID) { _ = try BroadcastRuntime.chooseExtension([descriptor(id: "bad/*")]) }
        expect(.invalidExtension) { _ = try BroadcastRuntime.chooseExtension([descriptor(point: "com.apple.widgetkit-extension")]) }
        expect(.invalidExtension) { _ = try BroadcastRuntime.chooseExtension([descriptor(mode: "wrong")]) }
        expect(.missingExecutable) { _ = try BroadcastRuntime.chooseExtension([descriptor(executable: false)]) }
        print("PASS: actual remapped extension ID, unique marker/point/mode validation, missing/ambiguous/invalid/binary diagnostics")
    }

    static func directory() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".resign-checks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func resolution() throws {
        let host = BroadcastProfileGroups.parse(try envelope(["group.host.only", common, "group.shared.second"]))
        let upload = BroadcastProfileGroups.parse(try envelope(["group.shared.second", common]))
        let reordered = BroadcastProfileGroups.parse(try envelope([common, "group.shared.second"]))
        let candidates = BroadcastRuntime.candidates(host: host, upload: upload, configured: ["group.configured"])
        precondition(candidates == BroadcastRuntime.candidates(host: host, upload: reordered, configured: ["group.configured"]))
        precondition(!candidates.contains { $0.identifier == "group.host.only" })
        precondition(candidates.first?.origin == .commonProfile)
        let disjoint = BroadcastProfileGroups.parse(try envelope(["group.extension.only"]))
        let noCommon = BroadcastRuntime.candidates(host: host, upload: disjoint, configured: ["group.configured"])
        precondition(noCommon.allSatisfy { $0.origin != .commonProfile && $0.origin != .singleProfile })
        let absent = BroadcastProfileGroups.parse(nil)
        let fallback = BroadcastRuntime.candidates(host: absent, upload: absent, configured: ["group.configured"])
        precondition(fallback.map(\.identifier) == ["group.configured", BroadcastRuntime.establishedGroup])
        let known = BroadcastProfileGroups.parse(try envelope([common, BroadcastRuntime.establishedGroup]))
        precondition(BroadcastRuntime.candidates(host: known, upload: known, configured: []).first?.identifier == BroadcastRuntime.establishedGroup)
        let many = BroadcastProfileGroups.parse(try envelope((0..<32).map { "group.synthetic.g\($0)" }))
        let bounded = BroadcastRuntime.candidates(host: many, upload: many, configured: ["group.configured"])
        precondition(bounded.count == 8 && bounded.contains { $0.identifier == BroadcastRuntime.establishedGroup })
        expect(.noUsableGroup) { _ = try BroadcastRuntime.probe(candidates, profileIssue: false) { _ in nil } }
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        precondition(BroadcastProfileGroups.read(bundleURL: root).status == .absent)
        let syntheticProfile = root.appendingPathComponent("embedded.mobileprovision")
        try envelope([common]).write(to: syntheticProfile)
        precondition(BroadcastProfileGroups.read(bundleURL: root).groups == [common])
        try Data(repeating: 0, count: BroadcastProfileGroups.maximumBytes + 1).write(to: syntheticProfile)
        precondition(BroadcastProfileGroups.read(bundleURL: root).status == .oversized)
        let file = root.appendingPathComponent("not-a-directory")
        try Data([0]).write(to: file)
        expect(.notWritable) { _ = try BroadcastRuntime.probe(fallback, profileIssue: true) { _ in file } }
        let usable = try BroadcastRuntime.probe(fallback, profileIssue: true) { group in
            group == BroadcastRuntime.establishedGroup ? root : nil
        }
        precondition(usable.count == 1 && usable[0].candidate.identifier == BroadcastRuntime.establishedGroup)
        let leftovers = try FileManager.default.contentsOfDirectory(at: usable[0].mailbox.root, includingPropertiesForKeys: nil)
        precondition(!leftovers.contains { $0.lastPathComponent.hasPrefix("probe-") })
        print("PASS: deterministic profile intersection/order, configured/established fallback, candidate cap, nil/unwritable containers and unique probe cleanup")
    }

    static func handshake() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let candidates = [BroadcastGroupCandidate(identifier: "group.host.only", origin: .commonProfile),
                          BroadcastGroupCandidate(identifier: common, origin: .commonProfile)]
        let endpoints = try BroadcastRuntime.probe(candidates, profileIssue: false) { group in root.appendingPathComponent(group) }
        let environment = BroadcastRuntimeEnvironment(extensionID: actualID, endpoints: endpoints,
            diagnostic: BroadcastDiagnostic(code: .startNotConfirmed, candidateCount: 2, usableCount: 2))
        var host = BroadcastMailboxSet(environment: environment)
        let request = try host.prepare(duration: 3)
        let uploadEnvironment = BroadcastRuntimeEnvironment(extensionID: actualID, endpoints: [endpoints[1]], diagnostic: environment.diagnostic)
        let (selected, uploadRequest) = try BroadcastMailboxSet(environment: uploadEnvironment).requestForExtension()
        precondition(uploadRequest.id == request.id && uploadRequest.binding.groupID == common && uploadRequest.binding.extensionID == actualID)
        try selected.mailbox.publish(BroadcastState(id: uploadRequest.id, binding: uploadRequest.binding, phase: .capturing))
        let ack = try host.state(request)
        precondition(ack.binding == uploadRequest.binding && host.selectedGroup == common)
        expect(.startNotPrepared) { _ = try BroadcastMailboxSet(environment: uploadEnvironment).requestForExtension() }
        try selected.mailbox.publish(BroadcastState(id: request.id, binding: uploadRequest.binding, phase: .completed,
            samples: Array(repeating: 0.5, count: 24_000)))
        let final = try host.state(request)
        let finalSamples = try final.samples()
        precondition(finalSamples == Array(repeating: 0.5, count: 24_000))
        let recovered = try BroadcastMailboxSet(environment: environment).recover()
        precondition(recovered?.id == request.id && recovered?.binding.groupID == common)
        try host.clearAudio(request)
        let handled = try BroadcastMailboxSet(environment: environment).recover()
        precondition(handled == nil)

        // A later launch may discover an extra container carrying an older
        // request. Recovery must use the newest UUID and ignore the old group.
        let singleGroupHost = BroadcastMailboxSet(environment: uploadEnvironment)
        let newer = try singleGroupHost.prepare(duration: 3)
        try selected.mailbox.publish(BroadcastState(id: newer.id, binding: newer.binding,
            phase: .completed, samples: Array(repeating: 0.25, count: 8_000)))
        var recoveredHost = BroadcastMailboxSet(environment: environment)
        let newest = try recoveredHost.recover()
        precondition(newest?.id == newer.id)
        let newestState = try recoveredHost.state(newer)
        precondition(newestState.binding.groupID == common)
        try recoveredHost.send(.matched, request: newer)
        try recoveredHost.clearAudio(newer)

        var retry = BroadcastMailboxSet(environment: environment)
        let next = try retry.prepare(duration: 3)
        try host.send(.cancel, request: request)
        let nextBeforeStart = try retry.state(next)
        precondition(nextBeforeStart.phase == .waiting)
        let mismatch = BroadcastBinding(extensionID: "example.wrong.Upload", groupID: common)
        try endpoints[1].mailbox.publish(BroadcastState(id: next.id, binding: mismatch, phase: .completed,
            samples: Array(repeating: 1, count: 24_000)))
        expect(.handshakeMismatch) { _ = try retry.state(next) }
        expect(.handshakeMismatch) { _ = try BroadcastMailboxSet(environment: environment).recover() }

        // Corrupt the current file deliberately; publish() correctly routes by
        // the supplied UUID and must not create a random session directory.
        let wrongUUIDState = BroadcastState(id: UUID(), binding: retry.binding(endpoints[1]), phase: .completed)
        let currentStateURL = endpoints[1].mailbox.root.appendingPathComponent(next.id.uuidString)
            .appendingPathComponent("state.plist")
        try PropertyListEncoder().encode(wrongUUIDState).write(to: currentStateURL)
        expect(.handshakeMismatch) { _ = try retry.state(next) }

        var cancelled = BroadcastMailboxSet(environment: environment)
        let cancelRequest = try cancelled.prepare(duration: 3)
        try cancelled.send(.cancel, request: cancelRequest)
        try cancelled.send(.complete, request: cancelRequest)
        let control = try endpoints[1].mailbox.control(cancelRequest.id)
        precondition(control?.command == .cancel, "Late completion must not undo cancellation")
        expect(.startNotPrepared) { _ = try BroadcastMailboxSet(environment: uploadEnvironment).requestForExtension() }
        do { _ = try cancelled.state(cancelRequest); fatalError("Cancelled session accepted") } catch is CancellationError { }

        var waiting = BroadcastMailboxSet(environment: environment)
        let waitingRequest = try waiting.prepare(duration: 3)
        expect(.startNotConfirmed) { _ = try waiting.state(waitingRequest, now: waitingRequest.startBefore) }
        expect(.startNotPrepared) {
            _ = try BroadcastMailboxSet(environment: uploadEnvironment).requestForExtension(now: waitingRequest.startBefore)
        }
        let oversizedState = endpoints[0].mailbox.root.appendingPathComponent(waitingRequest.id.uuidString)
            .appendingPathComponent("state.plist")
        try Data(repeating: 0, count: BroadcastMailbox.maximumFileBytes + 1).write(to: oversizedState)
        expect(.handshakeMismatch) { _ = try waiting.state(waitingRequest) }
        print("PASS: common usable group handshake, actual ID/UUID/group validation, recovery/cleanup, stale cancel/retry, sticky cancellation and bounded unconfirmed startup")
    }

    static func unusedEndpointIsolation() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let groups = ["group.synthetic.a", "group.synthetic.b", "group.synthetic.c"]
        let endpoints = try BroadcastRuntime.probe(groups.map {
            BroadcastGroupCandidate(identifier: $0, origin: .commonProfile)
        }, profileIssue: false) { root.appendingPathComponent($0) }
        let hostEnvironment = BroadcastRuntimeEnvironment(extensionID: actualID,
            endpoints: Array(endpoints.prefix(2)), diagnostic: BroadcastDiagnostic(code: .startNotConfirmed))
        let uploadEnvironment = BroadcastRuntimeEnvironment(extensionID: actualID,
            endpoints: Array(endpoints.suffix(2)), diagnostic: hostEnvironment.diagnostic)
        let host = BroadcastMailboxSet(environment: hostEnvironment)
        let upload = BroadcastMailboxSet(environment: uploadEnvironment)
        let now = Date(timeIntervalSince1970: 50_000)
        let request = BroadcastRequest(duration: 3, binding: host.binding(endpoints[0]), now: now)
        for endpoint in hostEnvironment.endpoints {
            try endpoint.mailbox.prepare(request.bound(to: host.binding(endpoint)))
        }
        let extra = endpoints[2]
        let foreign = BroadcastRequest(duration: 3,
            binding: BroadcastBinding(extensionID: "example.previous.Upload", groupID: groups[2]),
            now: now.addingTimeInterval(-300))
        try extra.mailbox.prepare(foreign)
        let (selected, selectedRequest) = try upload.requestForExtension(now: now)
        precondition(selected.candidate.identifier == groups[1] && selectedRequest.id == request.id)

        let headerURL = extra.mailbox.root.appendingPathComponent("request.plist")
        try Data([0xff]).write(to: headerURL)
        let (selectedAfterCorruption, current) = try upload.requestForExtension(now: now)
        precondition(selectedAfterCorruption.candidate.identifier == groups[1] && current.id == request.id)
        let session = try BroadcastSession(request: current, now: now, uptime: 0,
            initialState: selected.mailbox.state(current.id), control: selected.mailbox.control(current.id))
        try selected.mailbox.publish(session.state(now: now))
        var acknowledgedHost = host
        let ack = try acknowledgedHost.state(request, now: now)
        precondition(ack.binding == current.binding && acknowledgedHost.selectedGroup == groups[1])
        expect(.startNotPrepared) { _ = try upload.requestForExtension(now: now) }

        // Duplicate acknowledgements remain an error in the host's own set.
        try endpoints[0].mailbox.publish(BroadcastState(id: request.id, binding: request.binding, phase: .capturing, now: now))
        expect(.handshakeMismatch) { _ = try acknowledgedHost.state(request, now: now) }
        for endpoint in hostEnvironment.endpoints {
            try endpoint.mailbox.publish(BroadcastState(id: request.id, binding: host.binding(endpoint), phase: .waiting, now: now))
        }

        // Unknown/foreign headers cannot hide evidence for this exact UUID.
        let extraBinding = upload.binding(extra)
        try extra.mailbox.prepare(request.bound(to: extraBinding))
        let foreignSameUUID = request.bound(to: foreign.binding)
        try extra.mailbox.prepare(foreignSameUUID)
        expect(.handshakeMismatch) { _ = try upload.requestForExtension(now: now) }
        try Data([0xff]).write(to: headerURL)
        expect(.handshakeMismatch) { _ = try upload.requestForExtension(now: now) }
        try extra.mailbox.publish(BroadcastState(id: request.id, binding: extraBinding, phase: .completed, now: now))
        expect(.startNotPrepared) { _ = try upload.requestForExtension(now: now) }
        try extra.mailbox.publish(BroadcastState(id: request.id, binding: extraBinding, phase: .waiting, now: now))
        try extra.mailbox.send(.cancel, id: request.id, binding: extraBinding)
        try extra.mailbox.send(.complete, id: request.id, binding: extraBinding)
        let control = try extra.mailbox.control(request.id)
        precondition(control?.command == .cancel)
        expect(.startNotPrepared) { _ = try upload.requestForExtension(now: now) }
        print("PASS: host [A,B]/extension [B,C], unused foreign/corrupt headers, selected-UUID mismatch/consumption/cancellation and duplicate acknowledgements")
    }

}
