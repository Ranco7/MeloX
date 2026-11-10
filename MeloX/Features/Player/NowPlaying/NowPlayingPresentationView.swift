import Observation
import SwiftUI

/// Owns the card's high-frequency motion, gesture and background-extension
/// state. `NowPlayingView` is built once by `NowPlayingPresentationView` and
/// handed to the presentation modifier, so per-frame offset/radius changes
/// never reconstruct the full player tree.
@Observable
final class NowPlayingCardModel {
    static let openingSpring = LyricPhysicalSpringParameters(mass: 1, stiffness: 329, damping: 36.2)
    static let closingSpring = LyricPhysicalSpringParameters(mass: 1, stiffness: 329, damping: 28.9)
    static let opening = NowPlayingAnimationSpec(
        .interpolatingSpring(
            mass: openingSpring.mass,
            stiffness: openingSpring.stiffness,
            damping: openingSpring.damping,
            initialVelocity: 0
        ),
        duration: 0.56
    )

    private(set) var motion: NowPlayingInterruptibleSpringProgress
    private(set) var dragOrigin: Double?
    private(set) var dragProgress: Double = 0
    private(set) var hasStarted = false
    private(set) var isVisible = false
    private(set) var isDismissing = false

    let reducesMotion: Bool
    @ObservationIgnored private let onDismiss: () -> Void

    init(reducesMotion: Bool, onDismiss: @escaping () -> Void) {
        self.reducesMotion = reducesMotion
        self.onDismiss = onDismiss
        motion = .settled(at: 1, animationSpec: Self.opening, now: .now)
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        guard !isDismissing else { return }
        if reducesMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = true
            }
        } else {
            motion = motion.retargeted(
                to: 0, animationSpec: Self.opening, now: .now
            )
        }
    }

    func beginDrag(height: CGFloat) {
        guard !isDismissing else { return }
        // Grab the current spring position, including an entrance or snap-back.
        let current = reducesMotion ? 0 : motion.presentation(at: .now).progress
        dragOrigin = current
        dragProgress = current
        motion = motion.settled(at: current, now: .now)

    }

    func updateDrag(translation: CGFloat, height: CGFloat) {
        guard let origin = dragOrigin, !isDismissing else { return }
        dragProgress = NowPlayingPresentationDrag.progress(
            origin: origin, translation: Double(translation), height: Double(height)
        )

    }

    func endDrag(translation: CGFloat, velocity: CGFloat, height: CGFloat, cancelled: Bool) {
        guard let origin = dragOrigin, !isDismissing else { return }
        updateDrag(translation: translation, height: height)
        let progress = dragProgress
        dragOrigin = nil
        let dismisses = !cancelled && NowPlayingPresentationDrag.shouldDismiss(
            progress: progress, velocity: Double(velocity), height: Double(height)
        )
        // Hand the spring the card's visible velocity: upward travel is damped
        // by the rubber band, downward travel remains 1:1.
        let scale = NowPlayingPresentationDrag.velocityScale(
            origin: origin, translation: Double(translation), height: Double(height)
        )
        let speed = cancelled ? 0 : Double(velocity) / max(Double(height), 1) * scale
        if dismisses {
            collapse(velocity: speed, from: progress)
        } else if !reducesMotion {
            animate(to: 0, from: progress, velocity: speed)
        }
    }

    func collapse() {
        collapse(velocity: nil, from: nil)
    }

    /// Called by the presentation modifier after the spring's settlement
    /// horizon. Keeping it here means the settle task never needs to capture
    /// transient view values.
    func settle(requestID: UUID) {
        guard motion.id == requestID, motion.isAnimating else { return }
        motion = motion.settled(at: motion.targetProgress, now: .now)

        if isDismissing {
            onDismiss()
        }
    }

    private func collapse(velocity: Double?, from progress: Double?) {
        guard !isDismissing else { return }
        let current = progress ?? currentProgress()
        isDismissing = true
        dragOrigin = nil
        if reducesMotion {

            withAnimation(.easeInOut(duration: 0.2), completionCriteria: .removed) {
                isVisible = false
            } completion: {
                self.onDismiss()
            }
        } else {
            animate(to: max(1, current), from: current, velocity: velocity)
        }
    }

    private func currentProgress() -> Double {
        dragOrigin == nil ? motion.presentation(at: .now).progress : dragProgress
    }

    private func animate(to target: Double, from progress: Double, velocity: Double?) {
        guard abs(target - progress) > 0.000_001 else {
            motion = motion.settled(at: target, now: .now)

            if isDismissing {
                onDismiss()
            }
            return
        }
        let speed = velocity ?? motion.presentation(at: .now).velocity
        let parameters = isDismissing ? Self.closingSpring : Self.openingSpring
        let solver = Spring(
            mass: parameters.mass, stiffness: parameters.stiffness,
            damping: parameters.damping, allowOverDamping: true
        )
        let duration = solver.settlingDuration(
            fromValue: progress, toValue: target, initialVelocity: speed, epsilon: 0.001
        )
        // This fitted dismissal spring crosses the bottom within 0.29s. Do not
        // leave an invisible modal blocking the page while it settles offscreen.
        let settlement = duration.isFinite ? max(duration, 0) : 0.56
        motion = NowPlayingInterruptibleSpringProgress(
            id: UUID(), startProgress: progress, targetProgress: target,
            initialVelocity: speed, startedAt: .now,
            settlementDuration: isDismissing ? min(settlement, 0.3) : settlement,
            spring: parameters
        )
    }

}

/// A transparent cover keeps sheets and system chrome scoped to the player.
/// Only the card moves; neither the page underneath nor the artwork is scaled.
struct NowPlayingPresentationView: View {
    let initialPage: NowPlayingPage
    // Keep the presentation style stable if accessibility settings change mid-drag.
    let reducesMotion: Bool
    let dismissalRequested: Bool
    let onDismiss: () -> Void

    @State private var model: NowPlayingCardModel

    init(
        initialPage: NowPlayingPage,
        reducesMotion: Bool,
        dismissalRequested: Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.initialPage = initialPage
        self.reducesMotion = reducesMotion
        self.dismissalRequested = dismissalRequested
        self.onDismiss = onDismiss
        _model = State(
            initialValue: NowPlayingCardModel(
                reducesMotion: reducesMotion,
                onDismiss: onDismiss
            )
        )
    }

    var body: some View {
        // The player content is constructed here, outside every high-frequency
        // closure. The modifier owns all motion state and transforms this value.
        NowPlayingView(
            initialPage: initialPage,
            onDismiss: { model.collapse() }
        )
        .modifier(
            NowPlayingCardPresentationModifier(
                model: model,
                dismissalRequested: dismissalRequested
            )
        )
    }
}

private struct NowPlayingCardPresentationModifier: ViewModifier {
    let model: NowPlayingCardModel
    let dismissalRequested: Bool

    func body(content: Content) -> some View {
        let motion = model.motion
        let dragOrigin = model.dragOrigin
        let dragProgress = model.dragProgress
        let reducesMotion = model.reducesMotion
        let isVisible = model.isVisible
        let isDismissing = model.isDismissing

        return GeometryReader { safeArea in
            GeometryReader { window in
                TimelineView(
                    .animation(
                        paused: reducesMotion || !motion.isAnimating
                    )
                ) { _ in
                    let progress = dragOrigin == nil
                        ? motion.presentation(at: .now).progress : dragProgress
                    let offset = reducesMotion ? 0 : CGFloat(progress) * window.size.height
                    // Upward travel is rubber-banded, so the card can rise above
                    // the top edge. Continue only its background below the bottom
                    // edge; the content and artwork keep their layout size.
                    let overhang = max(0, -offset)
                    let radius = reducesMotion
                        ? 0
                        : CGFloat(
                            NowPlayingPresentationDrag.topCornerRadius(
                                offset: Double(offset), height: Double(window.size.height)
                            )
                        )

                    content
                        .environment(\.nowPlayingBackgroundExtension, overhang)
                        // Restore actual insets without resizing content or artwork.
                        .safeAreaPadding(safeArea.safeAreaInsets)
                        .frame(width: window.size.width, height: window.size.height)
                        .frame(
                            width: window.size.width,
                            height: window.size.height + overhang,
                            alignment: .top
                        )
                        .clipShape(
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: radius, bottomLeading: 0,
                                    bottomTrailing: 0, topTrailing: radius
                                ),
                                style: .continuous
                            )
                        )
                        .offset(y: offset)
                        .opacity(reducesMotion && !isVisible ? 0 : 1)
                        .gesture(
                            NowPlayingDismissGesture(
                                isEnabled: !isDismissing,
                                onBegan: {
                                    model.beginDrag(
                                        height: window.size.height
                                    )
                                },
                                onChanged: { translation in
                                    model.updateDrag(
                                        translation: translation,
                                        height: window.size.height
                                    )
                                },
                                onEnded: { translation, velocity, cancelled in
                                    model.endDrag(
                                        translation: translation,
                                        velocity: velocity,
                                        height: window.size.height,
                                        cancelled: cancelled
                                    )
                                }
                            )
                        )
                }
            }
            .ignoresSafeArea(.container)
            .task {
                model.startIfNeeded()
            }
            .task(id: motion.id) {
                guard !reducesMotion, motion.isAnimating else { return }
                let requestID = motion.id
                do {
                    try await Task.sleep(
                        for: .seconds(motion.remainingDuration(at: .now))
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                model.settle(requestID: requestID)
            }
            .onChange(of: dismissalRequested, initial: true) { _, requested in
                if requested {
                    model.collapse()
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .accessibilityAction(.escape) {
            model.collapse()
        }
    }
}

// Only the background leaf reads this value; the player content does not.
extension EnvironmentValues {
    @Entry var nowPlayingBackgroundExtension: CGFloat = 0
}
