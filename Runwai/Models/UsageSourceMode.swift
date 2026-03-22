import Foundation

enum UsageSourceMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case codexApp
    case codexSparkApp
    case geminiCLI
    case experimentalPrivateSync

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .codexApp:
            return "Codex app"
        case .codexSparkApp:
            return "Codex Spark"
        case .geminiCLI:
            return "Gemini CLI"
        case .experimentalPrivateSync:
            return "Experimental private sync"
        }
    }

    var badgeText: String {
        switch self {
        case .manual:
            return "Manual"
        case .codexApp:
            return "Auto"
        case .codexSparkApp:
            return "Auto"
        case .geminiCLI:
            return "Auto"
        case .experimentalPrivateSync:
            return "Experimental"
        }
    }

    var isImplementedInScaffold: Bool {
        switch self {
        case .manual:
            return true
        case .codexApp:
            return true
        case .codexSparkApp:
            return true
        case .geminiCLI:
            return true
        case .experimentalPrivateSync:
            return false
        }
    }

    var usesAutomaticRefresh: Bool {
        switch self {
        case .manual:
            return false
        case .codexApp:
            return true
        case .codexSparkApp:
            return true
        case .geminiCLI:
            return true
        case .experimentalPrivateSync:
            return false
        }
    }
}
