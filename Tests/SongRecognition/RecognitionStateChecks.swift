// Runs the production state store and recording contracts with deterministic
// recorder/fingerprint/network doubles. No capture devices or real requests.
import Foundation

enum L10n {
    static func string(_ key: String) -> String { key }
    static func format(_ key: String, _ arguments: CVarArg...) -> String { key }
}
struct Song: Decodable { let id: Int }

@MainActor
final class NeteaseAPI {
    var candidates: [AudioMatchCandidate] = []
    private(set) var requests = 0
    func audioMatches(fingerprint: String, duration: Int) async throws -> [AudioMatchCandidate] {
        precondition(fingerprint == "fixture" && duration > 0)
        requests += 1
        return candidates
    }
    func songDetails(ids: [Int]) async throws -> [Song] { ids.map { Song(id: $0) } }
}

@MainActor
final class NeteaseAudioFingerprintGenerator: AudioFingerprintGenerating {
    func generate(from samples: [Float]) async throws -> String {
        precondition(!samples.isEmpty)
        return "fixture"
    }
}

@MainActor
final class SongRecognitionAudioRecorder: SongRecognitionRecording {
    var startFailure: Error?
    var snapshotFailure: Error?
    var startup: CheckedContinuation<Void, Never>?
    var suspendsStartup = false
    var value: SongRecognitionAudioSnapshot?
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0

    func start(maximumDuration: Int?, source: SongRecognitionAudioSource) async throws {
        starts += 1
        if let startFailure { throw startFailure }
        if suspendsStartup {
            suspendsStartup = false
            await withCheckedContinuation { startup = $0 }
        }
        try Task.checkCancellation()
    }
    func snapshot() throws -> SongRecognitionAudioSnapshot? {
        if let snapshotFailure { throw snapshotFailure }
        return value
    }
    func prepareForConcurrentPlayback() { }
    func cancel() { cancels += 1 }
    func stop() { stops += 1 }
}

@main
struct RecognitionStateChecks {
    @MainActor
    static func main() async throws {
        let api = NeteaseAPI()
        let recorder = SongRecognitionAudioRecorder()
        let store = SongRecognitionStore(recorder: recorder, fingerprintGenerator: NeteaseAudioFingerprintGenerator())
        recorder.startFailure = SongRecognitionRecordingError.captureUnavailable
        store.start(api: api, duration: .quick, source: .microphone)
        precondition(store.phase == .requestingPermission)
        await wait { !store.phase.isWorking }
        assertFailure(store, .captureUnavailable)
        precondition(api.requests == 0)

        recorder.startFailure = nil
        recorder.snapshotFailure = SongRecognitionRecordingError.conversionFailed
        store.start(api: api, duration: .quick, source: .microphone)
        await wait { !store.phase.isWorking }
        assertFailure(store, .conversionFailed)
        precondition(recorder.stops > 0 && api.requests == 0)
        print("PASS: startup and callback failures become recoverable failures and stop capture")

        recorder.snapshotFailure = nil
        recorder.value = snapshot(reachedLimit: true)
        store.start(api: api, duration: .quick, source: .microphone)
        await wait { !store.phase.isWorking }
        precondition(store.phase == .noMatch && api.requests == 1)
        api.candidates = [AudioMatchCandidate(song: Song(id: 1), startTime: -50),
                          AudioMatchCandidate(song: Song(id: 1), startTime: 0),
                          AudioMatchCandidate(song: Song(id: 2), startTime: 1_500)]
        store.start(api: api, duration: .quick, source: .microphone)
        await wait { store.results.count == 2 && !store.phase.isWorking }
        precondition(store.phase == .results && store.results.map(\.id) == [1, 2])
        precondition(store.results[0].playbackPosition == 0 && store.results[1].playbackPosition == 1.5)
        print("PASS: PCM snapshots use existing fingerprint/match results and empty state")

        recorder.value = snapshot(reachedLimit: false)
        store.start(api: api, duration: .continuous, source: .microphone)
        await wait { store.results.count == 2 && store.phase == .listening }
        store.stopContinuousRecognition()
        precondition(store.phase == .results && store.results.count == 2)
        print("PASS: stopping continuous capture preserves recognized results")

        recorder.suspendsStartup = true
        recorder.value = snapshot(reachedLimit: true)
        store.start(api: api, duration: .quick, source: .microphone)
        await wait { recorder.startup != nil }
        store.cancel()
        precondition(store.phase == .ready)
        let starts = recorder.starts
        store.start(api: api, duration: .quick, source: .microphone)
        recorder.startup?.resume()
        recorder.startup = nil
        await wait { recorder.starts > starts && store.phase == .results }
        precondition(store.results.count == 2)
        print("PASS: cancel/restart serializes startup cleanup and ignores stale completion")

        recorder.value = nil
        store.start(api: api, duration: .quick, source: .microphone)
        await wait { store.phase == .listening }
        try await Task.sleep(for: .seconds(8))
        assertFailure(store, .recordingTimedOut)
        precondition(!SongRecognitionAudioSource.availableCases.contains(.systemAudio))
        let domain = "MeloX.RecognitionStateChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("systemAudio", forKey: "songRecognition.audioSource")
        precondition(SongRecognitionPreferences(defaults: defaults).audioSource == .microphone)
        print("PASS: microphone timeout and legacy preference fallback")
        try await broadcastChecks(api: api)
    }

    @MainActor
    private static func broadcastChecks(api: NeteaseAPI) async throws {
        let client = BroadcastDouble()
        let recorder = SongRecognitionAudioRecorder()
        let store = SongRecognitionStore(recorder: recorder, fingerprintGenerator: NeteaseAudioFingerprintGenerator(), broadcastClient: client)
        store.start(api: api, duration: .continuous, source: .appAudio)
        await wait { store.phase == .waitingForBroadcast }
        precondition(!store.isContinuous && recorder.starts == 0 && store.broadcastExtensionID == "fixture.BroadcastUpload")
        let duration = await client.duration
        precondition(duration == 9)
        await client.setNotice(true)
        await wait { store.broadcastStartupDiagnostic != nil }
        precondition(store.phase == .waitingForBroadcast && store.broadcastStartupDiagnostic?.contains("[startNotConfirmed]") == true)
        await client.setNotice(false)
        await client.setPhase(.capturing)
        await wait { store.phase == .listening }
        store.stopBroadcastCapture()
        await wait { store.phase == .results }
        precondition(store.broadcastExtensionID == nil && store.broadcastStartupDiagnostic == nil && recorder.starts == 0)
        print("PASS: native-picker waiting state, bounded system mode, manual finish and existing match pipeline")

        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { store.phase == .waitingForBroadcast }
        await client.setPhase(.silent)
        await wait { !store.phase.isWorking }
        assertFailure(store, .broadcastSilent)
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { store.phase == .waitingForBroadcast }
        store.cancel()
        precondition(store.phase == .ready && store.broadcastExtensionID == nil)
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { store.phase == .waitingForBroadcast }
        await client.setPhase(.completed)
        await wait { store.phase == .results }
        print("PASS: silence error, cancellation before picker start, retry and stale UUID control isolation")

        await client.setFailure(BroadcastDiagnostic(code: .invalidExtensionID))
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { !store.phase.isWorking }
        guard case .failed(let setupFailure) = store.phase else { fatalError("Expected setup diagnostic") }
        precondition(setupFailure.message == SongRecognitionRecordingError.captureUnavailable.localizedDescription)
        precondition(setupFailure.diagnostic?.contains("[invalidExtensionID]") == true)
        precondition(store.broadcastExtensionID == nil && recorder.starts == 0)
        print("PASS: safe localized setup diagnostic preserves the friendly failure and microphone fallback")

        let unavailable = SongRecognitionStore(recorder: recorder, fingerprintGenerator: NeteaseAudioFingerprintGenerator())
        unavailable.start(api: api, duration: .quick, source: .appAudio)
        await wait { !unavailable.phase.isWorking }
        assertFailure(unavailable, .captureUnavailable)
        precondition(unavailable.broadcastExtensionID == nil && recorder.starts == 0)
        print("PASS: missing extension/group safely fails without touching microphone capture")
    }

    private static func snapshot(reachedLimit: Bool) -> SongRecognitionAudioSnapshot {
        SongRecognitionAudioSnapshot(samples: Array(repeating: 0.5, count: 24_000),
                                     duration: 3, totalDuration: 3, reachedLimit: reachedLimit)
    }

    @MainActor
    private static func assertFailure(_ store: SongRecognitionStore, _ error: SongRecognitionRecordingError) {
        guard case .failed(let failure) = store.phase else { fatalError("Expected failed state, got \(store.phase)") }
        precondition(failure.message == error.localizedDescription && !failure.opensSystemSettings)
    }

    @MainActor
    private static func wait(until condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Recognition did not reach expected state")
    }
}


actor BroadcastDouble: SongRecognitionBroadcasting {
    var duration = 0
    private var current: BroadcastRequest?
    private var phase: BroadcastPhase = .waiting
    private var notice = false
    private var setupFailure: BroadcastDiagnostic?
    func setNotice(_ value: Bool) { notice = value }
    func setFailure(_ value: BroadcastDiagnostic?) { setupFailure = value }
    func prepare(duration: Int) throws -> PreparedBroadcast {
        self.duration = duration
        if let setupFailure { throw setupFailure }
        let request = BroadcastRequest(duration: duration, binding: BroadcastBinding(extensionID: "fixture.BroadcastUpload", groupID: "group.fixture.MeloX"))
        current = request
        phase = .waiting
        return PreparedBroadcast(request: request, extensionID: "fixture.BroadcastUpload")
    }
    func recover() throws -> PreparedBroadcast? { nil }
    func setPhase(_ phase: BroadcastPhase) { self.phase = phase }
    func poll(_ request: BroadcastRequest) throws -> BroadcastPoll {
        guard request.id == current?.id else { throw CancellationError() }
        if phase == .silent { throw SongRecognitionRecordingError.broadcastSilent }
        let snapshot = phase == .completed ? SongRecognitionAudioSnapshot(samples: Array(repeating: 0.5, count: 24_000),
            duration: 3, totalDuration: 3, reachedLimit: true) : nil
        return BroadcastPoll(phase: phase, snapshot: snapshot,
                             diagnostic: notice ? BroadcastDiagnostic(code: .startNotConfirmed) : nil)
    }
    func stop(_ request: BroadcastRequest, command: BroadcastStop) throws {
        guard request.id == current?.id else { return }
        if command == .complete { phase = .completed }
        else if command == .cancel { phase = .cancelled }
    }
    func clearAudio(_ request: BroadcastRequest) throws { }
}
