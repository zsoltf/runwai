import Foundation
import Testing
@testable import runwai

struct PacingCalculatorTests {
    @Test
    func safeBudgetUsesRemainingTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: 40,
            windowDuration: UsageProvider.codex.defaultWindowDuration,
            resetAt: now.addingTimeInterval(2 * 86_400),
            lastUpdatedAt: now
        )

        let summary = PacingCalculator.evaluate(snapshot: snapshot, now: now)

        #expect(summary.remainingUnits == 60)
        #expect(summary.safeUnitsPerDay == 30)
        #expect(summary.remainingPercent == 60)
    }

    @Test
    func paceStatusTurnsBehindWhenBurningTooFast() {
        let resetAt = Date(timeIntervalSince1970: 2_000_000)
        let now = resetAt.addingTimeInterval(-(UsageProvider.codex.defaultWindowDuration / 2))
        let snapshot = UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: 70,
            windowDuration: UsageProvider.codex.defaultWindowDuration,
            resetAt: resetAt,
            lastUpdatedAt: now
        )

        let summary = PacingCalculator.evaluate(snapshot: snapshot, now: now)

        #expect(summary.status == .behind)
    }

    @Test
    func paceStatusTurnsAheadWhenBurningSlowly() {
        let resetAt = Date(timeIntervalSince1970: 3_000_000)
        let now = resetAt.addingTimeInterval(-(UsageProvider.codex.defaultWindowDuration / 2))
        let snapshot = UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: 20,
            windowDuration: UsageProvider.codex.defaultWindowDuration,
            resetAt: resetAt,
            lastUpdatedAt: now
        )

        let summary = PacingCalculator.evaluate(snapshot: snapshot, now: now)

        #expect(summary.status == .ahead)
    }

    @Test
    func exhaustedWinsWhenBudgetIsGone() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        let snapshot = UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: 120,
            windowDuration: UsageProvider.codex.defaultWindowDuration,
            resetAt: now.addingTimeInterval(86_400),
            lastUpdatedAt: now
        )

        let summary = PacingCalculator.evaluate(snapshot: snapshot, now: now)

        #expect(summary.remainingUnits == 0)
        #expect(summary.status == .exhausted)
    }

    @MainActor
    @Test
    func dailyTrackingUsesPreviousCheckpointAsBaseline() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ManualUsageStore(defaults: defaults)
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let yesterdayCheckpoint = calendar.date(
            bySettingHour: 22,
            minute: 0,
            second: 0,
            of: yesterday
        ) ?? yesterday

        store.saveHistory([
            UsageHistoryPoint(timestamp: yesterdayCheckpoint, remainingPercent: 100)
        ], for: .codex)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 10,
                windowDuration: UsageProvider.codex.defaultWindowDuration,
                resetAt: now.addingTimeInterval(4 * 86_400),
                lastUpdatedAt: now
            ),
            for: .codex
        )

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [:]
        )

        model.selectedProvider = .codex
        #expect(model.todayConsumedPercent == 10)
        #expect(model.todayTrackingLine == "Today")
        #expect(model.dailyProgressFraction > 0)
    }

    @MainActor
    @Test
    func codexWeeklyWindowExposesDailyTargetMilestones() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date(timeIntervalSince1970: 7_000_000)
        let store = ManualUsageStore(defaults: defaults)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 21,
                windowDuration: UsageProvider.codex.defaultWindowDuration,
                resetAt: now.addingTimeInterval(6 * 86_400),
                lastUpdatedAt: now
            ),
            for: .codex
        )

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [:]
        )

        model.selectedProvider = .codex

        #expect(model.dailyTargetMilestoneFractions.count == 6)
        #expect(abs(model.dailyTargetMilestoneFractions.first! - (6.0 / 7.0)) < 0.001)
        #expect(abs(model.dailyTargetMilestoneFractions.last! - (1.0 / 7.0)) < 0.001)
    }

    @MainActor
    @Test
    func overBudgetDailyTrackingShowsBorrowedBuffer() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date()
        let earlierToday = now.addingTimeInterval(-2 * 3_600)
        let store = ManualUsageStore(defaults: defaults)

        store.saveHistory([
            UsageHistoryPoint(timestamp: earlierToday, remainingPercent: 100)
        ], for: .codex)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 20,
                windowDuration: UsageProvider.codex.defaultWindowDuration,
                resetAt: now.addingTimeInterval(5 * 86_400),
                lastUpdatedAt: now
            ),
            for: .codex
        )

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [:]
        )

        model.selectedProvider = .codex

        #expect(model.isTodayOverBudget)
        #expect(model.focusBudgetLabel == "borrowed")
        #expect(model.focusBudgetValue.contains("h"))
        #expect(model.dailyBarTargetFraction < 1)
        #expect(model.dailyBarProgressFraction > model.dailyBarTargetFraction)
        #expect(model.borrowedBufferFraction > 0)
        #expect(model.borrowedBufferTrackTitle == "tomorrow")
        #expect(model.borrowedBufferSummaryLine.contains("tomorrow borrowed"))
        #expect(model.postLimitCarryoverLabel == "tomorrow starts")
        #expect(model.postLimitOutcomeLine.contains("tomorrow starts"))
        #expect(model.overBudgetStatusLine == "Into tomorrow")
    }

    @MainActor
    @Test
    func heroStyleSwapsDailyAndWeeklyPrimaryMetrics() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date(timeIntervalSince1970: 7_500_000)
        let store = ManualUsageStore(defaults: defaults)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 21,
                windowDuration: UsageProvider.codex.defaultWindowDuration,
                resetAt: now.addingTimeInterval(6 * 86_400),
                lastUpdatedAt: now
            ),
            for: .codex
        )

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [:]
        )

        model.selectedProvider = .codex
        model.heroStyle = .remainingFirst

        #expect(model.focusHeroPrimaryValue == model.focusBudgetValue)
        #expect(model.focusHeroSecondaryValue == model.estimatedStopAtValue)
        #expect(model.weeklyHeroPrimaryValue == model.remainingMetricValue)
        #expect(model.weeklyHeroSecondaryValue == model.daysRemainingMetricValue)

        model.heroStyle = .timeFirst

        #expect(model.focusHeroPrimaryValue == model.estimatedStopAtValue)
        #expect(model.focusHeroSecondaryValue == model.focusBudgetValue)
        #expect(model.weeklyHeroPrimaryValue == model.daysRemainingMetricValue)
        #expect(model.weeklyHeroSecondaryValue == model.remainingMetricValue)
    }

    @MainActor
    @Test
    func geminiDayPacingUsesSafeAllowanceByNowNotSingleHourAllowance() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date()
        let ninetyMinutesAgo = now.addingTimeInterval(-(90 * 60))
        let store = ManualUsageStore(defaults: defaults)

        store.saveHistory([
            UsageHistoryPoint(timestamp: ninetyMinutesAgo, remainingPercent: 100)
        ], for: .gemini)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 6,
                windowDuration: UsageProvider.gemini.defaultWindowDuration,
                resetAt: now.addingTimeInterval(20 * 3_600),
                lastUpdatedAt: now
            ),
            for: .gemini
        )

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [:]
        )

        model.selectedProvider = .gemini

        #expect(model.todayConsumedPercent == 6)
        #expect(model.dailyAllowancePercent > 6)
        #expect(model.isTodayOverBudget == false)
        #expect(model.focusBudgetLabel == "under pace today")
    }

    @MainActor
    @Test
    func clearingProviderDataReturnsToSetupState() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ManualUsageStore(defaults: defaults)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 35,
                windowDuration: UsageProvider.gemini.defaultWindowDuration,
                resetAt: Date().addingTimeInterval(4 * 3_600),
                lastUpdatedAt: Date()
            ),
            for: .gemini
        )
        store.saveHistory([
            UsageHistoryPoint(timestamp: Date(), remainingPercent: 65)
        ], for: .gemini)

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [:]
        )
        model.selectedProvider = .gemini

        #expect(model.isPlaceholderSnapshot == false)
        model.clearSelectedProviderData()

        #expect(model.isPlaceholderSnapshot)
        #expect(model.sourceModeDisplayName == "Gemini CLI")
        #expect(store.hasSavedSnapshot(for: .gemini) == false)
        #expect(store.loadHistory(for: .gemini).isEmpty)
    }

    @MainActor
    @Test
    func geminiSourceDefaultsToCliAndRefreshesAutomatically() async {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let resetAt = Date().addingTimeInterval(6 * 3_600)
        let model = UsageMonitorModel(
            store: ManualUsageStore(defaults: defaults),
            automaticSyncServices: [
                .geminiCLI: StubAutomaticSyncService(
                    provider: .gemini,
                    sourceMode: .geminiCLI,
                    payload: AutomaticUsageSyncPayload(
                        provider: .gemini,
                        usageSnapshot: UsageSnapshot(
                            weeklyBudgetUnits: 100,
                            usedUnits: 6,
                            windowDuration: UsageProvider.gemini.defaultWindowDuration,
                            resetAt: resetAt,
                            lastUpdatedAt: Date()
                        ),
                        detail: .gemini(
                            GeminiAutoSyncDetail(
                                modelID: "gemini-3.1-pro-preview",
                                tierName: "Gemini Code Assist in Google One AI Pro"
                            )
                        )
                    )
                )
            ]
        )

        model.selectedProvider = .gemini
        model.refreshNow()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(model.selectedSourceMode == .geminiCLI)
        #expect(model.isPlaceholderSnapshot == false)
        #expect(abs(model.remainingPercentInput - 94) < 0.1)
        #expect(model.resetAt == resetAt)
    }

    @MainActor
    @Test
    func codexSourceDefaultsToLocalAutoAndRefreshesAutomatically() async {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let weeklyReset = Date().addingTimeInterval(6 * 86_400)
        let primaryReset = Date().addingTimeInterval(2 * 3_600)
        let model = UsageMonitorModel(
            store: ManualUsageStore(defaults: defaults),
            automaticSyncServices: [
                .codexApp: StubAutomaticSyncService(
                    provider: .codex,
                    sourceMode: .codexApp,
                    payload: AutomaticUsageSyncPayload(
                        provider: .codex,
                        usageSnapshot: UsageSnapshot(
                            weeklyBudgetUnits: 100,
                            usedUnits: 15,
                            windowDuration: UsageProvider.codex.defaultWindowDuration,
                            resetAt: weeklyReset,
                            lastUpdatedAt: Date()
                        ),
                        detail: .codex(
                            CodexAutoSyncDetail(
                                planType: "pro",
                                primaryRemainingPercent: 84,
                                primaryResetAt: primaryReset,
                                secondaryRemainingPercent: 85,
                                secondaryResetAt: weeklyReset
                            )
                        )
                    )
                )
            ]
        )

        model.selectedProvider = .codex
        model.refreshNow()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(model.selectedSourceMode == .codexApp)
        #expect(model.isPlaceholderSnapshot == false)
        #expect(abs(model.remainingPercentInput - 85) < 0.1)
        #expect(model.resetAt == weeklyReset)
    }

    @MainActor
    @Test
    func codexSparkSourceDefaultsToLocalAutoAndRefreshesAutomatically() async {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let weeklyReset = Date().addingTimeInterval(6 * 86_400)
        let primaryReset = Date().addingTimeInterval(90 * 60)
        let model = UsageMonitorModel(
            store: ManualUsageStore(defaults: defaults),
            automaticSyncServices: [
                .codexSparkApp: StubAutomaticSyncService(
                    provider: .codexSpark,
                    sourceMode: .codexSparkApp,
                    payload: AutomaticUsageSyncPayload(
                        provider: .codexSpark,
                        usageSnapshot: UsageSnapshot(
                            weeklyBudgetUnits: 100,
                            usedUnits: 2,
                            windowDuration: UsageProvider.codexSpark.defaultWindowDuration,
                            resetAt: weeklyReset,
                            lastUpdatedAt: Date()
                        ),
                        detail: .codex(
                            CodexAutoSyncDetail(
                                planType: "pro",
                                primaryRemainingPercent: 99,
                                primaryResetAt: primaryReset,
                                secondaryRemainingPercent: 98,
                                secondaryResetAt: weeklyReset
                            )
                        )
                    )
                )
            ]
        )

        model.selectedProvider = .codexSpark
        model.refreshNow()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(model.selectedSourceMode == .codexSparkApp)
        #expect(model.isPlaceholderSnapshot == false)
        #expect(abs(model.remainingPercentInput - 98) < 0.1)
        #expect(model.resetAt == weeklyReset)
    }

    @MainActor
    @Test
    func geminiRefreshFailureSurfacesIssueState() async {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ManualUsageStore(defaults: defaults)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 8,
                windowDuration: UsageProvider.gemini.defaultWindowDuration,
                resetAt: Date().addingTimeInterval(5 * 3_600),
                lastUpdatedAt: Date().addingTimeInterval(-10 * 60)
            ),
            for: .gemini
        )

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [
                .geminiCLI: FailingAutomaticSyncService(
                    provider: .gemini,
                    sourceMode: .geminiCLI,
                    error: GeminiQuotaSyncError.syncFailed("forced failure")
                )
            ]
        )

        model.selectedProvider = .gemini
        model.refreshNow()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(model.hasSourceError)
        #expect(model.sourceBadgeText == "Issue")
        #expect(model.stalenessLine?.contains("auto-refresh failed") == true)
    }

    @MainActor
    @Test
    func codexOnlyLaunchPreservesPreviousProviderData() {
        let suite = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ManualUsageStore(defaults: defaults)
        let gemini = UsageSnapshot.sample(provider: .gemini, now: Date())
        store.save(gemini, for: .gemini)
        store.saveSelectedProvider(.gemini)
        let model = UsageMonitorModel(store: store, automaticSyncServices: [:])
        defer { model.refreshTimer?.invalidate() }

        #expect(model.selectedProvider == .codex)
        #expect(UsageProvider.visibleProviders == [.codex])
        #expect(Set(UsageMonitorModel.makeAutomaticSyncServices().keys) == [.codexApp])
        #expect(store.loadSnapshot(for: .gemini) == gemini)
        #expect(model.formattedNumber(42 - 1e-12) == model.formattedNumber(42))
    }

    @MainActor
    @Test
    func optionalFiveHourWindowDoesNotOverrideWeeklyUsage() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = UsageMonitorModel(
            store: ManualUsageStore(defaults: defaults),
            automaticSyncServices: [:]
        )
        defer { model.refreshTimer?.invalidate() }
        let now = Date()
        let weeklyReset = now.addingTimeInterval(6 * 86_400)

        for provider in [UsageProvider.codex, .codexSpark] {
            model.selectedProvider = provider
            for shortRemaining: Double? in [nil, 10, 0, nil] {
                model.applyAutomaticSyncPayload(AutomaticUsageSyncPayload(
                    provider: provider,
                    usageSnapshot: UsageSnapshot(
                        weeklyBudgetUnits: 100, usedUnits: 49,
                        windowDuration: 604_800, resetAt: weeklyReset, lastUpdatedAt: now
                    ),
                    detail: .codex(CodexAutoSyncDetail(
                        planType: "pro", primaryRemainingPercent: shortRemaining,
                        primaryResetAt: shortRemaining.map { _ in now.addingTimeInterval(3_600) },
                        secondaryRemainingPercent: 51, secondaryResetAt: weeklyReset
                    ))
                ))

                #expect(model.remainingPercentInput == 51)
                #expect(model.resetAt == weeklyReset)
                #expect(!model.hasSourceError)
                if let shortRemaining {
                    #expect(model.warningLine?.contains("5h window") == true)
                    #expect(model.warningLine?.contains("exhausted") == (shortRemaining == 0))
                } else {
                    #expect(model.warningLine == nil)
                }
            }
        }
    }

    @MainActor
    @Test
    func midnightSnapshotIsTodaysBaseline() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Calendar.current.date(from: DateComponents(
            year: 2026, month: 9, day: 6, hour: 12
        ))!
        let midnight = Calendar.current.startOfDay(for: now)
        let store = ManualUsageStore(defaults: defaults)
        store.saveHistory([
            UsageHistoryPoint(timestamp: midnight.addingTimeInterval(-86_400), remainingPercent: 79),
            UsageHistoryPoint(timestamp: midnight, remainingPercent: 62)
        ], for: .codex)
        store.save(UsageSnapshot(
            weeklyBudgetUnits: 100, usedUnits: 47, windowDuration: 604_800,
            resetAt: now.addingTimeInterval(4 * 86_400), lastUpdatedAt: now
        ), for: .codex)
        let model = UsageMonitorModel(store: store, automaticSyncServices: [:])
        defer { model.refreshTimer?.invalidate() }
        model.selectedProvider = .codex
        model.now = now

        #expect(model.todayConsumedPercent == 9)
        #expect(!model.isTodayOverBudget)
        #expect(model.overBudgetStatusLine == "Behind this week")
        #expect(model.focusTargetLabel == "today's budget")
    }

    @MainActor
    @Test
    func safeTodayCanStillBeBehindForWeek() {
        let suiteName = "runwai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Calendar.current.date(
            from: DateComponents(year: 2026, month: 3, day: 21, hour: 20, minute: 0, second: 0)
        )!
        let startOfToday = Calendar.current.startOfDay(for: now)
        let store = ManualUsageStore(defaults: defaults)

        store.saveHistory([
            UsageHistoryPoint(timestamp: startOfToday, remainingPercent: 62)
        ], for: .codex)
        store.save(
            UsageSnapshot(
                weeklyBudgetUnits: 100,
                usedUnits: 46,
                windowDuration: UsageProvider.codex.defaultWindowDuration,
                resetAt: now.addingTimeInterval(4.1 * 86_400),
                lastUpdatedAt: now
            ),
            for: .codex
        )

        let model = UsageMonitorModel(
            store: store,
            automaticSyncServices: [:]
        )

        model.selectedProvider = .codex
        model.now = now

        #expect(abs(model.todayRemainingAllowancePercent - 5.2) < 0.2)
        #expect(model.summary.status == .behind)
        #expect(model.reachesTargetAfterBoundary)
        #expect(model.overBudgetStatusLine == "Behind this week")
        #expect(model.estimatedStopAtLabel == "today's budget")
        #expect(model.estimatedStopCountdownLine == "Safe today. Behind this week.")
    }
}

private struct StubAutomaticSyncService: AutomaticUsageSyncing {
    let provider: UsageProvider
    let sourceMode: UsageSourceMode
    let payload: AutomaticUsageSyncPayload

    func fetchPayload() async throws -> AutomaticUsageSyncPayload {
        payload
    }
}

private struct FailingAutomaticSyncService: AutomaticUsageSyncing {
    let provider: UsageProvider
    let sourceMode: UsageSourceMode
    let error: Error

    func fetchPayload() async throws -> AutomaticUsageSyncPayload {
        throw error
    }
}
