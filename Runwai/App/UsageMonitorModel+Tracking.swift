import Foundation

extension UsageMonitorModel {
    var automaticSourceStaleThreshold: TimeInterval {
        switch selectedProvider {
        case .codex, .codexSpark:
            return 10 * 60
        case .gemini:
            return 3 * 60
        }
    }

    var targetRatePercent: Double {
        switch selectedProvider.rateUnit {
        case .day:
            return summary.safePercentPerDay
        case .hour:
            return summary.safePercentPerHour
        }
    }

    var nextBufferCapacityPercent: Double {
        switch selectedProvider.rateUnit {
        case .day:
            return max(summary.safePercentPerDay, 0.01)
        case .hour:
            return max(summary.safePercentPerHour, 0.01)
        }
    }

    var nextBufferRemainingPercent: Double {
        max(dailyAllowancePercent - dailyOveragePercent, 0)
    }

    func formattedNumber(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...1))
        )
    }

    var updatedShortLine: String {
        "updated \(relativeAgeShortString(from: snapshot.lastUpdatedAt))"
    }

    func relativeAgeShortString(from date: Date) -> String {
        let interval = max(now.timeIntervalSince(date), 0)

        if interval < 90 {
            return "just now"
        }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = Int(interval / 3_600)
        if hours < 24 {
            return "\(hours)h ago"
        }

        let days = Int(interval / 86_400)
        return "\(days)d ago"
    }

    var currentHistoryPoint: UsageHistoryPoint {
        UsageHistoryPoint(
            timestamp: snapshot.lastUpdatedAt,
            remainingPercent: remainingPercent(for: snapshot)
        )
    }

    var trackedHistoryPoints: [UsageHistoryPoint] {
        guard !isPlaceholderSnapshot else {
            return []
        }

        var points = history
            .filter { $0.timestamp <= snapshot.resetAt }
            .sorted { $0.timestamp < $1.timestamp }

        let currentPoint = currentHistoryPoint
        if points.isEmpty {
            points = [currentPoint]
        } else if
            let last = points.last,
            last.timestamp != currentPoint.timestamp || abs(last.remainingPercent - currentPoint.remainingPercent) > 0.05
        {
            points.append(currentPoint)
        }

        return points
    }

    var trackingStart: Date {
        switch selectedProvider.trackingScope {
        case .day:
            return Calendar.current.startOfDay(for: now)
        case .window:
            return windowStart
        }
    }

    var trackingBaselinePoint: UsageHistoryPoint? {
        guard !isPlaceholderSnapshot else {
            return nil
        }

        let points = trackedHistoryPoints

        if let lastBeforeStart = points.last(where: { $0.timestamp <= trackingStart }) {
            return UsageHistoryPoint(
                timestamp: trackingStart,
                remainingPercent: lastBeforeStart.remainingPercent
            )
        }

        return points.first(where: { $0.timestamp >= trackingStart })
    }

    var trackingBoundaryEnd: Date {
        switch selectedProvider.trackingScope {
        case .day:
            let dayEnd = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
            return min(dayEnd, snapshot.resetAt)
        case .window:
            return snapshot.resetAt
        }
    }

    var projectedStopInterval: TimeInterval? {
        guard
            !isPlaceholderSnapshot,
            !isTodayOverBudget,
            todayConsumedPercent > 0.05,
            todayRemainingAllowancePercent > 0.05,
            let baseline = trackingBaselinePoint
        else {
            return nil
        }

        let referenceStart = max(baseline.timestamp, trackingStart)
        let elapsed = now.timeIntervalSince(referenceStart)
        guard elapsed >= 15 * 60 else {
            return nil
        }

        let burnRate = todayConsumedPercent / elapsed
        guard burnRate > 0 else {
            return nil
        }

        return todayRemainingAllowancePercent / burnRate
    }

    var projectedStopAt: Date? {
        guard let projectedStopInterval else {
            return nil
        }

        return now.addingTimeInterval(projectedStopInterval)
    }

    var reachesTargetAfterBoundary: Bool {
        guard let projectedStopAt else {
            return false
        }

        return projectedStopAt > trackingBoundaryEnd
    }

    var estimatedStopInterval: TimeInterval? {
        guard let projectedStopInterval, reachesTargetAfterBoundary == false else {
            return nil
        }

        return projectedStopInterval
    }

    var estimatedStopAt: Date? {
        guard let projectedStopAt, reachesTargetAfterBoundary == false else {
            return nil
        }

        return projectedStopAt
    }

    var trackingElapsedSinceBaseline: TimeInterval? {
        guard
            !isPlaceholderSnapshot,
            let baseline = trackingBaselinePoint
        else {
            return nil
        }

        let referenceStart = max(baseline.timestamp, trackingStart)
        let elapsed = now.timeIntervalSince(referenceStart)
        guard elapsed > 0 else {
            return nil
        }

        return elapsed
    }

    func historyRecording(
        snapshot: UsageSnapshot,
        history: [UsageHistoryPoint]
    ) -> [UsageHistoryPoint] {
        let point = UsageHistoryPoint(
            timestamp: snapshot.lastUpdatedAt,
            remainingPercent: remainingPercent(for: snapshot)
        )

        var history = history
            .filter { $0.timestamp >= windowStart(for: snapshot).addingTimeInterval(-86_400) }
            .sorted { $0.timestamp < $1.timestamp }

        // Retain both ends of a plateau so the chart does not turn a break into burn.
        if history.count >= 2,
           abs(history[history.count - 1].remainingPercent - point.remainingPercent) < 0.05,
           abs(history[history.count - 2].remainingPercent - point.remainingPercent) < 0.05 {
            history[history.count - 1] = point
            return history
        }

        history.append(point)
        return history
    }

    func normalizeImportedHistory(_ points: [AutomaticUsageHistoryPoint]) -> [UsageHistoryPoint] {
        var normalized: [UsageHistoryPoint] = []

        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            let normalizedPoint = UsageHistoryPoint(
                timestamp: point.timestamp,
                remainingPercent: point.remainingPercent
            )

            if normalized.count >= 2,
               abs(normalized[normalized.count - 1].remainingPercent - normalizedPoint.remainingPercent) < 0.05,
               abs(normalized[normalized.count - 2].remainingPercent - normalizedPoint.remainingPercent) < 0.05 {
                normalized[normalized.count - 1] = normalizedPoint
            } else {
                normalized.append(normalizedPoint)
            }
        }

        return normalized
    }
}
