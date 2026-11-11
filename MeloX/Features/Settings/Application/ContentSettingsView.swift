import SwiftUI

struct ContentSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        @Bindable var recognition = settings.songRecognition

        Form {
            Section("ui.settings.content.section.discovery") {
                Picker("ui.settings.content.album_region", selection: $settings.musicArea) {
                    Text("ui.region.all").tag("ALL")
                    Text("ui.region.china").tag("ZH")
                    Text("ui.region.europe_america").tag("EA")
                    Text("ui.region.korea").tag("KR")
                    Text("ui.region.japan").tag("JP")
                }

                Toggle("ui.settings.content.show_play_count", isOn: $settings.showPlayCount)
            }

            Section {
                Picker("ui.recognition.source", selection: $recognition.audioSource) {
                    ForEach(SongRecognitionAudioSource.availableCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                Picker(
                    "ui.settings.content.recognition_duration",
                    selection: $recognition.duration
                ) {
                    ForEach(
                        SongRecognitionDuration.allCases
                    ) { duration in
                        Text(
                            L10n.joined(
                                [duration.title, duration.detail],
                                separatorKey:
                                    "ui.common.metadata_separator"
                            )
                        )
                        .tag(duration)
                    }
                }
            } header: {
                Text("ui.settings.content.section.recognition")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recognition.audioSource.detail)
                    if recognition.audioSource == .appAudio {
                        Text("ui.recognition.system_audio_availability")
                        Text(recognition.duration.isContinuous
                            ? L10n.string("ui.recognition.capture.continuous")
                            : L10n.format("ui.recognition.capture.limited", recognition.duration.title))
                    } else if recognition.duration.isContinuous {
                        Text("ui.settings.content.recognition.footer.continuous")
                    } else {
                        Text("ui.settings.content.recognition.footer.limited")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("ui.settings.content.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
