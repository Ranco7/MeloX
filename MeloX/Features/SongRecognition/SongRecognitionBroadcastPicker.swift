import Foundation
import Observation
import ReplayKit
import SwiftUI
import UIKit

/// ReplayKit has no public custom-trigger API. Keep its native control available
/// if its internal button is absent or changes in a future system release.
@MainActor
@Observable
final class SongRecognitionBroadcastPickerController {
    private(set) var canForward = false
    @ObservationIgnored private weak var picker: RPSystemBroadcastPickerView?
    @ObservationIgnored private var lastLaunch = Date.distantPast

    func attach(_ picker: RPSystemBroadcastPickerView) {
        self.picker = picker
        refresh()
    }

    func detach(_ picker: RPSystemBroadcastPickerView) {
        guard self.picker === picker else { return }
        self.picker = nil
        canForward = false
    }

    func refresh() {
        let available = picker?.subviews.contains(where: { ($0 as? UIButton)?.isEnabled == true }) == true
        if canForward != available { canForward = available }
    }

    func start() {
        guard Date().timeIntervalSince(lastLaunch) >= 1 else { return }
        guard let button = picker?.subviews.first(where: { $0 is UIButton }) as? UIButton,
              button.isEnabled else {
            canForward = false
            return
        }
        lastLaunch = Date()
        button.sendActions(for: .touchUpInside)
    }
}

final class SongRecognitionNativeBroadcastPicker: RPSystemBroadcastPickerView {
    weak var controller: SongRecognitionBroadcastPickerController?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { controller?.detach(self) }
        else { scheduleRefresh() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            controller?.attach(self)
        }
    }
}

struct SongRecognitionBroadcastPicker: UIViewRepresentable {
    let extensionID: String
    let controller: SongRecognitionBroadcastPickerController

    func makeUIView(context: Context) -> SongRecognitionNativeBroadcastPicker {
        let picker = SongRecognitionNativeBroadcastPicker(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.controller = controller
        picker.preferredExtension = extensionID
        picker.tintColor = .white
        picker.showsMicrophoneButton = false
        picker.accessibilityLabel = L10n.string("ui.recognition.broadcast.launch")
        picker.accessibilityHint = L10n.string("ui.recognition.broadcast.launch_hint")
        return picker
    }

    func updateUIView(_ uiView: SongRecognitionNativeBroadcastPicker, context: Context) {
        uiView.controller = controller
        uiView.preferredExtension = extensionID
        uiView.tintColor = .white
        uiView.showsMicrophoneButton = false
    }

    static func dismantleUIView(_ uiView: SongRecognitionNativeBroadcastPicker, coordinator: ()) {
        uiView.controller?.detach(uiView)
        uiView.controller = nil
    }
}
