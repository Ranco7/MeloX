import Foundation
import OSLog

struct PlaybackSnapshot: Codable {
    let queue: [Song]
    let currentIndex: Int
    var progress: TimeInterval
    let repeatMode: String
    let isShuffled: Bool
    let shuffledOrder: [Int]
    let volume: Double
    let historySourceID: Int?
    let heartModeEnabled: Bool?
    let autoplayEnabled: Bool?
    let autoMixEnabled: Bool?
    let queueModeIndicator: String?
}

@MainActor
final class PlaybackPersistence {
    private enum Key {
        static let snapshot = "player.playbackSnapshot"
        static let progress = "player.playbackProgress"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MeloX",
        category: "PlaybackPersistence"
    )

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PlaybackSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        guard var snapshot = try? JSONDecoder().decode(
            PlaybackSnapshot.self,
            from: data
        ) else {
            Self.logger.error("Failed to decode playback snapshot")
            return nil
        }
        // The playback clock writes the resume position to its own lightweight
        // key so it never has to re-encode the whole queue while playing.
        if let storedProgress = defaults.object(
            forKey: Key.progress
        ) as? Double {
            snapshot.progress = storedProgress
        }
        return snapshot
    }

    func save(_ snapshot: PlaybackSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Key.snapshot)
            defaults.set(snapshot.progress, forKey: Key.progress)
        } catch {
            Self.logger.error(
                "Failed to encode playback snapshot: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Saves only the resume position from the 100 ms playback clock. The
    /// queue itself is written on structural changes.
    func saveProgress(_ progress: TimeInterval) {
        guard progress.isFinite else { return }
        defaults.set(progress, forKey: Key.progress)
    }

    func clear() {
        defaults.removeObject(forKey: Key.snapshot)
        defaults.removeObject(forKey: Key.progress)
    }
}
