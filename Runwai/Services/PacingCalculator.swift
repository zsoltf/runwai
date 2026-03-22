import Foundation

enum PaceStatus: Equatable {
    case ahead
    case onPace
    case behind
    case exhausted

    var displayText: String {
        switch self {
        case .ahead:
            return "Ahead of pace"
        case .onPace:
            return "On pace"
        case .behind:
            return "Behind pace"
        case .exhausted:
            return "Exhausted"
        }
    }
}

struct PacingSummary: Equatable {
    let remainingUnits: Double
    let usedUnits: Double
    let weeklyBudgetUnits: Double
    let usedFraction: Double
    let remainingFraction: Double
    let timeRemaining: TimeInterval
    let daysRemaining: Double
    let hoursRemaining: Double
    let safeUnitsPerDay: Double
    let safePercentPerDay: Double
    let safeUnitsPerHour: Double
    let safePercentPerHour: Double
    let expectedUsedUnits: Double
    let deltaFromExpected: Double
    let toleranceUnits: Double
    let status: PaceStatus
    let isStale: Bool

    var remainingPercent: Double {
        remainingFraction * 100
    }
}

enum PacingCalculator {
    static let minimumBudgetWindow: Double = 1.0 / 24.0
    static let minimumHourlyWindow: Double = 1.0 / 60.0
    static let staleThreshold: TimeInterval = 24 * 60 * 60

    static func evaluate(snapshot: UsageSnapshot, now: Date) -> PacingSummary {
        let budget = max(snapshot.weeklyBudgetUnits, 0)
        let used = max(snapshot.usedUnits, 0)
        let remainingUnits = max(budget - used, 0)
        let usedFraction = budget > 0 ? (used / budget).clamped(to: 0...1) : 0
        let remainingFraction = max(1 - usedFraction, 0)
        let timeRemaining = max(snapshot.resetAt.timeIntervalSince(now), 0)
        let daysRemaining = timeRemaining / 86_400
        let hoursRemaining = timeRemaining / 3_600
        let effectiveDaysRemaining = max(daysRemaining, minimumBudgetWindow)
        let effectiveHoursRemaining = max(hoursRemaining, minimumHourlyWindow)
        let safeUnitsPerDay = remainingUnits / effectiveDaysRemaining
        let safePercentPerDay = (remainingFraction * 100) / effectiveDaysRemaining
        let safeUnitsPerHour = remainingUnits / effectiveHoursRemaining
        let safePercentPerHour = (remainingFraction * 100) / effectiveHoursRemaining

        let windowDuration = max(snapshot.windowDuration, 1)
        let windowStart = snapshot.resetAt.addingTimeInterval(-windowDuration)
        let elapsedFraction = now.timeIntervalSince(windowStart) / windowDuration
        let clampedElapsedFraction = elapsedFraction.clamped(to: 0...1)
        let expectedUsedUnits = budget * clampedElapsedFraction
        let deltaFromExpected = used - expectedUsedUnits
        let tolerance = max(budget * 0.03, 1)

        let status: PaceStatus
        if remainingUnits == 0 {
            status = .exhausted
        } else if deltaFromExpected < -tolerance {
            status = .ahead
        } else if deltaFromExpected > tolerance {
            status = .behind
        } else {
            status = .onPace
        }

        let isStale = now.timeIntervalSince(snapshot.lastUpdatedAt) > staleThreshold

        return PacingSummary(
            remainingUnits: remainingUnits,
            usedUnits: used,
            weeklyBudgetUnits: budget,
            usedFraction: usedFraction,
            remainingFraction: remainingFraction,
            timeRemaining: timeRemaining,
            daysRemaining: daysRemaining,
            hoursRemaining: hoursRemaining,
            safeUnitsPerDay: safeUnitsPerDay,
            safePercentPerDay: safePercentPerDay,
            safeUnitsPerHour: safeUnitsPerHour,
            safePercentPerHour: safePercentPerHour,
            expectedUsedUnits: expectedUsedUnits,
            deltaFromExpected: deltaFromExpected,
            toleranceUnits: tolerance,
            status: status,
            isStale: isStale
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
