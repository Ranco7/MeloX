import Foundation

/// One writer per item. New taps change the visible intent immediately and
/// coalesce while a request is in flight; an older failure cannot undo a tap.
@MainActor
final class OptimisticFavoriteActions<Key: Hashable> {
    private final class Action {
        var confirmed: Bool
        var desired: Bool
        var revision: UInt64
        var acknowledged = false
        var apply: (Bool) -> Void
        var write: (Bool) async throws -> Void
        var task: Task<Void, Never>?

        init(value: Bool, revision: UInt64, apply: @escaping (Bool) -> Void,
             write: @escaping (Bool) async throws -> Void) {
            confirmed = value
            desired = value
            self.revision = revision
            self.apply = apply
            self.write = write
        }
    }

    var onFailure: ((any Error) -> Void)?
    private(set) var revision: UInt64 = 0
    private var actions: [Key: Action] = [:]

    func toggle(_ key: Key, currentValue: Bool, apply: @escaping (Bool) -> Void,
                write: @escaping (Bool) async throws -> Void) {
        revision &+= 1
        let action = actions[key] ?? Action(value: currentValue, revision: revision, apply: apply, write: write)
        actions[key] = action
        action.apply = apply
        action.write = write
        action.revision = revision
        action.acknowledged = false
        action.desired.toggle()
        action.apply(action.desired)
        guard action.task == nil else { return }
        action.task = Task { [weak self] in
            guard let self else { return }
            await self.drain(key, action: action)
        }
    }

    /// A completed write stays protected until a later read acknowledges it.
    /// Retain the revision after acknowledgement so an older overlapping read
    /// cannot undo it. A later read can still report changes from other clients.
    func resolvedValue(for key: Key, remoteValue: Bool, readRevision: UInt64) -> Bool {
        guard let action = actions[key] else { return remoteValue }
        if action.task == nil, readRevision >= action.revision,
           remoteValue == action.desired || action.acknowledged {
            if !action.acknowledged || remoteValue != action.desired {
                revision &+= 1
                action.revision = revision
            }
            action.acknowledged = true
            action.confirmed = remoteValue
            action.desired = remoteValue
            return remoteValue
        }
        return action.desired
    }

    func reapply(where includes: (Key) -> Bool, readRevision: UInt64, remoteValue: (Key) -> Bool) {
        for (key, action) in Array(actions) where includes(key) {
            action.apply(resolvedValue(for: key, remoteValue: remoteValue(key), readRevision: readRevision))
        }
    }

    func reset() {
        for action in actions.values { action.task?.cancel() }
        actions.removeAll()
        revision &+= 1
    }

    private func drain(_ key: Key, action: Action) async {
        while actions[key] === action, !Task.isCancelled, action.confirmed != action.desired {
            let requested = action.desired
            do {
                try await action.write(requested)
                guard actions[key] === action else { return }
                action.confirmed = requested
            } catch {
                guard actions[key] === action else { return }
                if action.desired == requested {
                    action.desired = action.confirmed
                    action.apply(action.confirmed)
                    if !(error is CancellationError) { onFailure?(error) }
                }
            }
            revision &+= 1
            action.revision = revision
        }
        guard actions[key] === action else { return }
        action.task = nil
    }
}

nonisolated enum LibraryFavoriteKey: Hashable {
    case song(Int), playlist(Int), album(Int), artist(Int), podcast(Int)
}

nonisolated struct LibraryFavoriteRead {
    let cookie: String
    let revision: UInt64
    let accountGeneration: UUID
}
