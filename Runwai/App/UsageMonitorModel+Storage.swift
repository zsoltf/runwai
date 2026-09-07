import Foundation

extension UsageMonitorModel {
    var weeklyBudgetUnits: Double {
        get { snapshot.weeklyBudgetUnits }
        set { updateSnapshot { $0.weeklyBudgetUnits = max(newValue, 0) } }
    }

    var usedUnits: Double {
        get { snapshot.usedUnits }
        set { updateSnapshot { $0.usedUnits = max(newValue, 0) } }
    }

    var resetAt: Date {
        get { snapshot.resetAt }
        set { updateSnapshot { $0.resetAt = newValue } }
    }

    var remainingPercentInput: Double {
        get { summary.remainingPercent }
        set {
            updateSnapshot { snapshot in
                let clampedPercent = min(max(newValue, 0), 100)
                let budget = max(snapshot.weeklyBudgetUnits, 100)
                snapshot.weeklyBudgetUnits = budget
                snapshot.usedUnits = budget * (1 - (clampedPercent / 100))
            }
        }
    }

    func startFreshWindow() {
        let referenceNow = Date()
        snapshot = UsageSnapshot(
            weeklyBudgetUnits: max(snapshot.weeklyBudgetUnits, 100),
            usedUnits: 0,
            windowDuration: selectedProvider.defaultWindowDuration,
            resetAt: referenceNow.addingTimeInterval(selectedProvider.defaultWindowDuration),
            lastUpdatedAt: referenceNow
        )
        isPlaceholderSnapshot = false
        now = referenceNow
        persistCurrentState(recordHistory: true)
    }

    func applySampleValues() {
        let referenceNow = Date()
        snapshot = UsageSnapshot.sample(provider: selectedProvider, now: referenceNow)
        isPlaceholderSnapshot = false
        history = []
        now = referenceNow
        persistCurrentState(recordHistory: true)
    }

    func clearSelectedProviderData() {
        let placeholder = UsageSnapshot.placeholder(provider: selectedProvider)
        snapshot = placeholder
        history = []
        sourceMode = selectedProvider.defaultSourceMode
        isPlaceholderSnapshot = true
        syncErrorsByProvider[selectedProvider] = nil
        automaticSourceDetailsByProvider[selectedProvider] = nil
        now = Date()
        store.clearSnapshot(for: selectedProvider)
        store.clearHistory(for: selectedProvider)
        store.clearMode(for: selectedProvider)
        store.saveSelectedProvider(selectedProvider)
        store.saveGlassAppearance(glassAppearance)
        store.saveHeroStyle(heroStyle)
    }

    func updateSnapshot(_ mutate: (inout UsageSnapshot) -> Void) {
        var updatedSnapshot = snapshot
        mutate(&updatedSnapshot)
        updatedSnapshot.windowDuration = selectedProvider.defaultWindowDuration
        updatedSnapshot.lastUpdatedAt = Date()
        isPlaceholderSnapshot = false
        snapshot = updatedSnapshot
        now = updatedSnapshot.lastUpdatedAt
        persistCurrentState(recordHistory: true)
    }

    func persistCurrentState(recordHistory: Bool = false) {
        persistState(for: selectedProvider, recordHistory: recordHistory)
    }

    func persistState(for provider: UsageProvider, recordHistory: Bool = false) {
        guard let snapshot = snapshotsByProvider[provider] else {
            return
        }

        var updatedHistory = historiesByProvider[provider] ?? []
        if recordHistory {
            updatedHistory = historyRecording(snapshot: snapshot, history: updatedHistory)
            historiesByProvider[provider] = updatedHistory
        }

        store.save(snapshot, for: provider)
        store.saveHistory(updatedHistory, for: provider)
        store.saveMode(providerSourceMode(for: provider), for: provider)
        store.saveSelectedProvider(selectedProvider)
        store.saveGlassAppearance(glassAppearance)
        store.saveHeroStyle(heroStyle)
    }

    var snapshot: UsageSnapshot {
        get {
            snapshotsByProvider[selectedProvider] ?? UsageSnapshot.placeholder(provider: selectedProvider)
        }
        set {
            snapshotsByProvider[selectedProvider] = newValue
        }
    }

    var history: [UsageHistoryPoint] {
        get {
            historiesByProvider[selectedProvider] ?? []
        }
        set {
            historiesByProvider[selectedProvider] = newValue
        }
    }

    var isPlaceholderSnapshot: Bool {
        get {
            placeholdersByProvider[selectedProvider] ?? true
        }
        set {
            placeholdersByProvider[selectedProvider] = newValue
        }
    }

    var sourceMode: UsageSourceMode {
        get {
            sourceModesByProvider[selectedProvider] ?? selectedProvider.defaultSourceMode
        }
        set {
            sourceModesByProvider[selectedProvider] = newValue
        }
    }

    func providerSourceMode(for provider: UsageProvider) -> UsageSourceMode {
        sourceModesByProvider[provider] ?? provider.defaultSourceMode
    }

    func isCodexAutoSource(provider: UsageProvider, mode: UsageSourceMode) -> Bool {
        switch (provider, mode) {
        case (.codex, .codexApp), (.codexSpark, .codexSparkApp):
            return true
        default:
            return false
        }
    }

    var selectedSyncError: String? {
        syncErrorsByProvider[selectedProvider]
    }

    var selectedAutomaticSourceDetail: AutomaticUsageSyncDetail? {
        automaticSourceDetailsByProvider[selectedProvider] ?? nil
    }

    var codexDetail: CodexAutoSyncDetail? {
        guard case let .codex(detail)? = selectedAutomaticSourceDetail else {
            return nil
        }

        return detail
    }

    func windowStart(for snapshot: UsageSnapshot) -> Date {
        snapshot.resetAt.addingTimeInterval(-snapshot.windowDuration)
    }

    func remainingPercent(for snapshot: UsageSnapshot) -> Double {
        let budget = max(snapshot.weeklyBudgetUnits, 1)
        let remaining = max(budget - max(snapshot.usedUnits, 0), 0)
        return (remaining / budget) * 100
    }
}
