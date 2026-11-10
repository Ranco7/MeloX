import SwiftUI
import UIKit

/// Resolve the touched scroll view before either pan begins. This avoids a
/// simultaneous DragGesture moving the card while lyrics/queue are scrolling.
struct NowPlayingDismissGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        context.coordinator.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        // Do not disable an active recognizer while handling its end callback.
        context.coordinator.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(translation)
        case .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).y, false)
        case .cancelled, .failed:
            onEnded(translation, 0, true)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true
        private weak var touchedView: UIView?

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled else { return false }
            touchedView = touch.view
            var view = touch.view
            while let current = view {
                // Transport/volume controls, text selection and editing own their touches.
                if current is UIControl || current is UITextView || current is UITextField { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            let offsets = scrollViews.compactMap { scroll -> Double? in
                let inset = scroll.adjustedContentInset
                let isVertical = scroll.isScrollEnabled
                    && (scroll.alwaysBounceVertical
                        || scroll.contentSize.height + inset.top + inset.bottom > scroll.bounds.height + 1)
                return isVertical ? Double(scroll.contentOffset.y + inset.top) : nil
            }
            return NowPlayingPresentationDrag.canBegin(
                velocityX: Double(velocity.x), velocityY: Double(velocity.y), scrollOffsets: offsets
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The touched scroll pans wait for this direction/top-edge decision.
            // We never change a scroll delegate, content offset or enabled state.
            scrollViews.contains { $0.panGestureRecognizer === otherGestureRecognizer }
        }

        private var scrollViews: [UIScrollView] {
            var result: [UIScrollView] = []
            var view = touchedView
            while let current = view {
                if let scroll = current as? UIScrollView { result.append(scroll) }
                view = current.superview
            }
            return result
        }
    }
}
