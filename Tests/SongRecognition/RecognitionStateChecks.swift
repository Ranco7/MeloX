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

    func start(maximumDuration: Int?, source: SongRecognitionAudioSource, playbackAudio: PlaybackAudioCapture?) async throws {
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
        store.start(api: api, duration: .quick, source: .appAudio)
        precondition(store.phase == .requestingPermission)
        await wait { !store.phase.isWorking }
        assertFailure(store, .captureUnavailable)
        precondition(api.requests == 0)

        recorder.startFailure = nil
        recorder.snapshotFailure = SongRecognitionRecordingError.conversionFailed
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { !store.phase.isWorking }
        assertFailure(store, .conversionFailed)
        precondition(recorder.stops > 0 && api.requests == 0)
        print("PASS: startup and callback failures become recoverable failures and stop capture")

        recorder.snapshotFailure = nil
        recorder.value = snapshot(reachedLimit: true)
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { !store.phase.isWorking }
        precondition(store.phase == .noMatch && api.requests == 1)
        api.candidates = [AudioMatchCandidate(song: Song(id: 1), startTime: -50),
                          AudioMatchCandidate(song: Song(id: 1), startTime: 0),
                          AudioMatchCandidate(song: Song(id: 2), startTime: 1_500)]
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { store.results.count == 2 && !store.phase.isWorking }
        precondition(store.phase == .results && store.results.map(\.id) == [1, 2])
        precondition(store.results[0].playbackPosition == 0 && store.results[1].playbackPosition == 1.5)
        print("PASS: PCM snapshots use existing fingerprint/match results and empty state")

        recorder.value = snapshot(reachedLimit: false)
        store.start(api: api, duration: .continuous, source: .appAudio)
        await wait { store.results.count == 2 && store.phase == .listening }
        store.stopContinuousRecognition()
        precondition(store.phase == .results && store.results.count == 2)
        print("PASS: stopping continuous capture preserves recognized results")

        recorder.suspendsStartup = true
        recorder.value = snapshot(reachedLimit: true)
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { recorder.startup != nil }
        store.cancel()
        precondition(store.phase == .ready)
        let starts = recorder.starts
        store.start(api: api, duration: .quick, source: .appAudio)
        recorder.startup?.resume()
        recorder.startup = nil
        await wait { recorder.starts > starts && store.phase == .results }
        precondition(store.results.count == 2)
        print("PASS: cancel/restart serializes startup cleanup and ignores stale completion")

        recorder.value = nil
        store.start(api: api, duration: .quick, source: .appAudio)
        await wait { store.phase == .listening }
        try await Task.sleep(for: .seconds(8))
        assertFailure(store, .captureTimedOut)
        precondition(!SongRecognitionAudioSource.availableCases.contains(.systemAudio))
        let domain = "MeloX.RecognitionStateChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("systemAudio", forKey: "songRecognition.audioSource")
        precondition(SongRecognitionPreferences(defaults: defaults).audioSource == .microphone)
        print("PASS: missing PCM times out; unavailable cross-app source is not advertised/restored")
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
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("Recognition did not reach expected state")
    }
}
