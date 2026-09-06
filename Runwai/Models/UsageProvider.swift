import Foundation

enum UsageProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case codexSpark
    case gemini

    static let visibleProviders: [UsageProvider] = [.codex]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .codexSpark:
            return "Codex Spark"
        case .gemini:
            return "Gemini"
        }
    }

    var shortName: String {
        switch self {
        case .codex:
            return "codex"
        case .codexSpark:
            return "spark"
        case .gemini:
            return "gemini"
        }
    }

    var defaultWindowDuration: TimeInterval {
        switch self {
        case .codex, .codexSpark:
            return 7 * 24 * 60 * 60
        case .gemini:
            return 24 * 60 * 60
        }
    }

    var remainingLabel: String {
        switch self {
        case .codex, .codexSpark:
            return "weekly remaining"
        case .gemini:
            return "daily remaining"
        }
    }

    var usageLineLabel: String {
        switch self {
        case .codex, .codexSpark:
            return "Weekly usage window remaining"
        case .gemini:
            return "Current day remaining"
        }
    }

    var resetHint: String {
        switch self {
        case .codex:
            return "runwai can refresh Codex from your local Codex login on this Mac. If that falls behind, enter the weekly remaining percentage here."
        case .codexSpark:
            return "runwai can refresh Codex Spark from your local Codex login on this Mac. If that falls behind, enter the weekly remaining percentage here."
        case .gemini:
            return "Enter the remaining Gemini quota percentage for today and the next reset time."
        }
    }

    var launchURL: URL? {
        switch self {
        case .codex, .codexSpark:
            return URL(string: "https://chatgpt.com")
        case .gemini:
            return URL(string: "https://gemini.google.com")
        }
    }

    var launchActionLabel: String {
        switch self {
        case .codex, .codexSpark:
            return "Open ChatGPT"
        case .gemini:
            return "Open Gemini"
        }
    }

    var setupTitle: String {
        switch self {
        case .codex:
            return "Set up codex pacing"
        case .codexSpark:
            return "Set up codex spark pacing"
        case .gemini:
            return "Set up gemini pacing"
        }
    }

    var setupSummary: String {
        switch self {
        case .codex:
            return "runwai refreshes Codex from your local Codex login on this Mac, then uses local history to keep the weekly runway honest."
        case .codexSpark:
            return "runwai refreshes Codex Spark from your local Codex login on this Mac, then uses local history to keep the weekly Spark runway honest."
        case .gemini:
            return "runwai can read Gemini quota from your local Gemini CLI. If you prefer, you can still keep a manual daily snapshot."
        }
    }

    var setupSteps: [String] {
        switch self {
        case .codex:
            return [
                "Stay signed in to Codex on this Mac so runwai can read the live usage snapshot.",
                "runwai also keeps local history so it can show how much of today's weekly budget you already burned.",
                "If Codex auto-refresh falls behind, enter the remaining weekly percentage here as a manual fallback."
            ]
        case .codexSpark:
            return [
                "Stay signed in to Codex on this Mac so runwai can read the live Codex Spark usage snapshot.",
                "runwai reads the Spark 5-hour window and the Spark weekly runway from the same local Codex session.",
                "If Codex Spark auto-refresh falls behind, enter the remaining weekly percentage here as a manual fallback."
            ]
        case .gemini:
            return [
                "Use Gemini CLI on this Mac so runwai can see today's local quota.",
                "If auto-refresh is unavailable, enter the remaining percentage here.",
                "Keep the next reset time accurate whenever you fall back to manual."
            ]
        }
    }

    var quickUpdateHint: String {
        switch self {
        case .codex:
            return "If Codex looks behind, update the weekly remaining percentage here and runwai recalculates the rest."
        case .codexSpark:
            return "If Codex Spark looks behind, update the weekly remaining percentage here and runwai recalculates the rest."
        case .gemini:
            return "If Gemini CLI is unavailable, update the remaining percentage here and today's pacing refreshes instantly."
        }
    }

    var syncDescription: String {
        switch self {
        case .codex:
            return "Codex refreshes from your local Codex login on this Mac, with manual fallback."
        case .codexSpark:
            return "Codex Spark refreshes from your local Codex login on this Mac, with manual fallback."
        case .gemini:
            return "Gemini can refresh from your local Gemini CLI quota once a minute, or you can keep using a manual snapshot."
        }
    }

    var setupExample: String {
        switch self {
        case .codex:
            return "If OpenAI says 90% remaining, enter 90 here."
        case .codexSpark:
            return "If OpenAI says 98% Spark remaining, enter 98 here."
        case .gemini:
            return "If Gemini has about 75% of today's quota left, enter 75 here."
        }
    }

    var timeMetricUnit: TimeMetricUnit {
        switch self {
        case .codex, .codexSpark:
            return .days
        case .gemini:
            return .hours
        }
    }

    var rateUnit: RateMetricUnit {
        switch self {
        case .codex, .codexSpark:
            return .day
        case .gemini:
            return .hour
        }
    }

    var trackingScope: TrackingScope {
        switch self {
        case .codex, .codexSpark, .gemini:
            return .day
        }
    }

    var trackingSectionTitle: String {
        switch rateUnit {
        case .day:
            return "Today"
        case .hour:
            switch trackingScope {
            case .day:
                return "Pace today"
            case .window:
                return "Pace this window"
            }
        }
    }

    var windowLabel: String {
        switch self {
        case .codex, .codexSpark:
            return "weekly window"
        case .gemini:
            return "daily window"
        }
    }

    var usedTrackingLabel: String {
        switch trackingScope {
        case .day:
            return "burned today"
        case .window:
            return "burned this window"
        }
    }

    var remainingTrackingLabel: String {
        switch rateUnit {
        case .day:
            switch trackingScope {
            case .day:
                return "left today"
            case .window:
                return "safe room left in this window"
            }
        case .hour:
            switch trackingScope {
            case .day:
                return "under pace today"
            case .window:
                return "under pace in this window"
            }
        }
    }

    var availableSourceModes: [UsageSourceMode] {
        switch self {
        case .codex:
            return [.codexApp, .manual]
        case .codexSpark:
            return [.codexSparkApp, .manual]
        case .gemini:
            return [.geminiCLI, .manual]
        }
    }

    var defaultSourceMode: UsageSourceMode {
        availableSourceModes.first ?? .manual
    }
}

enum TimeMetricUnit {
    case days
    case hours
}

enum RateMetricUnit {
    case day
    case hour

    var displayLabel: String {
        switch self {
        case .day:
            return "safe to use per day"
        case .hour:
            return "safe to use per hour"
        }
    }
}

enum TrackingScope {
    case day
    case window
}
