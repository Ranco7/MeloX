import Foundation

enum PlayerVolumeControlMode: String, CaseIterable, Identifiable {
    case hidden
    case independent
    case system

    static let defaultMode: Self = .system

    static func resolved(storedValue: String?) -> Self {
        storedValue.flatMap(Self.init(rawValue:)) ?? defaultMode
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hidden: L10n.string("ui.settings.volume_control.hidden")
        case .independent: L10n.string("ui.settings.volume_control.independent")
        case .system: L10n.string("ui.settings.volume_control.system")
        }
    }

    var description: String {
        switch self {
        case .hidden:
            L10n.string("ui.settings.volume_control.hidden.detail")
        case .independent:
            L10n.string("ui.settings.volume_control.independent.detail")
        case .system:
            L10n.string("ui.settings.volume_control.system.detail")
        }
    }
}
