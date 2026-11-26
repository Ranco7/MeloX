import SwiftUI

struct MusicCollectionPaginationFooter: View {
    let isLoading: Bool
    let failureMessage: String?
    let loadToken: Int
    var loadingTitle = L10n.string("ui.common.loading_more_songs")
    let action: () async -> Void

    @State private var requestGate = MusicCollectionPageRequestGate()

    var body: some View {
        Group {
            if let failureMessage {
                VStack(spacing: 8) {
                    Text(failureMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("ui.common.reload") {
                        Task {
                            await action()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(loadingTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .task(id: loadToken) {
                    await requestPage()
                }
                // A page publishes its new offset before it stops loading, so
                // this footer can rebuild with a fresh token while the previous
                // request is still in flight. `.task(id:)` runs once per token,
                // so retry when loading settles rather than spinning forever on
                // a page that was never requested.
                .onChange(of: isLoading) { _, loading in
                    guard !loading else { return }
                    Task { await requestPage() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func requestPage() async {
        guard requestGate.shouldRequest(
            token: loadToken,
            isLoading: isLoading,
            hasFailure: failureMessage != nil
        ) else { return }
        await action()
    }
}
