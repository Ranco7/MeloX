import ReplayKit
import SwiftUI

/// The public native button stays visible and receives the user's tap directly.
struct SongRecognitionBroadcastPicker: UIViewRepresentable {
    let extensionID: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.preferredExtension = extensionID
        picker.tintColor = .label
        picker.showsMicrophoneButton = false
        picker.accessibilityLabel = L10n.string("ui.recognition.broadcast.launch")
        picker.accessibilityHint = L10n.string("ui.recognition.broadcast.launch_hint")
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = extensionID
        uiView.showsMicrophoneButton = false
    }
}
