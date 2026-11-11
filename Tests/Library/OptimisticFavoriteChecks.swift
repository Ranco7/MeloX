// Executes the production coordinator with manually completed network requests.
import Foundation

@MainActor
private final class FavoritesFixture {
    struct Request {
        let key: LibraryFavoriteKey
        let value: Bool
        let completion: CheckedContinuation<Void, Error>
    }
    enum Failure: Error { case offline }
    let actions = OptimisticFavoriteActions<LibraryFavoriteKey>()
    var visible: [LibraryFavoriteKey: Bool] = [:]
    var requests: [Request] = []
    var lastAppliedLabel = ""
    var failureCount = 0

    init() {
        actions.onFailure = { [weak self] _ in self?.failureCount += 1 }
    }

    func tap(_ key: LibraryFavoriteKey = .song(1), label: String = "initial") {
        actions.toggle(key, currentValue: visible[key] ?? false) { [weak self] value in
            self?.visible[key] = value
            self?.lastAppliedLabel = label
        } write: { [weak self] value in
            try await withCheckedThrowingContinuation { continuation in
                self?.requests.append(Request(key: key, value: value, completion: continuation))
            }
        }
    }

    func finish(_ index: Int, fails: Bool = false) {
        if fails { requests[index].completion.resume(throwing: Failure.offline) }
        else { requests[index].completion.resume() }
    }
}

@main
struct OptimisticFavoriteChecks {
    @MainActor
    static func main() async {
        let key = LibraryFavoriteKey.song(1)
        let quick = FavoritesFixture()
        quick.tap(); quick.tap(); quick.tap()
        precondition(quick.visible[key] == true, "Every tap must flip before yielding")
        await wait { quick.requests.count == 1 }
        precondition(quick.requests[0].value)
        quick.tap(label: "updated metadata"); quick.tap(label: "updated metadata")
        precondition(quick.lastAppliedLabel == "updated metadata", "New controls must supply the current item payload")
        let quickRevision = quick.actions.revision
        quick.finish(0)
        await wait { quick.actions.revision > quickRevision }
        precondition(quick.requests.count == 1 && quick.visible[key] == true)
        print("PASS: immediate flip and rapid-tap coalescing")

        let serial = FavoritesFixture()
        serial.tap()
        await wait { serial.requests.count == 1 }
        serial.tap()
        precondition(serial.visible[key] == false && serial.requests.count == 1)
        serial.finish(0)
        await wait { serial.requests.count == 2 }
        precondition(!serial.requests[1].value && serial.visible[key] == false)
        let serialRevision = serial.actions.revision
        serial.finish(1, fails: true)
        await wait { serial.actions.revision > serialRevision }
        precondition(serial.visible[key] == true, "Rollback to the last confirmed write")
        precondition(serial.failureCount == 1)
        print("PASS: one writer per item and rollback to confirmed state")

        let failure = FavoritesFixture()
        failure.tap()
        await wait { failure.requests.count == 1 }
        failure.tap()
        let failureRevision = failure.actions.revision
        failure.finish(0, fails: true)
        await wait { failure.actions.revision > failureRevision }
        precondition(failure.visible[key] == false && failure.requests.count == 1)
        precondition(failure.failureCount == 0, "An obsolete failure must not show an error")
        let single = FavoritesFixture()
        single.tap()
        await wait { single.requests.count == 1 }
        let singleRevision = single.actions.revision
        single.finish(0, fails: true)
        await wait { single.actions.revision > singleRevision }
        precondition(single.visible[key] == false && single.failureCount == 1)
        print("PASS: quiet failure and older failures respect newer intent")

        let readBeforeTap: UInt64 = 0
        precondition(quick.actions.resolvedValue(for: key, remoteValue: false, readRevision: readBeforeTap))
        precondition(quick.actions.resolvedValue(for: key, remoteValue: false, readRevision: quick.actions.revision))
        let readBeforeAcknowledgement = quick.actions.revision
        precondition(quick.actions.resolvedValue(for: key, remoteValue: true, readRevision: readBeforeAcknowledgement))
        precondition(quick.actions.resolvedValue(for: key, remoteValue: false, readRevision: readBeforeAcknowledgement),
                     "Acknowledgement must retain a revision tombstone for older reads")
        precondition(!quick.actions.resolvedValue(for: key, remoteValue: false, readRevision: quick.actions.revision),
                     "A later remote change may be accepted after acknowledgement")
        precondition(!quick.actions.resolvedValue(for: key, remoteValue: true, readRevision: readBeforeAcknowledgement))
        print("PASS: stale refresh, acknowledgement, and subsequent external changes")

        let independent = FavoritesFixture()
        independent.tap(.song(1)); independent.tap(.playlist(1))
        await wait { independent.requests.count == 2 }
        independent.visible = [:]
        independent.actions.reapply(where: { _ in true }, readRevision: 0) { _ in false }
        precondition(independent.visible[.song(1)] == true && independent.visible[.playlist(1)] == true)
        independent.finish(0); independent.finish(1)
        await wait { independent.actions.revision >= 4 }
        print("PASS: item types are independent and refresh overlays restore intent")

        let account = FavoritesFixture()
        account.tap()
        await wait { account.requests.count == 1 }
        account.actions.reset()
        account.visible = [:]
        account.tap()
        await wait { account.requests.count == 2 }
        account.finish(0, fails: true)
        let accountRevision = account.actions.revision
        account.finish(1)
        await wait { account.actions.revision > accountRevision }
        precondition(account.visible[key] == true)
        print("PASS: old account completions cannot roll back a new account")
    }

    @MainActor
    private static func wait(until condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("Coordinator did not reach the expected state")
    }
}
