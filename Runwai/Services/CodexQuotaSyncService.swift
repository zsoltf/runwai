import Foundation

struct CodexQuotaSnapshot: Equatable {
    let capturedAt: Date
    let planType: String?
    let primaryRemainingPercent: Double?
    let primaryResetAt: Date?
    let primaryWindowMinutes: Double?
    let secondaryRemainingPercent: Double
    let secondaryResetAt: Date
    let secondaryWindowMinutes: Double
    let historyPoints: [AutomaticUsageHistoryPoint]

    var usageSnapshot: UsageSnapshot {
        UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: 100 - secondaryRemainingPercent,
            windowDuration: secondaryWindowMinutes * 60,
            resetAt: secondaryResetAt,
            lastUpdatedAt: capturedAt
        )
    }

    var detail: CodexAutoSyncDetail {
        CodexAutoSyncDetail(
            planType: planType,
            primaryRemainingPercent: primaryRemainingPercent,
            primaryResetAt: primaryResetAt,
            secondaryRemainingPercent: secondaryRemainingPercent,
            secondaryResetAt: secondaryResetAt
        )
    }
}

enum CodexQuotaSyncError: LocalizedError {
    case authMissing
    case databaseMissing
    case httpFailure(Int)
    case invalidResponse
    case noRateLimitsFound
    case sqliteUnavailable
    case syncFailed(String)
    case tokenMissing

    var errorDescription: String? {
        switch self {
        case .authMissing:
            return "Codex auth is not available on this Mac yet."
        case .databaseMissing:
            return "Codex logs are not available on this Mac yet."
        case .httpFailure(let statusCode):
            return "Codex usage refresh returned HTTP \(statusCode)."
        case .invalidResponse:
            return "runwai could not read the latest Codex usage response."
        case .noRateLimitsFound:
            return "No local Codex rate-limit event was found yet."
        case .sqliteUnavailable:
            return "sqlite3 is unavailable on this Mac."
        case .syncFailed(let message):
            return message
        case .tokenMissing:
            return "Codex auth token is missing on this Mac."
        }
    }
}

struct CodexQuotaSyncService: AutomaticUsageSyncing {
    let provider: UsageProvider
    let sourceMode: UsageSourceMode
    private let additionalRateLimitName: String?

    private let authURL: URL
    private let databaseURL: URL
    private let sqliteExecutableURL: URL
    private let urlSession: URLSession
    private let usageURL: URL
    private let queryTimeout: TimeInterval = 10

    init(
        provider: UsageProvider = .codex,
        sourceMode: UsageSourceMode = .codexApp,
        additionalRateLimitName: String? = nil,
        codexHome: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex"),
        sqliteExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3"),
        usageURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        urlSession: URLSession = .shared
    ) {
        self.provider = provider
        self.sourceMode = sourceMode
        self.additionalRateLimitName = additionalRateLimitName
        self.authURL = codexHome.appendingPathComponent("auth.json")
        self.databaseURL = codexHome.appendingPathComponent("logs_1.sqlite")
        self.sqliteExecutableURL = sqliteExecutableURL
        self.usageURL = usageURL
        self.urlSession = urlSession
    }

    init(
        provider: UsageProvider = .codex,
        sourceMode: UsageSourceMode = .codexApp,
        additionalRateLimitName: String? = nil,
        databaseURL: URL,
        authURL: URL? = nil,
        sqliteExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3"),
        usageURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        urlSession: URLSession = .shared
    ) {
        self.provider = provider
        self.sourceMode = sourceMode
        self.additionalRateLimitName = additionalRateLimitName
        self.databaseURL = databaseURL
        self.authURL = authURL ?? databaseURL.deletingLastPathComponent().appendingPathComponent("auth.json")
        self.sqliteExecutableURL = sqliteExecutableURL
        self.usageURL = usageURL
        self.urlSession = urlSession
    }

    func fetchPayload() async throws -> AutomaticUsageSyncPayload {
        let localEvents = (try? loadRecentLocalEvents()) ?? []

        do {
            let snapshot = try await loadCurrentSnapshot(localEvents: localEvents)
            return payload(from: snapshot)
        } catch {
            guard let fallbackSnapshot = makeLatestLocalSnapshot(from: localEvents) else {
                throw error
            }

            return payload(from: fallbackSnapshot)
        }
    }

    private func payload(from snapshot: CodexQuotaSnapshot) -> AutomaticUsageSyncPayload {
        AutomaticUsageSyncPayload(
            provider: provider,
            usageSnapshot: snapshot.usageSnapshot,
            detail: .codex(snapshot.detail),
            historyPoints: snapshot.historyPoints
        )
    }

    private func loadCurrentSnapshot(localEvents: [ParsedCodexRateLimitEvent]) async throws -> CodexQuotaSnapshot {
        let token = try loadAccessToken()

        var request = URLRequest(url: usageURL)
        request.timeoutInterval = queryTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexQuotaSyncError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw CodexQuotaSyncError.httpFailure(httpResponse.statusCode)
        }

        let usage = try JSONDecoder().decode(CodexUsageEnvelope.self, from: data)
        let selectedRateLimit = try selectedLiveRateLimit(from: usage)
        let windows = try CodexUsageWindows([
            selectedRateLimit.primaryWindow?.rateLimitWindow,
            selectedRateLimit.secondaryWindow?.rateLimitWindow
        ])
        let secondaryResetAt = Date(timeIntervalSince1970: windows.weekly.resetAt)
        let historyPoints = localHistoryPoints(from: localEvents, matchingSecondaryResetAt: secondaryResetAt)

        return CodexQuotaSnapshot(
            capturedAt: Date(),
            planType: usage.planType,
            primaryRemainingPercent: windows.fiveHour.map { (100 - $0.usedPercent).clamped(to: 0...100) },
            primaryResetAt: windows.fiveHour.map { Date(timeIntervalSince1970: $0.resetAt) },
            primaryWindowMinutes: windows.fiveHour?.windowMinutes,
            secondaryRemainingPercent: (100 - windows.weekly.usedPercent).clamped(to: 0...100),
            secondaryResetAt: secondaryResetAt,
            secondaryWindowMinutes: windows.weekly.windowMinutes,
            historyPoints: historyPoints
        )
    }

    private func loadAccessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw CodexQuotaSyncError.authMissing
        }

        let data = try Data(contentsOf: authURL)
        let auth = try JSONDecoder().decode(CodexAuthEnvelope.self, from: data)
        guard let token = auth.tokens.accessToken?.nonEmptyString else {
            throw CodexQuotaSyncError.tokenMissing
        }

        return token
    }

    private func loadRecentLocalEvents() throws -> [ParsedCodexRateLimitEvent] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CodexQuotaSyncError.databaseMissing
        }

        guard FileManager.default.isExecutableFile(atPath: sqliteExecutableURL.path) else {
            throw CodexQuotaSyncError.sqliteUnavailable
        }

        let process = Process()
        process.qualityOfService = .userInitiated
        process.executableURL = sqliteExecutableURL
        process.arguments = [
            "-batch",
            "-readonly",
            "-separator",
            "\t",
            databaseURL.path,
            recentRateLimitsQuery
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        try waitForExit(of: process)

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            let message = stderr.nonEmptyString ?? stdout.nonEmptyString ?? "Codex rate-limit query failed."
            throw CodexQuotaSyncError.syncFailed(message)
        }

        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw CodexQuotaSyncError.noRateLimitsFound
        }

        return try trimmed
            .split(whereSeparator: \.isNewline)
            .map(parseRateLimitEvent)
    }

    private func makeLatestLocalSnapshot(from events: [ParsedCodexRateLimitEvent]) -> CodexQuotaSnapshot? {
        guard let latestEvent = events.last else {
            return nil
        }

        return CodexQuotaSnapshot(
            capturedAt: latestEvent.capturedAt,
            planType: latestEvent.planType,
            primaryRemainingPercent: latestEvent.primaryRemainingPercent,
            primaryResetAt: latestEvent.primaryResetAt,
            primaryWindowMinutes: latestEvent.primaryWindowMinutes,
            secondaryRemainingPercent: latestEvent.secondaryRemainingPercent,
            secondaryResetAt: latestEvent.secondaryResetAt,
            secondaryWindowMinutes: latestEvent.secondaryWindowMinutes,
            historyPoints: localHistoryPoints(from: events, matchingSecondaryResetAt: latestEvent.secondaryResetAt)
        )
    }

    private func localHistoryPoints(
        from events: [ParsedCodexRateLimitEvent],
        matchingSecondaryResetAt resetAt: Date
    ) -> [AutomaticUsageHistoryPoint] {
        events
            .filter { abs($0.secondaryResetAt.timeIntervalSince(resetAt)) < 1 }
            .map {
                AutomaticUsageHistoryPoint(
                    timestamp: $0.capturedAt,
                    remainingPercent: $0.secondaryRemainingPercent
                )
            }
    }

    private func parseRateLimitEvent(_ line: Substring) throws -> ParsedCodexRateLimitEvent {
        let pieces = line.split(
            separator: "\t",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard
            pieces.count >= 2,
            let timestamp = TimeInterval(String(pieces[0]))
        else {
            throw CodexQuotaSyncError.invalidResponse
        }

        let message = String(pieces[1])
        let prefix = "websocket event: "
        guard message.hasPrefix(prefix) else {
            throw CodexQuotaSyncError.invalidResponse
        }

        let payloadData = Data(message.dropFirst(prefix.count).utf8)
        let payload = try JSONDecoder().decode(CodexRateLimitsEnvelope.self, from: payloadData)

        guard payload.type == "codex.rate_limits" else {
            throw CodexQuotaSyncError.invalidResponse
        }

        let selectedRateLimits = try selectedLoggedRateLimits(from: payload)

        let windows = try CodexUsageWindows([selectedRateLimits.primary, selectedRateLimits.secondary])

        return ParsedCodexRateLimitEvent(
            capturedAt: Date(timeIntervalSince1970: timestamp),
            planType: payload.planType,
            primaryRemainingPercent: windows.fiveHour.map { (100 - $0.usedPercent).clamped(to: 0...100) },
            primaryResetAt: windows.fiveHour.map { Date(timeIntervalSince1970: $0.resetAt) },
            primaryWindowMinutes: windows.fiveHour?.windowMinutes,
            secondaryRemainingPercent: (100 - windows.weekly.usedPercent).clamped(to: 0...100),
            secondaryResetAt: Date(timeIntervalSince1970: windows.weekly.resetAt),
            secondaryWindowMinutes: windows.weekly.windowMinutes
        )
    }

    private func waitForExit(of process: Process) throws {
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + queryTimeout) == .timedOut {
            if process.isRunning {
                process.terminate()
            }

            _ = semaphore.wait(timeout: .now() + 1)
            throw CodexQuotaSyncError.syncFailed("Codex rate-limit refresh timed out.")
        }
    }

    private func selectedLiveRateLimit(from usage: CodexUsageEnvelope) throws -> CodexUsageEnvelope.RateLimit {
        guard let additionalRateLimitName else {
            return usage.rateLimit
        }

        guard let matchingRateLimit = usage.additionalRateLimits?.first(where: { $0.limitName == additionalRateLimitName }) else {
            throw CodexQuotaSyncError.syncFailed("\(provider.displayName) usage is not available in this Codex session yet.")
        }

        return matchingRateLimit.rateLimit
    }

    private func selectedLoggedRateLimits(from payload: CodexRateLimitsEnvelope) throws -> CodexRateLimitsPayload {
        guard let additionalRateLimitName else {
            return payload.rateLimits
        }

        guard let matchingRateLimits = payload.additionalRateLimits?[additionalRateLimitName] else {
            throw CodexQuotaSyncError.syncFailed("\(provider.displayName) usage was not present in the latest local Codex event.")
        }

        return matchingRateLimits
    }

    private var recentRateLimitsQuery: String {
        """
        SELECT ts, message
        FROM logs
        WHERE target = 'codex_api::endpoint::responses_websocket'
          AND message LIKE 'websocket event: {"type":"codex.rate_limits"%'
        ORDER BY id ASC
        LIMIT 500;
        """
    }
}

private struct ParsedCodexRateLimitEvent: Equatable {
    let capturedAt: Date
    let planType: String?
    let primaryRemainingPercent: Double?
    let primaryResetAt: Date?
    let primaryWindowMinutes: Double?
    let secondaryRemainingPercent: Double
    let secondaryResetAt: Date
    let secondaryWindowMinutes: Double
}

private struct CodexAuthEnvelope: Decodable {
    let tokens: Tokens

    struct Tokens: Decodable {
        let accessToken: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }
}

private struct CodexUsageEnvelope: Decodable {
    let planType: String?
    let rateLimit: RateLimit
    let additionalRateLimits: [AdditionalRateLimit]?

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        private enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Double
        let resetAt: TimeInterval

        var rateLimitWindow: CodexRateLimitWindow {
            CodexRateLimitWindow(
                usedPercent: usedPercent,
                windowMinutes: limitWindowSeconds / 60,
                resetAt: resetAt
            )
        }

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }
    }

    struct AdditionalRateLimit: Decodable {
        let limitName: String
        let rateLimit: RateLimit

        private enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case rateLimit = "rate_limit"
        }
    }
}

private struct CodexRateLimitsEnvelope: Decodable {
    let type: String
    let planType: String?
    let rateLimits: CodexRateLimitsPayload
    let additionalRateLimits: [String: CodexRateLimitsPayload]?

    private enum CodingKeys: String, CodingKey {
        case type
        case planType = "plan_type"
        case rateLimits = "rate_limits"
        case additionalRateLimits = "additional_rate_limits"
    }
}

private struct CodexRateLimitsPayload: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Double
    let resetAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetAt = "reset_at"
    }
}

// Backend slots are positional: weekly usage moves to primary when 5h is absent.
private struct CodexUsageWindows {
    let fiveHour: CodexRateLimitWindow?
    let weekly: CodexRateLimitWindow

    init(_ candidates: [CodexRateLimitWindow?]) throws {
        let windows = candidates.compactMap { $0 }
        guard let weekly = windows.first(where: { $0.windowMinutes == 7 * 24 * 60 }) else {
            throw CodexQuotaSyncError.invalidResponse
        }
        self.weekly = weekly
        self.fiveHour = windows.first(where: { $0.windowMinutes == 5 * 60 })
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    var nonEmptyString: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
