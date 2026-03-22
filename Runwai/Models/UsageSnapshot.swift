import Foundation

struct UsageSnapshot: Codable, Equatable {
    var weeklyBudgetUnits: Double
    var usedUnits: Double
    var windowDuration: TimeInterval
    var resetAt: Date
    var lastUpdatedAt: Date

    static func placeholder(
        provider: UsageProvider = .codex,
        now: Date = Date()
    ) -> UsageSnapshot {
        let resetAt = now.addingTimeInterval(provider.defaultWindowDuration)
        return UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: 0,
            windowDuration: provider.defaultWindowDuration,
            resetAt: resetAt,
            lastUpdatedAt: now
        )
    }

    static func sample(
        provider: UsageProvider = .codex,
        now: Date = Date()
    ) -> UsageSnapshot {
        let resetAt: Date
        let usedUnits: Double

        switch provider {
        case .codex:
            resetAt = Calendar.current.date(byAdding: .day, value: 4, to: now) ?? now.addingTimeInterval(4 * 86_400)
            usedUnits = 35
        case .codexSpark:
            resetAt = Calendar.current.date(byAdding: .day, value: 5, to: now) ?? now.addingTimeInterval(5 * 86_400)
            usedUnits = 12
        case .gemini:
            resetAt = Calendar.current.date(byAdding: .hour, value: 10, to: now) ?? now.addingTimeInterval(10 * 3_600)
            usedUnits = 28
        }

        return UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: usedUnits,
            windowDuration: provider.defaultWindowDuration,
            resetAt: resetAt,
            lastUpdatedAt: now
        )
    }
}
