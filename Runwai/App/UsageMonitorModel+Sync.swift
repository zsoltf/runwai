import Foundation

extension UsageMonitorModel {
    static func makeAutomaticSyncServices() -> [UsageSourceMode: any AutomaticUsageSyncing] {
        [
            .codexApp: CodexQuotaSyncService()
        ]
    }

    func refreshNow(force: Bool = true) {
        now = Date()
        refreshAutomaticSources(force: force)
    }

    func refreshAutomaticSources(
        for providers: [UsageProvider] = UsageProvider.visibleProviders,
        force: Bool = false
    ) {
        for provider in providers {
            let mode = providerSourceMode(for: provider)

            guard
                mode.usesAutomaticRefresh,
                let syncService = automaticSyncServices[mode],
                syncService.provider == provider
            else {
                continue
            }

            if force == false,
               let pausedUntil = automaticRefreshPausedUntilByProvider[provider],
               pausedUntil > now {
                continue
            }

            refreshAutomaticSource(using: syncService)
        }
    }

    func refreshAutomaticSource(using syncService: any AutomaticUsageSyncing) {
        let provider = syncService.provider

        guard !activeSyncProviders.contains(provider) else {
            return
        }

        activeSyncProviders.insert(provider)

        Task {
            do {
                let payload = try await syncService.fetchPayload()
                await MainActor.run {
                    applyAutomaticSyncPayload(payload)
                    activeSyncProviders.remove(provider)
                }
            } catch {
                await MainActor.run {
                    syncErrorsByProvider[provider] = error.localizedDescription
                    automaticRefreshPausedUntilByProvider[provider] = automaticRefreshPauseUntil(for: provider, error: error)
                    activeSyncProviders.remove(provider)
                }
            }
        }
    }

    func applyAutomaticSyncPayload(_ payload: AutomaticUsageSyncPayload) {
        snapshotsByProvider[payload.provider] = payload.usageSnapshot
        placeholdersByProvider[payload.provider] = false
        syncErrorsByProvider[payload.provider] = nil
        automaticSourceDetailsByProvider[payload.provider] = payload.detail
        automaticRefreshPausedUntilByProvider[payload.provider] = nil

        if let historyPoints = payload.historyPoints, historyPoints.isEmpty == false {
            historiesByProvider[payload.provider] = normalizeImportedHistory(historyPoints)
            persistState(for: payload.provider, recordHistory: false)
        } else {
            persistState(for: payload.provider, recordHistory: true)
        }

        now = Date()
    }

    func automaticRefreshPauseUntil(for provider: UsageProvider, error: Error) -> Date? {
        nil
    }
}
