import SwiftUI

/// A transparent cover keeps sheets and system chrome scoped to the player.
/// Only the card moves; neither the page underneath nor the artwork is scaled.
struct NowPlayingPresentationView: View {
    // Fitted against the original recording's timestamps, at 1408 x 970 points.
    private static let openingSpring = LyricPhysicalSpringParameters(mass: 1, stiffness: 329, damping: 36.2)
    private static let closingSpring = LyricPhysicalSpringParameters(mass: 1, stiffness: 329, damping: 28.9)
    private static let opening = NowPlayingAnimationSpec(
        .interpolatingSpring(
            mass: openingSpring.mass, stiffness: openingSpring.stiffness,
            damping: openingSpring.damping, initialVelocity: 0
        ),
        duration: 0.56
    )

    let initialPage: NowPlayingPage
    // Keep the presentation style stable if accessibility settings change mid-drag.
    let reducesMotion: Bool
    let dismissalRequested: Bool
    let onDismiss: () -> Void

    @State private var motion = NowPlayingInterruptibleSpringProgress.settled(
        at: 1, animationSpec: NowPlayingPresentationView.opening, now: .now
    )
    @State private var dragOrigin: Double?
    @State private var dragProgress: Double = 0
    @State private var hasStarted = false
    @State private var isVisible = false
    @State private var isDismissing = false

    var body: some View {
        GeometryReader { safeArea in
            GeometryReader { window in
                TimelineView(.animation(paused: !motion.isAnimating || reducesMotion)) { _ in
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

                    NowPlayingView(
                        initialPage: initialPage,
                        backgroundExtension: overhang,
                        onDismiss: collapse
                    )
                    // Restore actual insets without resizing content or artwork.
                    .safeAreaPadding(safeArea.safeAreaInsets)
                    .frame(width: window.size.width, height: window.size.height)
                    .frame(width: window.size.width, height: window.size.height + overhang, alignment: .top)
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
                            onBegan: beginDrag,
                            onChanged: { translation in
                                updateDrag(translation: translation, height: window.size.height)
                            },
                            onEnded: { translation, velocity, cancelled in
                                endDrag(
                                    translation: translation, velocity: velocity,
                                    height: window.size.height, cancelled: cancelled
                                )
                            }
                        )
                    )
                }
            }
            .ignoresSafeArea(.container)
        }
        .ignoresSafeArea(.keyboard)
        .accessibilityAction(.escape, collapse)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            guard !isDismissing else { return }
            if reducesMotion {
                withAnimation(.easeInOut(duration: 0.2)) { isVisible = true }
            } else {
                motion = motion.retargeted(to: 0, animationSpec: Self.opening, now: .now)
            }
        }
        .task(id: motion.id) {
            guard !reducesMotion, motion.isAnimating else { return }
            let requestID = motion.id
            do {
                try await Task.sleep(for: .seconds(motion.remainingDuration(at: .now)))
            } catch {
                return
            }
            guard !Task.isCancelled, motion.id == requestID else { return }
            motion = motion.settled(at: motion.targetProgress, now: .now)
            if isDismissing { onDismiss() }
        }
        .onChange(of: dismissalRequested, initial: true) { _, requested in
            if requested { collapse() }
        }
    }

    private func beginDrag() {
        guard !isDismissing else { return }
        // Grab the current spring position, including during an entrance or snap-back.
        let current = reducesMotion ? 0 : motion.presentation(at: .now).progress
        dragOrigin = current
        dragProgress = current
        motion = motion.settled(at: current, now: .now)
    }

    private func updateDrag(translation: CGFloat, height: CGFloat) {
        guard let origin = dragOrigin, !isDismissing else { return }
        dragProgress = NowPlayingPresentationDrag.progress(
            origin: origin, translation: Double(translation), height: Double(height)
        )
    }

    private func endDrag(translation: CGFloat, velocity: CGFloat, height: CGFloat, cancelled: Bool) {
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

    private func collapse() {
        collapse(velocity: nil, from: nil)
    }

    private func collapse(velocity: Double?, from progress: Double?) {
        guard !isDismissing else { return }
        let current = progress ?? (dragOrigin == nil ? motion.presentation(at: .now).progress : dragProgress)
        isDismissing = true
        dragOrigin = nil
        if reducesMotion {
            withAnimation(.easeInOut(duration: 0.2), completionCriteria: .removed) {
                isVisible = false
            } completion: {
                onDismiss()
            }
        } else {
            animate(to: max(1, current), from: current, velocity: velocity)
        }
    }

    private func animate(to target: Double, from progress: Double, velocity: Double?) {
        guard abs(target - progress) > 0.000_001 else {
            motion = motion.settled(at: target, now: .now)
            if isDismissing { onDismiss() }
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
