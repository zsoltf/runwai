import Foundation
import Testing
@testable import runwai

struct UsageActivitySeriesTests {
    private let start = Date(timeIntervalSince1970: 1_788_652_800)

    @Test(arguments: UsageActivityRange.allCases)
    func correctedSegmentsUseDurationWeightedRateWithoutBridgingGaps(range: UsageActivityRange) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let history = zip([0.0, 1, 3, 6, 8], [90.0, 84, 95, 92, 99]).map {
            UsageHistoryPoint(timestamp: start.addingTimeInterval($0.0 * 3_600), remainingPercent: $0.1)
        }
        let series = UsageActivitySeries(history: history, range: range, windowStart: start,
            windowEnd: start.addingTimeInterval(86_400), now: start.addingTimeInterval(9 * 3_600), calendar: calendar)
        #expect(series.segments.map { $0.points.count } == [2, 2, 1])
        #expect(series.observedUse == 9)
        // 6 points in one hour plus 3 in three hours, not the mean of the rates
        // or the nine-hour span containing unobserved correction gaps.
        #expect(series.pointsPerHour == 2.25)
    }

    @Test(arguments: UsageActivityRange.allCases)
    func resetMetadataBreaksEvenADecreasingReading(range: UsageActivityRange) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = start.addingTimeInterval(86_400)
        let history = [
            UsageHistoryPoint(timestamp: start, remainingPercent: 90, windowResetAt: end),
            UsageHistoryPoint(timestamp: start.addingTimeInterval(3_600), remainingPercent: 86, windowResetAt: end),
            UsageHistoryPoint(timestamp: start.addingTimeInterval(7_200), remainingPercent: 80, windowResetAt: end.addingTimeInterval(1)),
            UsageHistoryPoint(timestamp: start.addingTimeInterval(10_800), remainingPercent: 78, windowResetAt: end.addingTimeInterval(1))
        ]
        let series = UsageActivitySeries(history: history, range: range, windowStart: start,
            windowEnd: end, now: start.addingTimeInterval(14_400), calendar: calendar)
        #expect(series.segments.count == 2)
        #expect(series.observedUse == 6)
        #expect(series.pointsPerHour == 3)
    }

    @Test(arguments: UsageActivityRange.allCases)
    func thresholdUsesCombinedCleanTimeAndPlateausCount(range: UsageActivityRange) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for seconds in [899.0, 900] {
            let history = [
                UsageHistoryPoint(timestamp: start, remainingPercent: 80),
                UsageHistoryPoint(timestamp: start.addingTimeInterval(400), remainingPercent: 80),
                UsageHistoryPoint(timestamp: start.addingTimeInterval(3_600), remainingPercent: 90),
                UsageHistoryPoint(timestamp: start.addingTimeInterval(3_600 + seconds - 400), remainingPercent: 90),
                UsageHistoryPoint(timestamp: start.addingTimeInterval(7_200), remainingPercent: 100)
            ]
            let series = UsageActivitySeries(history: history, range: range, windowStart: start,
                windowEnd: start.addingTimeInterval(86_400), now: start.addingTimeInterval(10_800), calendar: calendar)
            #expect(series.observedUse == 0)
            #expect(series.pointsPerHour == (seconds == 900 ? 0 : nil))
        }
    }

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
        #expect(model.normalizeImportedHistory(imported, resetAt: start.addingTimeInterval(604_800)) == history)
    }

    @Test
    func historicalIncludesPreviousWindowsWithoutConnectingResets() {
        let oldReset = start
        let newReset = start.addingTimeInterval(604_800)
        let history = [
            UsageHistoryPoint(timestamp: start.addingTimeInterval(-40 * 86_400), remainingPercent: 75),
            UsageHistoryPoint(timestamp: start.addingTimeInterval(-3_600), remainingPercent: 5, windowResetAt: oldReset),
            UsageHistoryPoint(timestamp: start, remainingPercent: 100, windowResetAt: newReset),
            UsageHistoryPoint(timestamp: start.addingTimeInterval(3_600), remainingPercent: 95, windowResetAt: newReset)
        ]
        let series = UsageActivitySeries(history: history, range: .historical,
            windowStart: start, windowEnd: newReset, now: start.addingTimeInterval(7_200))
        #expect(series.points.count == 3)
        #expect(series.segments.count == 2)
        #expect(series.pointsPerHour == 5)
        #expect(series.observedUse == 5)
        #expect(series.showsPace == false)
    }

    @MainActor
    @Test
    func syncRetainsOldWindowsAndLocalReadings() {
        let suite = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ManualUsageStore(defaults: defaults)
        let model = UsageMonitorModel(store: store, automaticSyncServices: [:])
        defer { model.refreshTimer?.invalidate() }
        let old = UsageHistoryPoint(timestamp: start.addingTimeInterval(-86_400), remainingPercent: 10, windowResetAt: start)
        let local = UsageHistoryPoint(timestamp: start, remainingPercent: 90)
        model.history = [old, local]
        let snapshot = UsageSnapshot(weeklyBudgetUnits: 100, usedUnits: 20,
            windowDuration: 604_800, resetAt: start.addingTimeInterval(604_800),
            lastUpdatedAt: start.addingTimeInterval(7_200))
        model.applyAutomaticSyncPayload(AutomaticUsageSyncPayload(provider: .codex, usageSnapshot: snapshot,
            detail: nil, historyPoints: [AutomaticUsageHistoryPoint(timestamp: start.addingTimeInterval(3_600), remainingPercent: 85)]))
        #expect(model.history.contains(old))
        #expect(model.history.contains(local))
        #expect(model.history.last?.remainingPercent == 80)
        #expect(store.loadHistory(for: .codex) == model.history)
    }

    @Test
    func oldHistoryDecodesWithoutWindowMetadata() throws {
        let data = Data("[{\"timestamp\":0,\"remainingPercent\":50}]".utf8)
        let points = try JSONDecoder().decode([UsageHistoryPoint].self, from: data)
        #expect(points.first?.windowResetAt == nil)
        #expect(points.first?.remainingPercent == 50)
    }
}
