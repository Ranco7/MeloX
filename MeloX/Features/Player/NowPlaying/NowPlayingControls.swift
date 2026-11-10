import AVKit
import MediaPlayer
import SwiftUI

struct NowPlayingProgressControl: View {
    @Environment(PlayerStore.self) private var player

    let song: Song

    var usesCompactTimeRow = false
    var usesReferenceLayout = false

    var body: some View {
        if usesCompactTimeRow {
            // Time labels are passive: they can share the bottom of the
            // slider's 44pt hit region without overlapping another action.
            VStack(spacing: -8) {
                NowPlayingProgressSlider(maximum: progressMaximum)
                    .frame(height: 44)
                timeRow
                    .allowsHitTesting(false)
            }
            .frame(minHeight: NowPlayingPortraitLayout.baseProgressHeight)
        } else {
            VStack(spacing: 6) {
                Group {
                    if usesReferenceLayout {
                        NowPlayingProgressSlider(maximum: progressMaximum)
                            .contentShape(NowPlayingVerticalHitShape(minimumHeight: 44, maximumBottomOutset: 6))
                    } else {
                        NowPlayingProgressSlider(maximum: progressMaximum)
                    }
                }
                HStack(spacing: 10) {
                    NowPlayingProgressElapsedTime()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if usesReferenceLayout {
                            Group {
                                if player.isAutoMixTransitioning {
                                    NowPlayingAutoMixStatus()
                                } else {
                                    NowPlayingQualityMenu()
                                }
                            }
                            .animation(.smooth(duration: 0.25), value: player.isAutoMixTransitioning)
                        } else {
                            NowPlayingQualityControl()
                        }
                    }
                    .layoutPriority(1)
                    NowPlayingProgressRemainingTime()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var timeRow: some View {
        HStack {
            NowPlayingProgressElapsedTime()
            Spacer(minLength: 8)
            NowPlayingProgressRemainingTime()
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white.opacity(0.64))
    }

    private var progressMaximum: TimeInterval {
        max(player.duration, TimeInterval(song.durationMS) / 1_000, 1)
    }
}

/// Portrait shares this action with the existing top chrome. Other player
/// arrangements retain their quality/time row.
struct NowPlayingQualityControl: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        Group {
            if player.isAutoMixTransitioning {
                NowPlayingAutoMixStatus()
            } else {
                NowPlayingQualityMenu()
            }
        }
        .font(.caption2)
        .frame(minWidth: 44, minHeight: 44)
        .animation(.smooth(duration: 0.25), value: player.isAutoMixTransitioning)
    }
}

/// Keeps the ten-times-per-second progress reads in leaf views so the AutoMix
/// status and quality menu do not rebuild on every clock tick.
private struct NowPlayingProgressSlider: View {
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
        .tint(.white)
        .accessibilityLabel("ui.player.progress")
        .accessibilityValue(
            L10n.format(
                "ui.player.progress_accessibility",
                formatPlaybackTime(player.progress),
                formatPlaybackTime(maximum)
            )
        )
    }
}

private struct NowPlayingProgressElapsedTime: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        Text(formatPlaybackTime(player.progress))
            .lineLimit(1)
    }
}

private struct NowPlayingProgressRemainingTime: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        Text(
            "−\(formatPlaybackTime(max(player.duration - player.progress, 0)))"
        )
        .lineLimit(1)
    }
}

private func formatPlaybackTime(_ value: TimeInterval) -> String {
    guard value.isFinite else { return "0:00" }
    let seconds = max(0, Int(value))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

private struct NowPlayingAutoMixStatus: View {
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

private struct NowPlayingQualityMenu: View {
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

struct NowPlayingTransportControls: View {
    enum Presentation {
        case standard
        case tablet
        case referenceTablet
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var presentation: Presentation = .standard
    var rowHeight: CGFloat? = nil
    var availableWidth: CGFloat? = nil

    private var isTablet: Bool { presentation != .standard }
    private var isReference: Bool { presentation == .referenceTablet }
    private var controlDiameter: CGFloat {
        if isReference { return 44 }
        return isTablet ? min(64, max(rowHeight ?? 64, 44), max(44, ((availableWidth ?? 320) - 88) / 3))
            : min(64, max(rowHeight ?? 64, 44))
    }

    private var skipSymbolSize: CGFloat {
        isReference ? 24 : NowPlayingPortraitLayout.skipSymbolSize(controlDiameter: controlDiameter)
    }

    private var playSymbolSize: CGFloat {
        isReference ? 30 : NowPlayingPortraitLayout.playSymbolSize(
            controlDiameter: controlDiameter,
            isTablet: isTablet
        )
    }

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
                    .font(.system(size: skipSymbolSize, weight: .medium))
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
                            .font(.system(size: playSymbolSize, weight: .medium))
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
                    .font(.system(size: skipSymbolSize, weight: .medium))
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
        .frame(height: isReference ? 52 : max(rowHeight ?? (isTablet ? 64 : 82), controlDiameter))
    }
}

struct NowPlayingVolumeControl: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    var usesReferenceLayout = false

    @ViewBuilder
    var body: some View {
        if settings.playerVolumeControlMode != .hidden {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)

                volumeSlider
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .frame(height: usesReferenceLayout ? 32 : 44)
                    .contentShape(NowPlayingVerticalHitShape(minimumHeight: 44))
                    .layoutPriority(1)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.62))
            .frame(height: usesReferenceLayout ? 42 : 44)
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
            SystemVolumeSlider(usesReferenceLayout: usesReferenceLayout)
                .accessibilityLabel("ui.player.system_volume")
        }
    }
}

private final class AlignedSystemVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        bounds
    }
}

/// Keep native drawing geometry independent of the outer touch target.
/// SwiftUI owns the host size; only the child receives the native frame.
private final class SystemVolumeHostView: UIView {
    private let volumeView = AlignedSystemVolumeView(
        frame: CGRect(x: 0, y: 0, width: 200, height: 32)
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(volumeView)
        volumeView.frame = NowPlayingVolumeGeometry.nativeFrame(in: bounds)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(usesReferenceLayout: Bool = false) {
        volumeView.backgroundColor = .clear
        volumeView.showsVolumeSlider = true
        volumeView.showsRouteButton = usesReferenceLayout
        volumeView.tintColor = .white
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        volumeView.frame = NowPlayingVolumeGeometry.nativeFrame(in: bounds)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled,
              self.point(inside: point, with: event) else { return nil }
        // Forward the 6pt top/bottom padding to the native slider using public
        // hit testing, without inspecting MPVolumeView's private subviews.
        let nativePoint = NowPlayingVolumeGeometry.nativeHitPoint(point, frame: volumeView.frame)
        return volumeView.hitTest(nativePoint, with: event) ?? self
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {
    var usesReferenceLayout = false

    func makeUIView(context: Context) -> SystemVolumeHostView {
        let view = SystemVolumeHostView(frame: CGRect(origin: .zero, size: NowPlayingVolumeGeometry.size(proposedWidth: nil)))
        view.configure(usesReferenceLayout: usesReferenceLayout)
        return view
    }

    func updateUIView(_ volumeView: SystemVolumeHostView, context: Context) {
        volumeView.configure(usesReferenceLayout: usesReferenceLayout)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: SystemVolumeHostView,
        context: Context
    ) -> CGSize? {
        NowPlayingVolumeGeometry.size(proposedWidth: proposal.width)
    }
}

struct NowPlayingPageSelector: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    @Binding var page: NowPlayingPage
    var rowHeight: CGFloat = 50

    var body: some View {
        Group {
            if player.currentSong?.isPodcastProgram == true {
                HStack {
                    Spacer()

                    pageButton(
                        page: .queue,
                        systemImage: "list.bullet",
                        accessibilityLabel: L10n.string("ui.player.queue"),
                        badgeSystemImage:
                            page == .queue
                                ? nil
                                : player.queueModeBadgeSystemImage
                    )

                    Spacer()
                }
            } else {
                HStack {
                    pageButton(
                        page: .lyrics,
                        systemImage: "quote.bubble",
                        accessibilityLabel: L10n.string("ui.settings.lyrics.title")
                    )

                    Spacer()

                    NowPlayingAirPlayControl()

                    Spacer()

                    pageButton(
                        page: .queue,
                        systemImage: "list.bullet",
                        accessibilityLabel: L10n.string("ui.player.queue"),
                        badgeSystemImage:
                            page == .queue
                                ? nil
                                : player.queueModeBadgeSystemImage
                    )
                }
            }
        }
        .padding(.horizontal, 32)
        .foregroundStyle(.white.opacity(0.72))
        .frame(height: max(rowHeight, 44))
    }

    private func pageButton(
        page destination: NowPlayingPage,
        systemImage: String,
        accessibilityLabel: String,
        badgeSystemImage: String? = nil
    ) -> some View {
        let isSelected = page == destination

        return Button {
            let targetPage: NowPlayingPage =
                isSelected ? .artwork : destination
            withAnimation(
                accessibilityReduceMotion
                    ? nil
                    : NowPlayingPageTransition
                        .selectionAnimation(
                            from: page,
                            to: targetPage
                        )
            ) {
                page = targetPage
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(
                        isSelected
                            ? .black.opacity(0.68)
                            : .white.opacity(0.72)
                    )
                    .background(
                        .white.opacity(isSelected ? 0.68 : 0),
                        in: .circle
                    )

                if let badgeSystemImage {
                    Image(systemName: badgeSystemImage)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(
                            isSelected
                                ? .white.opacity(0.9)
                                : .black.opacity(0.74)
                        )
                        .frame(width: 15, height: 15)
                        .background(
                            isSelected
                                ? .black.opacity(0.58)
                                : .white.opacity(0.82),
                            in: .circle
                        )
                        .offset(x: 3, y: 1)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct NowPlayingAirPlayControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white.withAlphaComponent(0.72)
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AVRoutePickerView, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }
}

/// Enlarge only vertical hit geometry, leaving baseline visible bounds intact.
struct NowPlayingVerticalHitShape: Shape {
    var minimumHeight: CGFloat = 0
    var maximumBottomOutset: CGFloat = .infinity

    func path(in rect: CGRect) -> Path {
        let growth = max(minimumHeight - rect.height, 0)
        let top = growth - min(growth / 2, maximumBottomOutset)
        return Path(CGRect(x: rect.minX, y: rect.minY - top,
                           width: rect.width, height: rect.height + growth))
    }
}

/// Keep the current 32pt native drawing / 44pt hit host behind the old volume
/// view without changing that view's visible row, bindings or route behavior.
struct NowPlayingReferenceSystemVolumeSlider: View {
    var body: some View {
        SystemVolumeSlider(usesReferenceLayout: true)
    }
}
