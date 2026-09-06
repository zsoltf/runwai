import Foundation
import Observation

@MainActor
@Observable
final class UsageMonitorModel {
    var selectedProvider: UsageProvider {
        didSet {
            guard selectedProvider != oldValue else { return }
            store.saveSelectedProvider(selectedProvider)
            now = Date()
            refreshAutomaticSources(for: [selectedProvider])
        }
    }

    var glassAppearance: GlassAppearance {
        didSet {
            guard glassAppearance != oldValue else { return }
            store.saveGlassAppearance(glassAppearance)
        }
    }

    var heroStyle: HeroStyle {
        didSet {
            guard heroStyle != oldValue else { return }
            store.saveHeroStyle(heroStyle)
        }
    }

    var now: Date

    var snapshotsByProvider: [UsageProvider: UsageSnapshot]
    var historiesByProvider: [UsageProvider: [UsageHistoryPoint]]
    var placeholdersByProvider: [UsageProvider: Bool]
    var sourceModesByProvider: [UsageProvider: UsageSourceMode]
    var syncErrorsByProvider: [UsageProvider: String]
    var automaticSourceDetailsByProvider: [UsageProvider: AutomaticUsageSyncDetail]
    var automaticRefreshPausedUntilByProvider: [UsageProvider: Date]

    let store: ManualUsageStore
    let automaticSyncServices: [UsageSourceMode: any AutomaticUsageSyncing]
    var refreshTimer: Timer?
    var activeSyncProviders: Set<UsageProvider>

    init(
        store: ManualUsageStore = ManualUsageStore(),
        automaticSyncServices: [UsageSourceMode: any AutomaticUsageSyncing]? = nil
    ) {
        self.store = store
        self.automaticSyncServices = automaticSyncServices ?? UsageMonitorModel.makeAutomaticSyncServices()
        self.selectedProvider = store.loadSelectedProvider()
        self.glassAppearance = store.loadGlassAppearance()
        self.heroStyle = store.loadHeroStyle()
        self.now = Date()
        self.snapshotsByProvider = [:]
        self.historiesByProvider = [:]
        self.placeholdersByProvider = [:]
        self.sourceModesByProvider = [:]
        self.syncErrorsByProvider = [:]
        self.automaticSourceDetailsByProvider = [:]
        self.automaticRefreshPausedUntilByProvider = [:]
        self.activeSyncProviders = []

        for provider in UsageProvider.allCases {
            let loadedMode = store.loadMode(for: provider)
            let hasSavedSnapshot = store.hasSavedSnapshot(for: provider)
            snapshotsByProvider[provider] = store.loadSnapshot(for: provider)
            historiesByProvider[provider] = store.loadHistory(for: provider)
            placeholdersByProvider[provider] = !hasSavedSnapshot
            sourceModesByProvider[provider] = loadedMode.isImplementedInScaffold ? loadedMode : provider.defaultSourceMode
        }

        if UsageProvider.visibleProviders.contains(selectedProvider) == false {
            selectedProvider = .codex
            store.saveSelectedProvider(selectedProvider)
        }

        if snapshotsByProvider[selectedProvider] == nil {
            selectedProvider = .codex
        }

        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow(force: false)
            }
        }

        refreshAutomaticSources(force: false)
    }

    var providerName: String {
        selectedProvider.displayName
    }

    var windowLabel: String {
        selectedProvider.windowLabel
    }

    var heroStyleDescription: String {
        heroStyle.description
    }

    var summary: PacingSummary {
        PacingCalculator.evaluate(snapshot: snapshot, now: now)
    }

    var menuBarLabel: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        if summary.remainingUnits == 0 {
            return "0%"
        }

        return "\(Int(summary.remainingPercent.rounded()))%"
    }

    var menuBarSecondaryLabel: String {
        if isPlaceholderSnapshot {
            return "set"
        }

        if summary.timeRemaining <= 0 {
            return "reset"
        }

        let totalMinutes = Int(summary.timeRemaining / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60

        if days > 0 {
            return "\(days)d"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(max(totalMinutes, 1))m"
    }

    var menuBarHelpText: String {
        if isPlaceholderSnapshot {
            return manualSnapshotDescription
        }

        return "\(providerName): \(remainingHeadline), \(menuBarSecondaryLabel) left, \(paceStatusLine.lowercased()), \(sourceStatusLine)"
    }

    var menuBarGlyphProgress: Double {
        if isPlaceholderSnapshot {
            return 0.22
        }

        return min(max(dailyProgressFraction, 0.08), 1)
    }

    var sourceBadgeText: String {
        if sourceMode.usesAutomaticRefresh {
            if hasSourceError {
                return "Issue"
            }

            if isAutomaticSourceStale {
                return "Behind"
            }

            if isSourceRefreshing {
                return "Syncing"
            }
        }

        if isPlaceholderSnapshot {
            return sourceMode.usesAutomaticRefresh ? sourceMode.badgeText : "Set up"
        }

        return sourceMode.badgeText
    }

    var sourceModeDisplayName: String {
        sourceMode.displayName
    }

    var sourceModeSummaryLine: String {
        if isPlaceholderSnapshot {
            if sourceMode == .codexApp {
                return "Waiting for Codex session data"
            }

        if sourceMode == .codexSparkApp {
            return "Waiting for Codex Spark session data"
        }

            if sourceMode == .geminiCLI {
                return "Waiting for Gemini CLI quota"
            }

            return "No snapshot saved yet"
        }

        return "\(sourceMode.displayName) source"
    }

    var sourceStatusLine: String {
        if sourceMode.usesAutomaticRefresh {
            if hasSourceError {
                return "auto refresh failed"
            }

            if isSourceRefreshing {
                return "auto syncing"
            }

            if isAutomaticSourceStale {
                return "auto behind · \(updatedShortLine)"
            }

            if isPlaceholderSnapshot {
                return "waiting for auto data"
            }

            return "auto · \(updatedShortLine)"
        }

        if isPlaceholderSnapshot {
            return "manual setup"
        }

        return "manual · \(updatedShortLine)"
    }

    var availableSourceModes: [UsageSourceMode] {
        selectedProvider.availableSourceModes.filter(\.isImplementedInScaffold)
    }

    var selectedSourceMode: UsageSourceMode {
        get { sourceMode }
        set {
            guard
                sourceMode != newValue,
                availableSourceModes.contains(newValue)
            else {
                return
            }

            sourceMode = newValue
            syncErrorsByProvider[selectedProvider] = nil
            store.saveMode(newValue, for: selectedProvider)

            if newValue.usesAutomaticRefresh {
                refreshAutomaticSources(for: [selectedProvider])
            }
        }
    }

    var remainingHeadline: String {
        if isPlaceholderSnapshot {
            return "Add your numbers"
        }

        return "\(formattedNumber(summary.remainingPercent))% left"
    }

    var remainingMetricValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        return "\(formattedNumber(summary.remainingPercent))%"
    }

    var remainingMetricLabel: String {
        selectedProvider.remainingLabel
    }

    var remainingUnitsLine: String {
        if isPlaceholderSnapshot {
            return selectedProvider.resetHint
        }

        return selectedProvider.usageLineLabel
    }

    var budgetHealthLine: String {
        if isPlaceholderSnapshot {
            return "Manual snapshot needed"
        }

        switch summary.remainingPercent {
        case ...0:
            return "Current budget exhausted"
        case ...10:
            return "Tight runway"
        case ...25:
            return "Watch the burn"
        case ...50:
            return "Healthy runway"
        default:
            return "Comfortable runway"
        }
    }

    var resetAtLine: String {
        if isPlaceholderSnapshot {
            return "Waiting for reset time"
        }

        return "Resets \(Formatters.resetAt.string(from: snapshot.resetAt))"
    }

    var timeRemainingLine: String {
        if isPlaceholderSnapshot {
            return "Set the reset time in Settings."
        }

        return Formatters.relativeDuration.string(from: summary.timeRemaining) ?? "Less than 1m remaining"
    }

    var daysRemainingLine: String {
        if isPlaceholderSnapshot {
            return "Set reset time"
        }

        if summary.timeRemaining <= 0 {
            return "Window exhausted"
        }

        switch selectedProvider.timeMetricUnit {
        case .days:
            return "\(formattedNumber(summary.daysRemaining)) days remaining"
        case .hours:
            return "\(formattedNumber(summary.hoursRemaining)) hours remaining"
        }
    }

    var daysRemainingMetricValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        if summary.timeRemaining <= 0 {
            return "0"
        }

        switch selectedProvider.timeMetricUnit {
        case .days:
            return formattedNumber(summary.daysRemaining)
        case .hours:
            return formattedNumber(summary.hoursRemaining)
        }
    }

    var daysRemainingMetricDetail: String {
        if isPlaceholderSnapshot {
            return "Set reset time"
        }

        switch selectedProvider.timeMetricUnit {
        case .days:
            return "days left"
        case .hours:
            return "hours left"
        }
    }

    var weeklyHeroPrimaryValue: String {
        switch heroStyle {
        case .remainingFirst:
            return remainingMetricValue
        case .timeFirst:
            return daysRemainingMetricValue
        }
    }

    var weeklyHeroPrimaryLabel: String {
        switch heroStyle {
        case .remainingFirst:
            return remainingMetricLabel
        case .timeFirst:
            return daysRemainingMetricDetail
        }
    }

    var weeklyHeroSecondaryValue: String {
        switch heroStyle {
        case .remainingFirst:
            return daysRemainingMetricValue
        case .timeFirst:
            return remainingMetricValue
        }
    }

    var weeklyHeroSecondaryLabel: String {
        switch heroStyle {
        case .remainingFirst:
            return daysRemainingMetricDetail
        case .timeFirst:
            return remainingMetricLabel
        }
    }

    var safeTodayValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        return "\(formattedNumber(dailyAllowancePercent))%"
    }

    var safeRateHeadline: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        switch selectedProvider.rateUnit {
        case .day:
            return "\(formattedNumber(summary.safePercentPerDay))% / day"
        case .hour:
            return "\(formattedNumber(summary.safePercentPerHour))% / hour"
        }
    }

    var safeRateCaption: String {
        "safe pace"
    }

    var todaySectionTitle: String {
        selectedProvider.trackingSectionTitle
    }

    var todayUsedValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        return "\(formattedNumber(todayConsumedPercent))%"
    }

    var todayUsedLabel: String {
        selectedProvider.usedTrackingLabel
    }

    var todayRemainingValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        return "\(formattedNumber(todayRemainingAllowancePercent))%"
    }

    var todayRemainingLabel: String {
        selectedProvider.remainingTrackingLabel
    }

    var focusBudgetValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        if isTodayOverBudget {
            return borrowedBufferValue
        }

        return todayRemainingValue
    }

    var focusBudgetLabel: String {
        if isTodayOverBudget {
            return borrowedBufferLabel
        }

        return todayRemainingLabel
    }

    var focusBudgetNote: String {
        if isTodayOverBudget {
            return borrowedBufferSummaryLine
        }

        return safeRateHeadline
    }

    var focusHeroPrimaryValue: String {
        if isTodayOverBudget {
            return borrowedBufferValue
        }

        switch heroStyle {
        case .remainingFirst:
            return focusBudgetValue
        case .timeFirst:
            return estimatedStopAtValue
        }
    }

    var focusHeroPrimaryLabel: String {
        if isTodayOverBudget {
            return borrowedBufferLabel
        }

        switch heroStyle {
        case .remainingFirst:
            return focusBudgetLabel
        case .timeFirst:
            return estimatedStopAtLabel
        }
    }

    var focusHeroSecondaryValue: String {
        if isTodayOverBudget {
            return postLimitCarryoverValue
        }

        switch heroStyle {
        case .remainingFirst:
            return estimatedStopAtValue
        case .timeFirst:
            return focusBudgetValue
        }
    }

    var focusHeroSecondaryLabel: String {
        if isTodayOverBudget {
            return postLimitCarryoverLabel
        }

        switch heroStyle {
        case .remainingFirst:
            return estimatedStopAtLabel
        case .timeFirst:
            return focusBudgetLabel
        }
    }

    var dailyAllowancePercent: Double {
        guard !isPlaceholderSnapshot else {
            return 0
        }

        switch selectedProvider.rateUnit {
        case .day:
            return min(targetRatePercent, summary.remainingPercent)
        case .hour:
            guard let elapsed = trackingElapsedSinceBaseline else {
                return 0
            }

            let cumulativeAllowance = summary.safePercentPerHour * (elapsed / 3_600)
            return min(max(cumulativeAllowance, 0), 100)
        }
    }

    var todayConsumedPercent: Double {
        guard
            !isPlaceholderSnapshot,
            let baseline = trackingBaselinePoint
        else {
            return 0
        }

        return max(baseline.remainingPercent - summary.remainingPercent, 0)
    }

    var todayRemainingAllowancePercent: Double {
        max(dailyAllowancePercent - todayConsumedPercent, 0)
    }

    var dailyProgressFraction: Double {
        guard dailyAllowancePercent > 0 else {
            return 0
        }

        return min(max(todayConsumedPercent / dailyAllowancePercent, 0), 1)
    }

    var borrowedBufferFraction: Double {
        guard isTodayOverBudget else {
            return 0
        }

        return max(dailyOveragePercent / nextBufferCapacityPercent, 0)
    }

    var borrowedBufferPercent: Double {
        borrowedBufferFraction * 100
    }

    var dailyBarProgressFraction: Double {
        guard isTodayOverBudget else {
            return dailyProgressFraction
        }

        let totalVisiblePercent = dailyAllowancePercent + nextBufferCapacityPercent
        guard totalVisiblePercent > 0 else {
            return 1
        }

        return min(max(todayConsumedPercent / totalVisiblePercent, dailyBarTargetFraction), 1)
    }

    var dailyBarTargetFraction: Double {
        guard isTodayOverBudget else {
            return 1
        }

        let totalVisiblePercent = dailyAllowancePercent + nextBufferCapacityPercent
        guard totalVisiblePercent > 0 else {
            return 0.5
        }

        return min(max(dailyAllowancePercent / totalVisiblePercent, 0.18), 0.82)
    }

    var borrowedBufferTrackTitle: String {
        switch selectedProvider.rateUnit {
        case .day:
            return "tomorrow"
        case .hour:
            return "next buffer"
        }
    }

    var borrowedBufferSummaryLine: String {
        guard isTodayOverBudget else {
            return ""
        }

        switch selectedProvider.rateUnit {
        case .day:
            return "\(formattedNumber(borrowedBufferPercent))% of tomorrow borrowed"
        case .hour:
            return "\(formattedNumber(borrowedBufferPercent))% of next buffer borrowed"
        }
    }

    var postLimitCarryoverValue: String {
        guard isTodayOverBudget else {
            return safeTodayValue
        }

        return "\(formattedNumber(nextBufferRemainingPercent))%"
    }

    var postLimitCarryoverLabel: String {
        switch selectedProvider.rateUnit {
        case .day:
            return "tomorrow starts"
        case .hour:
            return "next buffer starts"
        }
    }

    var postLimitOutcomeLine: String {
        guard isTodayOverBudget else {
            return ""
        }

        if nextBufferRemainingPercent > 0 {
            return "\(postLimitCarryoverLabel) at \(postLimitCarryoverValue)"
        }

        switch selectedProvider.rateUnit {
        case .day:
            return "tomorrow starts at 0%"
        case .hour:
            return "next buffer starts at 0%"
        }
    }

    var overBudgetStatusLine: String {
        guard isTodayOverBudget else {
            switch summary.status {
            case .ahead:
                return selectedProvider.rateUnit == .day ? "Ahead this week" : "Ahead of pace"
            case .onPace:
                return selectedProvider.rateUnit == .day ? "On pace this week" : "On pace"
            case .behind:
                return selectedProvider.rateUnit == .day ? "Behind this week" : "Behind pace"
            case .exhausted:
                return "Exhausted"
            }
        }

        switch selectedProvider.rateUnit {
        case .day:
            return nextBufferRemainingPercent > 0 ? "Into tomorrow" : "Past tomorrow"
        case .hour:
            return nextBufferRemainingPercent > 0 ? "Into next buffer" : "Past next buffer"
        }
    }

    var isTodayOverBudget: Bool {
        todayConsumedPercent > dailyAllowancePercent + 0.05
    }

    var dailyOveragePercent: Double {
        max(todayConsumedPercent - dailyAllowancePercent, 0)
    }

    var todayTrackingLine: String {
        if isPlaceholderSnapshot {
            return "Waiting for setup"
        }

        guard let baseline = trackingBaselinePoint else {
            return "Add another check-in"
        }

        if baseline.timestamp > trackingStart {
            return "Since \(Formatters.timeOnly.string(from: baseline.timestamp))"
        }

        return todaySectionTitle
    }

    var todayBudgetSummaryLine: String {
        if isPlaceholderSnapshot {
            return "Pacing appears after setup."
        }

        guard let baseline = trackingBaselinePoint else {
            return "Update again later to start tracking this cadence."
        }

        if baseline.timestamp > trackingStart && todayConsumedPercent == 0 {
            switch selectedProvider.trackingScope {
            case .day:
                return "This is your first check-in today."
            case .window:
                return "This is your first check-in this window."
            }
        }

        if isTodayOverBudget {
            return "\(formattedNumber(todayConsumedPercent - dailyAllowancePercent))% over target pace"
        }

        switch selectedProvider.rateUnit {
        case .day:
            switch selectedProvider.trackingScope {
            case .day:
                return "\(formattedNumber(todayRemainingAllowancePercent))% left in today's budget"
            case .window:
                return "\(formattedNumber(todayRemainingAllowancePercent))% left in this window's budget"
            }
        case .hour:
            switch selectedProvider.trackingScope {
            case .day:
                return "\(formattedNumber(todayRemainingAllowancePercent))% left before you drift over pace today"
            case .window:
                return "\(formattedNumber(todayRemainingAllowancePercent))% left before you drift over pace in this window"
            }
        }
    }

    var todayBudgetMetaLine: String {
        if isPlaceholderSnapshot {
            return "Target appears after setup"
        }

        return "\(formattedNumber(todayConsumedPercent))% used • \(formattedNumber(dailyAllowancePercent))% target"
    }

    var estimatedStopAtValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        if isTodayOverBudget {
            return borrowedBufferValue
        }

        if reachesTargetAfterBoundary {
            return "on track"
        }

        guard let estimatedStopAt else {
            return "--"
        }

        return Formatters.timeOnly.string(from: estimatedStopAt)
    }

    var estimatedStopAtLabel: String {
        if isTodayOverBudget {
            return borrowedBufferLabel
        }

        if reachesTargetAfterBoundary {
            switch selectedProvider.trackingScope {
            case .day:
                return "today's budget"
            case .window:
                return "safe through reset"
            }
        }

        return estimatedStopAt == nil ? "need more history" : "budget lasts until"
    }

    var estimatedStopCountdownLine: String {
        if isPlaceholderSnapshot {
            return "Set your weekly snapshot to estimate today's stopping point."
        }

        if isTodayOverBudget {
            switch selectedProvider.rateUnit {
            case .day:
                return "Ease up to protect tomorrow."
            case .hour:
                return "Ease up to protect the next buffer."
            }
        }

        if reachesTargetAfterBoundary {
            switch selectedProvider.trackingScope {
            case .day:
                switch summary.status {
                case .ahead:
                    return "Safe today. Ahead this week."
                case .onPace:
                    return "Safe today. On pace this week."
                case .behind:
                    return "Safe today. Behind this week."
                case .exhausted:
                    return "No room left before reset."
                }
            case .window:
                return "Inside this window target."
            }
        }

        guard let interval = estimatedStopInterval else {
            return todayBudgetSummaryLine
        }

        return "At this pace, today's budget lasts \(Formatters.relativeDuration.string(from: interval) ?? "a little longer")."
    }

    var safeUnitsPerDayLine: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        switch selectedProvider.rateUnit {
        case .day:
            return "\(formattedNumber(summary.safePercentPerDay))% / day"
        case .hour:
            return "\(formattedNumber(summary.safePercentPerHour))% / hour"
        }
    }

    var paceStatusLine: String {
        if isPlaceholderSnapshot {
            return "Needs setup"
        }

        return summary.status.displayText
    }

    var paceSummaryLine: String {
        if isPlaceholderSnapshot {
            return "Add your current remaining percentage to see target pace."
        }

        return paceDetailLine
    }

    var expectedRemainingFraction: Double {
        if summary.weeklyBudgetUnits <= 0 {
            return 0
        }

        let expectedUsedFraction = summary.expectedUsedUnits / summary.weeklyBudgetUnits
        return min(max(1 - expectedUsedFraction, 0), 1)
    }

    var expectedRemainingPercent: Double {
        expectedRemainingFraction * 100
    }

    var dailyTargetMilestoneFractions: [Double] {
        guard
            !isPlaceholderSnapshot,
            selectedProvider.rateUnit == .day,
            snapshot.windowDuration > 86_400
        else {
            return []
        }

        let dayInterval: TimeInterval = 86_400
        var milestoneFractions: [Double] = []
        var boundary = windowStart.addingTimeInterval(dayInterval)

        while boundary < snapshot.resetAt {
            let elapsedFraction = boundary.timeIntervalSince(windowStart) / snapshot.windowDuration
            let remainingFraction = 1 - elapsedFraction

            if remainingFraction > 0.001 && remainingFraction < 0.999 {
                milestoneFractions.append(remainingFraction)
            }

            boundary = boundary.addingTimeInterval(dayInterval)
        }

        return milestoneFractions
    }

    var windowStart: Date {
        snapshot.resetAt.addingTimeInterval(-snapshot.windowDuration)
    }

    var displayHistory: [UsageHistoryPoint] {
        guard !isPlaceholderSnapshot else {
            return []
        }

        let trackedPoints = trackedHistoryPoints
        var points = trackedPoints
            .filter { $0.timestamp >= windowStart && $0.timestamp <= snapshot.resetAt }

        if let lastBeforeWindow = trackedPoints.last(where: { $0.timestamp < windowStart }) {
            let baseline = UsageHistoryPoint(
                timestamp: windowStart,
                remainingPercent: lastBeforeWindow.remainingPercent
            )

            if points.isEmpty || points.first?.timestamp != windowStart {
                points.insert(baseline, at: 0)
            }
        }

        return points
    }

    var shouldShowTrend: Bool {
        displayHistory.count >= 3
    }

    var paceDetailLine: String {
        if isPlaceholderSnapshot {
            return "Add the current remaining percentage to compare your burn against the reset window."
        }

        switch summary.status {
        case .ahead:
            return "\(formattedNumber(abs(summary.deltaFromExpected))) pts under target"
        case .onPace:
            return "On target pace"
        case .behind:
            return "\(formattedNumber(abs(summary.deltaFromExpected))) pts over target"
        case .exhausted:
            return "No room left before reset"
        }
    }

    var trendCurrentValue: String {
        remainingMetricValue
    }

    var trendTargetValue: String {
        if isPlaceholderSnapshot {
            return "--"
        }

        return "\(formattedNumber(expectedRemainingPercent))%"
    }

    var trendSummaryLine: String {
        if isPlaceholderSnapshot {
            return "Trend appears after another check-in."
        }

        return "now \(trendCurrentValue) • target \(trendTargetValue)"
    }

    var lastUpdatedLine: String {
        if isPlaceholderSnapshot {
            return "Set your manual snapshot"
        }

        return "Last updated \(Formatters.relativeDate.localizedString(for: snapshot.lastUpdatedAt, relativeTo: now))"
    }

    var settingsLastUpdatedLine: String {
        if isPlaceholderSnapshot {
            return "No snapshot saved for this provider yet."
        }

        return "\(compactUpdatedLine). \(compactResetLine)."
    }

    var compactResetLine: String {
        if isPlaceholderSnapshot {
            return "Set reset time"
        }

        return "Resets \(Formatters.compactResetAt.string(from: snapshot.resetAt))"
    }

    var compactUpdatedLine: String {
        if isPlaceholderSnapshot {
            return "Waiting for snapshot"
        }

        return "Updated \(Formatters.relativeDate.localizedString(for: snapshot.lastUpdatedAt, relativeTo: now))"
    }

    var stalenessLine: String? {
        if isPlaceholderSnapshot {
            return nil
        }

        if sourceMode.usesAutomaticRefresh {
            if hasSourceError {
                return "\(providerName) auto-refresh failed. Showing the last saved snapshot."
            }

            if isAutomaticSourceStale {
                return "\(providerName) auto data is \(relativeAgeShortString(from: snapshot.lastUpdatedAt)) behind. Showing the last saved snapshot."
            }
        }

        return summary.isStale ? "Manual values may be stale. Review your numbers." : nil
    }

    var warningLine: String? {
        if isPlaceholderSnapshot {
            return nil
        }

        if summary.remainingUnits == 0 {
            return "This budget is exhausted."
        }

        if let codexWindowWarningLine {
            return codexWindowWarningLine
        }

        if summary.remainingPercent <= 10 {
            return "Less than 10% remains in the current window."
        }

        return nil
    }

    var localDataDescription: String {
        if isCodexAutoSource(provider: selectedProvider, mode: sourceMode) {
            if let syncError = syncErrorsByProvider[selectedProvider] {
                return "runwai could not refresh \(providerName) just now: \(syncError)"
            }

            return "runwai reads live \(providerName) usage from your local Codex login on this Mac, and keeps local history for the pacing view."
        }

        if selectedProvider == .gemini, sourceMode == .geminiCLI {
            if let syncError = syncErrorsByProvider[.gemini] {
                return "runwai could not refresh Gemini CLI just now: \(syncError)"
            }

            return "runwai reads Gemini quota locally from Gemini CLI about once a minute. Nothing new signs in here."
        }

        return "All snapshots and history stay on this Mac. runwai does not sign in to provider accounts in this build."
    }

    var hasSourceError: Bool {
        sourceMode.usesAutomaticRefresh && selectedSyncError != nil
    }

    var isSourceRefreshing: Bool {
        sourceMode.usesAutomaticRefresh && activeSyncProviders.contains(selectedProvider)
    }

    var isAutomaticSourceStale: Bool {
        guard
            sourceMode.usesAutomaticRefresh,
            !isPlaceholderSnapshot
        else {
            return false
        }

        return now.timeIntervalSince(snapshot.lastUpdatedAt) > automaticSourceStaleThreshold
    }

    var overageBorrowLine: String {
        if !isTodayOverBudget {
            return "Within today's target pace."
        }

        switch selectedProvider.rateUnit {
        case .day:
            let borrowedDays = dailyOveragePercent / nextBufferCapacityPercent
            if borrowedDays < 1 {
                let hours = borrowedDays * 24
                return "\(formattedNumber(hours))h from tomorrow"
            }

            return "\(formattedNumber(borrowedDays))d from later"

        case .hour:
            let borrowedHours = dailyOveragePercent / nextBufferCapacityPercent
            return "\(formattedNumber(borrowedHours))h from later"
        }
    }

    var borrowedBufferValue: String {
        if !isTodayOverBudget {
            return "--"
        }

        switch selectedProvider.rateUnit {
        case .day:
            let borrowedDays = dailyOveragePercent / nextBufferCapacityPercent
            if borrowedDays < 1 {
                return "\(formattedNumber(borrowedDays * 24))h"
            }

            return "\(formattedNumber(borrowedDays))d"

        case .hour:
            let borrowedHours = dailyOveragePercent / nextBufferCapacityPercent
            return "\(formattedNumber(borrowedHours))h"
        }
    }

    var borrowedBufferLabel: String {
        "borrowed"
    }

    var focusTargetValue: String {
        safeTodayValue
    }

    var focusTargetLabel: String {
        switch selectedProvider.rateUnit {
        case .day:
            return "today's budget"
        case .hour:
            return "safe by now"
        }
    }

    var buildVersionLine: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(shortVersion) (\(build))"
    }

    var manualSnapshotDescription: String {
        if isCodexAutoSource(provider: selectedProvider, mode: sourceMode) {
            if isPlaceholderSnapshot {
                return "runwai is waiting for \(providerName) usage on this Mac. If needed, switch \(providerName) back to Manual in Settings."
            }

            return "runwai refreshes \(providerName) from your local Codex login on this Mac, with local history as a pacing fallback."
        }

        if selectedProvider == .gemini, sourceMode == .geminiCLI {
            if isPlaceholderSnapshot {
                return "runwai is waiting for Gemini CLI quota data. If needed, switch Gemini back to Manual in Settings."
            }

            return "runwai refreshes Gemini from your local Gemini CLI quota about once a minute."
        }

        if isPlaceholderSnapshot {
            return selectedProvider.resetHint
        }

        return "runwai is not synced yet, so the remaining percentage and reset time come from your manual \(providerName) snapshot."
    }

    private var codexWindowWarningLine: String? {
        guard
            isCodexAutoSource(provider: selectedProvider, mode: sourceMode),
            let codexDetail,
            let remaining = codexDetail.primaryRemainingPercent,
            let resetAt = codexDetail.primaryResetAt
        else {
            return nil
        }

        if remaining <= 0 {
            return "The \(providerName) 5h window is exhausted until \(Formatters.timeOnly.string(from: resetAt))."
        }

        if remaining <= 20 {
            return "The \(providerName) 5h window has \(formattedNumber(remaining))% left until \(Formatters.timeOnly.string(from: resetAt))."
        }

        return nil
    }
}
