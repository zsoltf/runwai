import Foundation

protocol AutomaticUsageSyncing {
    var provider: UsageProvider { get }
    var sourceMode: UsageSourceMode { get }
    func fetchPayload() async throws -> AutomaticUsageSyncPayload
}

struct AutomaticUsageSyncPayload {
    let provider: UsageProvider
    let usageSnapshot: UsageSnapshot
    let detail: AutomaticUsageSyncDetail?
    let historyPoints: [AutomaticUsageHistoryPoint]?

    init(
        provider: UsageProvider,
        usageSnapshot: UsageSnapshot,
        detail: AutomaticUsageSyncDetail?,
        historyPoints: [AutomaticUsageHistoryPoint]? = nil
    ) {
        self.provider = provider
        self.usageSnapshot = usageSnapshot
        self.detail = detail
        self.historyPoints = historyPoints
    }
}

struct AutomaticUsageHistoryPoint: Equatable {
    let timestamp: Date
    let remainingPercent: Double
}

enum AutomaticUsageSyncDetail: Equatable {
    case codex(CodexAutoSyncDetail)
    case gemini(GeminiAutoSyncDetail)
}

struct CodexAutoSyncDetail: Equatable {
    let planType: String?
    // Normalized 5-hour values, absent when the provider only reports a week.
    let primaryRemainingPercent: Double?
    let primaryResetAt: Date?
    let secondaryRemainingPercent: Double
    let secondaryResetAt: Date
}

struct GeminiAutoSyncDetail: Equatable {
    let modelID: String
    let tierName: String
}
