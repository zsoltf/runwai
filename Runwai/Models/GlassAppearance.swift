import Foundation

enum GlassAppearance: String, Codable, CaseIterable, Identifiable {
    case frosted
    case translucent
    case transparent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frosted:
            return "Frosted"
        case .translucent:
            return "Translucent"
        case .transparent:
            return "Transparent"
        }
    }

    var description: String {
        switch self {
        case .frosted:
            return "The strongest glass style, with the most fill and separation."
        case .translucent:
            return "Soft glass with visible background and clear separation around panels."
        case .transparent:
            return "Nearly clear, with only minimal panel separation to keep things readable."
        }
    }
}
