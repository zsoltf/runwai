import Foundation

enum UsageActivityRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case window = "Full window"

    var id: Self { self }
}

struct UsageActivitySeries {
    let points: [UsageHistoryPoint]
    let domain: ClosedRange<Date>
    let windowStart: Date
    let windowEnd: Date

    init(
        history: [UsageHistoryPoint], range: UsageActivityRange,
        windowStart: Date, windowEnd: Date, now: Date,
        calendar: Calendar = .current
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        let day = calendar.dateInterval(of: .day, for: now)!
        let start = range == .today ? max(day.start, windowStart) : windowStart
        let end = range == .today ? min(day.end, windowEnd) : windowEnd
        domain = start...max(end, start.addingTimeInterval(1))
        // Do not invent readings at midnight, before tracking began, or after a stale sync.
        var byTime: [Date: UsageHistoryPoint] = [:]
        for point in history where point.timestamp >= start && point.timestamp <= min(end, now) {
            guard point.remainingPercent.isFinite else { continue }
            byTime[point.timestamp] = UsageHistoryPoint(
                timestamp: point.timestamp,
                remainingPercent: min(max(point.remainingPercent, 0), 100)
            )
        }
        points = byTime.values.sorted { $0.timestamp < $1.timestamp }
    }

    var observedUse: Double? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        // A quota correction is not negative consumption. Wait for a clean interval.
        guard zip(points, points.dropFirst()).allSatisfy({ $0.remainingPercent >= $1.remainingPercent }) else {
            return nil
        }
        return first.remainingPercent - last.remainingPercent
    }

    var pointsPerHour: Double? {
        guard let first = points.first, let last = points.last, let used = observedUse else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= 15 * 60 else { return nil }
        return used / (elapsed / 3_600)
    }

    func expectedRemaining(at date: Date) -> Double {
        let duration = max(windowEnd.timeIntervalSince(windowStart), 1)
        return min(max(100 * windowEnd.timeIntervalSince(date) / duration, 0), 100)
    }

    func nearest(to date: Date?) -> UsageHistoryPoint? {
        guard let date else { return points.last }
        return points.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
    }
}
