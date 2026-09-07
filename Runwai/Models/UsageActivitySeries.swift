import Foundation

enum UsageActivityRange: String, CaseIterable, Identifiable {
    case today = "Day"
    case window = "Full window"
    case historical = "Historical"

    var id: Self { self }
}

struct UsageActivitySeries {
    let points: [UsageHistoryPoint]
    let domain: ClosedRange<Date>
    let windowStart: Date
    let windowEnd: Date
    let showsPace: Bool

    init(
        history: [UsageHistoryPoint], range: UsageActivityRange,
        windowStart: Date, windowEnd: Date, now: Date,
        calendar: Calendar = .current
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        showsPace = range != .historical
        let day = calendar.dateInterval(of: .day, for: now)!
        let start: Date
        let end: Date
        switch range {
        case .today:
            start = max(day.start, windowStart)
            end = min(day.end, windowEnd)
        case .window:
            start = windowStart
            end = windowEnd
        case .historical:
            let cutoff = now.addingTimeInterval(-30 * 86_400)
            start = max(history.filter { $0.timestamp <= now }.map(\.timestamp).min() ?? day.start, cutoff)
            end = now
        }
        domain = start...max(end, start.addingTimeInterval(1))
        // Do not invent readings at midnight, before tracking began, or after a stale sync.
        var byTime: [Date: UsageHistoryPoint] = [:]
        for point in history where point.timestamp >= start && point.timestamp <= min(end, now) {
            guard point.remainingPercent.isFinite else { continue }
            byTime[point.timestamp] = UsageHistoryPoint(
                timestamp: point.timestamp,
                remainingPercent: min(max(point.remainingPercent, 0), 100),
                windowResetAt: point.windowResetAt
            )
        }
        points = byTime.values.sorted { $0.timestamp < $1.timestamp }
    }

    var observedUse: Double? {
        if !showsPace {
            let intervals = segments.filter { $0.points.count >= 2 }
            guard !intervals.isEmpty else { return nil }
            return intervals.reduce(0) { $0 + $1.points.first!.remainingPercent - $1.points.last!.remainingPercent }
        }
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        // A quota correction is not negative consumption. Wait for a clean interval.
        guard segments.count == 1 else {
            return nil
        }
        return first.remainingPercent - last.remainingPercent
    }

    struct Segment: Identifiable {
        let id: Date
        var points: [UsageHistoryPoint]
    }

    var segments: [Segment] {
        var result: [Segment] = []
        for point in points {
            if let previous = result.last?.points.last,
               point.remainingPercent <= previous.remainingPercent,
               (point.windowResetAt == previous.windowResetAt || point.windowResetAt == nil || previous.windowResetAt == nil),
               !(previous.timestamp < windowStart && point.timestamp >= windowStart) {
                result[result.count - 1].points.append(point)
            } else {
                result.append(Segment(id: point.timestamp, points: [point]))
            }
        }
        return result
    }

    var pointsPerHour: Double? {
        guard let first = points.first, let last = points.last, let used = observedUse else { return nil }
        let elapsed = showsPace ? last.timestamp.timeIntervalSince(first.timestamp) : segments.reduce(0) {
            $0 + $1.points.last!.timestamp.timeIntervalSince($1.points.first!.timestamp)
        }
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
