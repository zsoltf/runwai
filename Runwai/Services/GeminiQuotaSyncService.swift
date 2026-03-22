import Foundation

struct GeminiQuotaSnapshot: Equatable {
    let remainingPercent: Double
    let resetAt: Date
    let modelID: String
    let tierName: String

    var usageSnapshot: UsageSnapshot {
        UsageSnapshot(
            weeklyBudgetUnits: 100,
            usedUnits: 100 - remainingPercent,
            windowDuration: UsageProvider.gemini.defaultWindowDuration,
            resetAt: resetAt,
            lastUpdatedAt: Date()
        )
    }

    var detail: GeminiAutoSyncDetail {
        GeminiAutoSyncDetail(
            modelID: modelID,
            tierName: tierName
        )
    }
}

enum GeminiQuotaSyncError: LocalizedError {
    case helperMissing
    case invalidResponse
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "Gemini quota helper is missing from the app bundle."
        case .invalidResponse:
            return "Gemini CLI returned a response runwai could not read."
        case .syncFailed(let message):
            return message
        }
    }
}

struct GeminiQuotaSyncService: AutomaticUsageSyncing {
    let provider = UsageProvider.gemini
    let sourceMode = UsageSourceMode.geminiCLI

    private let bundle: Bundle
    private let helperTimeout: TimeInterval = 10

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func fetchPayload() async throws -> AutomaticUsageSyncPayload {
        let snapshot = try await Task.detached(priority: .utility) {
            try runHelper(bundle: bundle)
        }.value

        return AutomaticUsageSyncPayload(
            provider: provider,
            usageSnapshot: snapshot.usageSnapshot,
            detail: .gemini(snapshot.detail)
        )
    }

    private func runHelper(bundle: Bundle) throws -> GeminiQuotaSnapshot {
        let helperURL =
            bundle.url(
                forResource: "gemini_quota_snapshot",
                withExtension: "mjs",
                subdirectory: "Scripts"
            ) ??
            bundle.url(
                forResource: "gemini_quota_snapshot",
                withExtension: "mjs"
            )

        guard let helperURL else {
            throw GeminiQuotaSyncError.helperMissing
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try resolveNodePath())
        process.arguments = [helperURL.path]
        process.environment = helperEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        try waitForExit(of: process)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            let message = stderr.nonEmptyString ?? stdout.nonEmptyString ?? "Gemini CLI quota helper failed."
            throw GeminiQuotaSyncError.syncFailed(message)
        }

        guard
            let jsonLine = stdout
                .split(whereSeparator: \.isNewline)
                .reversed()
                .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") })
        else {
            throw GeminiQuotaSyncError.invalidResponse
        }

        let payloadData = Data(String(jsonLine).utf8)
        let payload = try JSONDecoder().decode(GeminiQuotaHelperPayload.self, from: payloadData)

        guard payload.ok else {
            throw GeminiQuotaSyncError.syncFailed(payload.error ?? "Gemini CLI quota helper returned an error.")
        }

        guard
            let bucket = payload.bucket,
            let remainingFraction = bucket.remainingFraction,
            let resetAtString = bucket.resetTime
        else {
            throw GeminiQuotaSyncError.invalidResponse
        }

        guard let resetAt = ISO8601DateFormatter().date(from: resetAtString) else {
            throw GeminiQuotaSyncError.invalidResponse
        }

        return GeminiQuotaSnapshot(
            remainingPercent: min(max(remainingFraction * 100, 0), 100),
            resetAt: resetAt,
            modelID: bucket.modelID,
            tierName: payload.tier ?? "Gemini CLI"
        )
    }

    private func helperEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let commonPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPATH = environment["PATH"], !currentPATH.isEmpty {
            environment["PATH"] = "\(commonPATH):\(currentPATH)"
        } else {
            environment["PATH"] = commonPATH
        }
        return environment
    }

    private func resolveNodePath() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        throw GeminiQuotaSyncError.syncFailed("Node.js is required to read Gemini CLI quota.")
    }

    private func waitForExit(of process: Process) throws {
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + helperTimeout) == .timedOut {
            if process.isRunning {
                process.terminate()
            }

            _ = semaphore.wait(timeout: .now() + 1)
            throw GeminiQuotaSyncError.syncFailed("Gemini CLI refresh timed out.")
        }
    }
}

private struct GeminiQuotaHelperPayload: Decodable {
    let ok: Bool
    let tier: String?
    let bucket: GeminiQuotaHelperBucket?
    let error: String?
}

private struct GeminiQuotaHelperBucket: Decodable {
    let modelID: String
    let remainingFraction: Double?
    let resetTime: String?

    private enum CodingKeys: String, CodingKey {
        case modelID = "modelId"
        case remainingFraction
        case resetTime
    }
}

private extension String {
    var nonEmptyString: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
