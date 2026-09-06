import Foundation
import Testing
@testable import runwai

struct UsageActivitySeriesTests {
    private let start = Date(timeIntervalSince1970: 1_788_652_800)

    @Test
    func rateUsesObservedTimeNotTimeSinceLastSync() {
        let end = start.addingTimeInterval(7 * 86_400)
        let points = [
            UsageHistoryPoint(timestamp: start, remainingPercent: 100),
            UsageHistoryPoint(timestamp: start.addingTimeInterval(3_600), remainingPercent: 96),
            UsageHistoryPoint(timestamp: start.addingTimeInterval(7_200), remainingPercent: 94)
        ]
        let series = UsageActivitySeries(history: points, range: .window, windowStart: start,
            windowEnd: end, now: start.addingTimeInterval(86_400))
        #expect(series.observedUse == 6)
        #expect(series.pointsPerHour == 3)
        #expect(series.points.last?.timestamp == points.last?.timestamp)
        #expect(series.expectedRemaining(at: start) == 100)
        #expect(series.expectedRemaining(at: end) == 0)
        #expect(series.nearest(to: start.addingTimeInterval(4_000)) == points[1])
    }

    @Test
    func todayFiltersPreviousWindowAndDoesNotInventMidnightReading() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = start.addingTimeInterval(2 * 86_400 + 12 * 3_600)
        let midnight = calendar.startOfDay(for: now)
        let first = UsageHistoryPoint(timestamp: midnight.addingTimeInterval(3_600), remainingPercent: 65)
        let series = UsageActivitySeries(history: [
            UsageHistoryPoint(timestamp: midnight.addingTimeInterval(-1), remainingPercent: 70),
            first,
            UsageHistoryPoint(timestamp: now, remainingPercent: 60),
            UsageHistoryPoint(timestamp: now.addingTimeInterval(1), remainingPercent: 50)
        ], range: .today, windowStart: start, windowEnd: start.addingTimeInterval(7 * 86_400), now: now, calendar: calendar)
        #expect(series.points.count == 2)
        #expect(series.points.first == first)
        #expect(series.domain.lowerBound == midnight)
        #expect(series.observedUse == 5)
    }

    @Test
    func sparseOrCorrectedHistoryDoesNotClaimBurnRate() {
        let end = start.addingTimeInterval(86_400)
        for history in [
            [],
            [UsageHistoryPoint(timestamp: start, remainingPercent: 70)],
            [UsageHistoryPoint(timestamp: start, remainingPercent: 70),
             UsageHistoryPoint(timestamp: start.addingTimeInterval(60), remainingPercent: 69)],
            [UsageHistoryPoint(timestamp: start, remainingPercent: 70),
             UsageHistoryPoint(timestamp: start.addingTimeInterval(3_600), remainingPercent: 75)]
        ] {
            let series = UsageActivitySeries(history: history, range: .window,
                windowStart: start, windowEnd: end, now: end)
            #expect(series.pointsPerHour == nil)
        }
    }

    @MainActor
    @Test
    func recordingAndImportKeepBothEndsOfFlatPeriods() {
        let suite = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = UsageMonitorModel(store: ManualUsageStore(defaults: defaults), automaticSyncServices: [:])
        defer { model.refreshTimer?.invalidate() }
        let readings: [Double] = [90, 90, 90, 85, 85, 85, 80]
        var history: [UsageHistoryPoint] = []
        var imported: [AutomaticUsageHistoryPoint] = []
        for (index, remaining) in readings.enumerated() {
            let time = start.addingTimeInterval(Double(index) * 3_600)
            history = model.historyRecording(snapshot: UsageSnapshot(
                weeklyBudgetUnits: 100, usedUnits: 100 - remaining,
                windowDuration: 604_800, resetAt: start.addingTimeInterval(604_800), lastUpdatedAt: time
            ), history: history)
            imported.append(AutomaticUsageHistoryPoint(timestamp: time, remainingPercent: remaining))
        }
        #expect(history.map(\.remainingPercent) == [90, 90, 85, 85, 80])
        #expect(history.map { $0.timestamp.timeIntervalSince(start) / 3_600 } == [0, 2, 3, 5, 6])
        #expect(model.normalizeImportedHistory(imported) == history)
    }
}
