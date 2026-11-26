import SwiftUI

struct DesktopCollectionPaginationFooter: View {
    let isLoading: Bool
    let failureMessage: String?
    var loadToken: Int? = nil
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

                    Button("ui.common.retry") {
                        Task {
                            await action()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loadingTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("ui.common.loading_more", systemImage: "arrow.down.circle") {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .onAppear {
            requestPageIfNeeded()
        }
        .onChange(of: loadToken) { _, _ in
            requestPageIfNeeded()
        }
        // A page publishes its new offset before it stops loading, so the
        // token can arrive while `isLoading` is still true. Ask again once
        // loading settles instead of waiting for a token that never changes.
        .onChange(of: isLoading) { _, isLoading in
            guard !isLoading else { return }
            requestPageIfNeeded()
        }
    }

    private func requestPageIfNeeded() {
        guard loadToken != nil,
              requestGate.shouldRequest(
                  token: loadToken,
                  isLoading: isLoading,
                  hasFailure: failureMessage != nil
              ) else { return }
        Task { await action() }
    }
}
