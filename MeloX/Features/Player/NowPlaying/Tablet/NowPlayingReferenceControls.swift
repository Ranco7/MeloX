import MediaPlayer
import SwiftUI

struct NowPlayingReferenceProgressControl: View {
    @Environment(PlayerStore.self) private var player

    let song: Song

    var body: some View {
        VStack(spacing: 6) {
            NowPlayingReferenceProgressSlider(maximum: progressMaximum)

            HStack(spacing: 10) {
                NowPlayingReferenceProgressElapsedTime()
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                Group {
                    if player.isAutoMixTransitioning {
                        NowPlayingReferenceAutoMixStatus()
                    } else {
                        NowPlayingReferenceQualityMenu()
                    }
                }
                .layoutPriority(1)
                .animation(
                    .smooth(duration: 0.25),
                    value: player.isAutoMixTransitioning
                )

                NowPlayingReferenceProgressRemainingTime()
                    .frame(
                        maxWidth: .infinity,
                        alignment: .trailing
                    )
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var progressMaximum: TimeInterval {
        max(player.duration, TimeInterval(song.durationMS) / 1_000, 1)
    }
}

/// Keeps the ten-times-per-second progress reads in leaf views so the AutoMix
/// status and quality menu do not rebuild on every clock tick.
private struct NowPlayingReferenceProgressSlider: View {
    @Environment(PlayerStore.self) private var player

    let maximum: TimeInterval

    var body: some View {
        Slider(
            value: Binding(
                get: { min(player.progress, maximum) },
                set: { player.seek(to: $0) }
            ),
            in: 0...maximum
        )
        .sliderThumbVisibility(.hidden)
        .contentShape(NowPlayingVerticalHitShape(minimumHeight: 44, maximumBottomOutset: 6))
        .tint(.white)
        .accessibilityLabel("ui.player.progress")
        .accessibilityValue(
            L10n.format(
                "ui.player.progress_accessibility",
                formatReferencePlaybackTime(player.progress),
                formatReferencePlaybackTime(maximum)
            )
        )
    }
}

private struct NowPlayingReferenceProgressElapsedTime: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        Text(formatReferencePlaybackTime(player.progress))
            .lineLimit(1)
    }
}

private struct NowPlayingReferenceProgressRemainingTime: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        Text(
            "−\(formatReferencePlaybackTime(max(player.duration - player.progress, 0)))"
        )
        .lineLimit(1)
    }
}

private func formatReferencePlaybackTime(_ value: TimeInterval) -> String {
    guard value.isFinite else { return "0:00" }
    let seconds = max(0, Int(value))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

private struct NowPlayingReferenceAutoMixStatus: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .semibold))
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating.speed(1.2),
                    isActive:
                        !accessibilityReduceMotion
                            && player.isAutoMixTransitioning
                )

            Text("ui.player.mixing")
                .fontWeight(.medium)
                .lineLimit(1)

            ProgressView(
                value:
                    player.autoMixTransitionProgress
                        ?? 0
            )
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(width: 30)

            Text(L10n.percentagePoints(Double(progressPercent)))
                .monospacedDigit()
                .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            .white.opacity(0.16),
            in: .rect(cornerRadius: 7)
        )
        .foregroundStyle(.white.opacity(0.86))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ui.player.automix_active")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let songName =
            player.autoMixIncomingSongName {
            return L10n.format(
                "ui.player.transitioning_to",
                songName,
                progressPercent
            )
        }
        return L10n.percentagePoints(Double(progressPercent))
    }

    private var progressPercent: Int {
        Int(
            (
                player.autoMixTransitionProgress
                    ?? 0
            ) * 100
        )
    }
}

private struct NowPlayingReferenceQualityMenu: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(NeteaseAPI.self) private var api

    var body: some View {
        Menu {
            if player.availablePlaybackQualities.isEmpty {
                Text("ui.player.loading_quality")
            } else {
                Picker("ui.player.quality", selection: qualityBinding) {
                    ForEach(player.availablePlaybackQualities) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .semibold))
                Text(displayedQualityTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                .white.opacity(0.12),
                in: .rect(cornerRadius: 7)
            )
            .frame(minHeight: NowPlayingPortraitLayout.minimumTouchTarget)
            .contentShape(.rect)
        }
        .tint(.white)
        .accessibilityLabel("ui.player.playback_quality")
        .accessibilityValue(displayedQualityTitle)
        .accessibilityHint("ui.player.quality_hint")
    }

    private var displayedQualityTitle: String {
        player.effectivePlaybackQuality?.title ?? L10n.string("ui.player.quality")
    }

    private var qualityBinding: Binding<MusicQuality> {
        Binding(
            get: {
                api.isCellularData
                    ? settings.cellularQuality
                    : settings.quality
            },
            set: { player.selectPlaybackQuality($0) }
        )
    }
}

struct NowPlayingReferenceTransportControls: View {
    enum Presentation {
        case standard
        case tablet
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var presentation: Presentation = .standard

    private var isTablet: Bool { presentation == .tablet }
    private var controlDiameter: CGFloat { isTablet ? 44 : 64 }

    var body: some View {
        HStack(spacing: isTablet ? 0 : nil) {
            if isTablet {
                Button(action: player.toggleShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(player.isShuffled ? .red : .white.opacity(0.58))
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    player.isShuffled
                        ? L10n.string("ui.player.shuffle_off")
                        : L10n.string("ui.player.shuffle_on")
                )
                .accessibilityAddTraits(player.isShuffled ? .isSelected : [])
            }

            Spacer(minLength: isTablet ? 0 : nil)

            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: isTablet ? 24 : 34, weight: .medium))
                    .frame(width: controlDiameter, height: controlDiameter)
                    .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion,
                    diameter: controlDiameter
                )
            )
            .accessibilityLabel("ui.player.previous")

            Spacer(minLength: isTablet ? 0 : nil)

            Button {
                player.togglePlayback()
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: isTablet ? 30 : 48, weight: .medium))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(
                                        .replace.downUp.wholeSymbol,
                                        options: .speed(1.6)
                                    )
                            )
                            .animation(
                                accessibilityReduceMotion
                                    ? nil
                                    : .snappy(duration: 0.2, extraBounce: 0),
                                value: player.isPlaying
                            )
                    }
                }
                .frame(width: controlDiameter, height: controlDiameter)
                .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion,
                    diameter: controlDiameter
                )
            )
            .accessibilityLabel(
                player.isPlaying
                    ? L10n.string("ui.player.pause")
                    : L10n.string("ui.common.play")
            )

            Spacer(minLength: isTablet ? 0 : nil)

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: isTablet ? 24 : 34, weight: .medium))
                    .frame(width: controlDiameter, height: controlDiameter)
                    .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion,
                    diameter: controlDiameter
                )
            )
            .accessibilityLabel("ui.player.next")

            Spacer(minLength: isTablet ? 0 : nil)

            if isTablet {
                Button(action: player.cycleRepeatMode) {
                    Image(systemName: player.repeatMode.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.58) : .red)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.repeatMode.accessibilityTitle)
                .accessibilityAddTraits(player.repeatMode == .off ? [] : .isSelected)
            }
        }
        .frame(height: isTablet ? 52 : 82)
    }
}

struct NowPlayingReferenceVolumeControl: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    @ViewBuilder
    var body: some View {
        if settings.playerVolumeControlMode != .hidden {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)

                volumeSlider
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .frame(height: 32)
                    .contentShape(NowPlayingVerticalHitShape(minimumHeight: 44))
                    .layoutPriority(1)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.62))
            .frame(height: 42)
        }
    }

    @ViewBuilder
    private var volumeSlider: some View {
        switch settings.playerVolumeControlMode {
        case .hidden:
            EmptyView()
        case .independent:
            Slider(
                value: Binding(
                    get: { player.volume },
                    set: { player.setVolume($0) }
                ),
                in: 0...1
            )
            .tint(.white)
            .accessibilityLabel("ui.player.volume")
        case .system:
            NowPlayingReferenceSystemVolumeSlider()
                .accessibilityLabel("ui.player.system_volume")
        }
    }
}

