import Foundation

/// Decides when a pagination footer should ask its owner for the next page.
///
/// A page publishes its new offset before it stops loading, and those two
/// mutations are separated by a suspension point (persisting the page). The
/// footer can therefore observe a fresh token while `isLoading` is still true.
/// Gating on `isLoading` alone while asking once per token drops that page
/// permanently and leaves the footer spinning. Remembering the last requested
/// token lets the footer retry once loading settles, without looping.
struct MusicCollectionPageRequestGate {
    private var requestedToken: Int?

    mutating func shouldRequest(
        token: Int?,
        isLoading: Bool,
        hasFailure: Bool
    ) -> Bool {
        guard let token,
              !isLoading,
              !hasFailure,
              requestedToken != token else {
            return false
        }
        requestedToken = token
        return true
    }

    mutating func reset() {
        requestedToken = nil
    }
}
