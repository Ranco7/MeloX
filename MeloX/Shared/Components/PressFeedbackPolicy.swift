import Foundation

nonisolated enum PressFeedbackPolicy {
    static let rowOpacity = 0.06
    static let lyricOpacity = 0.055
    static let rowCornerRadius = 10.0
    static let lyricCornerRadius = 12.0
    static let lyricInternalInset = 8.0
    static let releaseDuration = 0.16

    static func animationDuration(isActive: Bool, reducesMotion: Bool) -> Double {
        isActive || reducesMotion ? 0 : releaseDuration
    }
}
