import AVFoundation
import Foundation

enum AudioPlaybackMixMode: Equatable {
    case exclusive
    case mixWithOthers
}

@MainActor
enum AudioPlaybackSessionConfigurator {
    /// When on, the playback session stays mixable so other apps do not interrupt it.
    static var preferredMixMode: AudioPlaybackMixMode = .exclusive

    private(set) static var isApplyingConfiguration = false
    private static var lastConfigurationDate: Date?

    /// Interruption notifications arrive asynchronously on the main queue, so
    /// `isApplyingConfiguration` has already been cleared when the handler
    /// runs. A short recency window keeps our own category change from being
    /// mistaken for an external interruption.
    static func shouldIgnoreInterruption() -> Bool {
        if isApplyingConfiguration { return true }
        guard let lastConfigurationDate else { return false }
        return Date().timeIntervalSince(lastConfigurationDate) < 0.5
    }

    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord {
            return
        }

        let options: AVAudioSession.CategoryOptions =
            preferredMixMode == .mixWithOthers ? [.mixWithOthers] : []
        let needsCategory =
            session.category != .playback
            || session.mode != .default
            || session.categoryOptions != options

        isApplyingConfiguration = true
        defer { isApplyingConfiguration = false }

        if needsCategory {
            try session.setCategory(
                .playback,
                mode: .default,
                options: options
            )
            lastConfigurationDate = Date()
        }
        if !session.supportsMultichannelContent {
            try? session.setSupportsMultichannelContent(true)
        }
        if !session.prefersInterruptionOnRouteDisconnect {
            try session.setPrefersInterruptionOnRouteDisconnect(true)
        }
        try session.setActive(true)
    }
}
