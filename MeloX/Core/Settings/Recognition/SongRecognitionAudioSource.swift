import Foundation

enum SongRecognitionAudioSource: String, CaseIterable, Identifiable {
    case microphone
    case appAudio
    case systemAudio

    var id: String { rawValue }

    static var availableCases: [Self] {
        // appAudio keeps the saved preference identity; capture uses ReplayKit.
        return [.microphone, .appAudio]
    }

    var title: String { L10n.string("ui.recognition.source.\(rawValue)") }
    var detail: String { L10n.string("ui.recognition.source.\(rawValue).detail") }
    var systemImage: String {
        switch self {
        case .microphone: "mic.fill"
        case .appAudio: "music.note"
        case .systemAudio: "speaker.wave.2.fill"
        }
    }

    var preparationTitle: String {
        L10n.string(self == .microphone
            ? "ui.recognition.preparing_microphone"
            : "ui.recognition.preparing_capture")
    }

    var permissionMessage: String {
        switch self {
        case .microphone: L10n.string("ui.recognition.microphone_permission_message")
        case .appAudio: detail
        case .systemAudio: L10n.string("ui.recognition.capture_permission_message")
        }
    }
}
