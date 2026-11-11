import SwiftUI
import UIKit

struct SongRecognitionView: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(NeteaseAPI.self) private var api
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings

    @State private var recognition = SongRecognitionStore()
    @State private var broadcastPicker = SongRecognitionBroadcastPickerController()

    var body: some View {
        Group {
            switch recognition.phase {
            case .ready:
                readyView
            case .requestingPermission:
                progressView(
                    title: recognition.audioSource.preparationTitle,
                    description: recognition.audioSource.permissionMessage
                )
            case .waitingForBroadcast:
                broadcastWaitingView
            case .listening:
                if recognition.isContinuous {
                    continuousListeningView
                } else {
                    listeningView
                }
            case .matching:
                progressView(
                    title: L10n.string("ui.recognition.matching"),
                    description: L10n.string("ui.recognition.matching_message")
                )
            case .results:
                resultsView
            case .noMatch:
                noMatchView
            case .failed(let failure):
                failureView(failure)
            }
        }
        .navigationTitle("ui.recognition.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsRestartButton {
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        "ui.recognition.restart",
                        systemImage: "arrow.clockwise",
                        action: startRecognition
                    )
                }
            }
        }
        .alert(
            "ui.error.favorite_failed",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.clearError() } }
            )
        ) {
            Button("ui.common.ok", role: .cancel) {
                library.clearError()
            }
        } message: {
            Text(library.errorMessage ?? L10n.string("ui.common.unknown_error"))
        }
        .task { await recognition.resumeBroadcastIfNeeded(api: api) }
        .onDisappear {
            recognition.cancel()
        }
    }

    private var readyView: some View {
        stateContent {
            messageHeader(title: L10n.string("ui.recognition.title"), symbol: "waveform", description: readyDescription)
            VStack(spacing: 12) {
                FilterPicker(title: "ui.recognition.source", selection: audioSourceBinding,
                             maximumWidth: 360, usesMenu: true) {
                    ForEach(SongRecognitionAudioSource.availableCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                Button("ui.recognition.start", systemImage: settings.songRecognition.audioSource.systemImage,
                       action: startRecognition)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private var listeningView: some View {
        stateContent {
            listeningSymbol
            VStack(spacing: 8) {
                Text("ui.recognition.listening")
                    .font(.title2.weight(.semibold))
                Text(recognition.audioSource == .microphone
                     ? L10n.format("ui.recognition.listening_message", settings.songRecognition.duration.title)
                     : recognition.audioSource.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recognition.audioSource != .microphone {
                if recognition.broadcastPaused {
                    Text("ui.recognition.broadcast.paused").foregroundStyle(.secondary)
                }
                Button("ui.recognition.broadcast.stop", action: recognition.stopBroadcastCapture)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Button("ui.common.cancel", role: .cancel) { recognition.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var broadcastWaitingView: some View {
        stateContent {
            messageHeader(title: L10n.string("ui.recognition.broadcast.waiting"), symbol: "record.circle",
                          description: L10n.string("ui.recognition.broadcast.instructions"))
            VStack(spacing: 8) {
                if let extensionID = recognition.broadcastExtensionID {
                    ZStack {
                        SongRecognitionBroadcastPicker(extensionID: extensionID, controller: broadcastPicker)
                            .frame(width: 56, height: 56)
                            .background(.tint, in: Capsule())
                            .opacity(broadcastPicker.canForward ? 0 : 1)
                            .accessibilityHidden(broadcastPicker.canForward)
                        if broadcastPicker.canForward {
                            Button(action: broadcastPicker.start) {
                                Text("ui.recognition.broadcast.launch")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityHint("ui.recognition.broadcast.launch_hint")
                        }
                    }
                    if !broadcastPicker.canForward {
                        Text("ui.recognition.broadcast.launch")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(role: .cancel) { recognition.cancel() } label: {
                    Text("ui.common.cancel")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(maxWidth: 320)
            if let diagnostic = recognition.broadcastStartupDiagnostic { diagnosticDetails(diagnostic) }
            Text("ui.recognition.broadcast.privacy").font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var continuousListeningView: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    listeningSymbol

                    VStack(spacing: 8) {
                        Text("ui.recognition.continuous")
                            .font(.headline)
                        Text("ui.recognition.continuous_message")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("ui.recognition.stop", role: .cancel) {
                        recognition.stopContinuousRecognition()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowSeparator(.hidden)
            }

            if !recognition.results.isEmpty {
                Section("ui.recognition.results") {
                    ForEach(recognition.results) { result in
                        recognitionResultRow(result)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var resultsView: some View {
        List {
            Section("ui.recognition.results") {
                ForEach(recognition.results) { result in
                    recognitionResultRow(result)
                }
            }
        }
        .listStyle(.plain)
    }

    private var listeningSymbol: some View {
        Image(systemName: "waveform")
            .font(.system(size: 48, weight: .medium))
            .foregroundStyle(.tint)
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating.speed(1.2),
                isActive: !accessibilityReduceMotion
            )
            .accessibilityHidden(true)
    }

    private func recognitionResultRow(
        _ result: SongRecognitionResult
    ) -> some View {
        Button {
            play(result)
        } label: {
            TrackRowView(
                song: result.song,
                showsArtwork: true
            )
        }
        .buttonStyle(MusicTrackPressStyle())
        .swipeActions(edge: .trailing) {
            Button {
                library.toggle(song: result.song)
            } label: {
                Label(
                    library.contains(song: result.song)
                        ? L10n.string("ui.common.unfavorite")
                        : L10n.string("ui.common.favorite"),
                    systemImage:
                        library.contains(song: result.song)
                            ? "heart.slash"
                            : "heart"
                )
            }
            .tint(.pink)
        }
        .accessibilityHint("ui.recognition.play_from_match_hint")
    }

    private var noMatchView: some View {
        stateContent {
            messageHeader(title: L10n.string("ui.recognition.no_match"), symbol: "questionmark.circle",
                          description: L10n.string("ui.recognition.no_match_message"))
            Button("ui.recognition.try_again", systemImage: "arrow.clockwise", action: startRecognition)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func failureView(_ failure: SongRecognitionFailure) -> some View {
        stateContent {
            messageHeader(title: L10n.string("ui.recognition.failed"), symbol: "exclamationmark.triangle",
                          description: failure.message)
            if let diagnostic = failure.diagnostic { diagnosticDetails(diagnostic) }
            VStack(spacing: 12) {
                if failure.opensSystemSettings,
                   let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Button("ui.common.open_system_settings", systemImage: "gear") { openURL(settingsURL) }
                        .buttonStyle(.borderedProminent)
                    Button("ui.common.retry", systemImage: "arrow.clockwise", action: startRecognition)
                        .buttonStyle(.bordered)
                } else {
                    Button("ui.common.retry", systemImage: "arrow.clockwise", action: startRecognition)
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            if recognition.audioSource != .microphone {
                Button("ui.recognition.broadcast.use_microphone") {
                    settings.songRecognition.audioSource = .microphone
                    startRecognition()
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
    }

    private func diagnosticDetails(_ message: String) -> some View {
        DisclosureGroup {
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("ui.recognition.diagnostic.details")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
    }

    private func progressView(title: String, description: String) -> some View {
        stateContent {
            ProgressView().controlSize(.large)
            VStack(spacing: 8) {
                Text(title).font(.headline)
                Text(description).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("ui.common.cancel", role: .cancel) { recognition.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private func messageHeader(title: String, symbol: String, description: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(description).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stateContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 24, content: content)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
        }
        .defaultScrollAnchor(.center, for: .alignment)
    }

    private var showsRestartButton: Bool {
        switch recognition.phase {
        case .results, .noMatch, .failed:
            true
        case .ready,
             .requestingPermission,
             .waitingForBroadcast,
             .listening,
             .matching:
            false
        }
    }

    private var readyDescription: String {
        let duration = settings.songRecognition.duration
        if settings.songRecognition.audioSource != .microphone {
            let timing = duration.isContinuous
                ? L10n.string("ui.recognition.capture.continuous")
                : L10n.format("ui.recognition.capture.limited", duration.title)
            return settings.songRecognition.audioSource.detail + "\n" + timing
        }
        if duration.isContinuous {
            return L10n.string("ui.recognition.ready.continuous")
        }
        return L10n.format("ui.recognition.ready.limited", duration.title)
    }

    private var audioSourceBinding: Binding<SongRecognitionAudioSource> {
        Binding(
            get: { settings.songRecognition.audioSource },
            set: { settings.songRecognition.audioSource = $0 }
        )
    }

    private func play(_ result: SongRecognitionResult) {
        recognition.prepareForResultPlayback()
        Task {
            await player.play(
                result.song,
                in: recognition.results.map(\.song),
                startAt: result.playbackPosition
            )
        }
    }

    private func startRecognition() {
        if settings.songRecognition.audioSource == .microphone, player.isPlaying {
            player.togglePlayback()
        }
        recognition.start(
            api: api,
            duration: settings.songRecognition.duration,
            source: settings.songRecognition.audioSource
        )
    }
}
