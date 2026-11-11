import SwiftUI
import UIKit

/// Transient status only; never changes content geometry or blocks playback.
struct FavoriteFailureFeedback: ViewModifier {
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if library.favoriteFailureID != nil {
                    Text("ui.library.favorite_sync_failed")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: 360)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .task(id: library.favoriteFailureID) {
                guard let id = library.favoriteFailureID else { return }
                UIAccessibility.post(notification: .announcement, argument: L10n.string("ui.library.favorite_sync_failed"))
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                library.dismissFavoriteFailure(id)
            }
    }
}
