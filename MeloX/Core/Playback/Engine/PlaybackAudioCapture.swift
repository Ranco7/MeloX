@preconcurrency import AVFoundation
import Foundation

/// The existing mixer tap supplies borrowed PCM buffers. Delivery stays on the
/// audio thread; stopping drains delivery before the receiver is released.
nonisolated final class PlaybackAudioCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var activeSource: UUID?
    private var subscription: UUID?
    private var receiver: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func start(receiver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> UUID? {
        lock.withLock {
            guard subscription == nil else { return nil }
            let token = UUID()
            subscription = token
            self.receiver = receiver
            return token
        }
    }

    func stop(_ token: UUID) {
        lock.withLock {
            guard subscription == token else { return }
            subscription = nil
            receiver = nil
        }
    }

    func select(source: UUID?) {
        lock.withLock { activeSource = source }
    }

    func append(_ buffer: AVAudioPCMBuffer, from source: UUID) {
        lock.withLock {
            guard activeSource == source else { return }
            receiver?(buffer)
        }
    }
}
