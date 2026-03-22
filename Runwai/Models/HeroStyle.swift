import Foundation

enum HeroStyle: String, Codable, CaseIterable, Identifiable {
    case remainingFirst
    case timeFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .remainingFirst:
            return "Left First"
        case .timeFirst:
            return "Time First"
        }
    }

    var description: String {
        switch self {
        case .remainingFirst:
            return "Keep the remaining percentage as the main hero and show time left as the secondary metric."
        case .timeFirst:
            return "Make time left the main hero and show remaining percentage as the secondary metric."
        }
    }
}
