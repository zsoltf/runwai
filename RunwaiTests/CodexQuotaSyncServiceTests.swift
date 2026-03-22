import Foundation
import Testing
@testable import runwai

struct CodexQuotaSyncServiceTests {
    @Test
    func codexSparkSyncReadsLatestRateLimitsFromSqliteLog() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = tempDirectory.appendingPathComponent("logs_1.sqlite")

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let olderMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":4,"window_minutes":300,"reset_at":1774000000},"secondary":{"used_percent":12,"window_minutes":10080,"reset_at":1774500000}},"additional_rate_limits":{"GPT-5.3-Codex-Spark":{"primary":{"used_percent":3,"window_minutes":300,"reset_at":1774010000},"secondary":{"used_percent":4,"window_minutes":10080,"reset_at":1774512222}}}}"#
        let newerMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":18,"window_minutes":300,"reset_at":1774011111},"secondary":{"used_percent":15,"window_minutes":10080,"reset_at":1774512222}},"additional_rate_limits":{"GPT-5.3-Codex-Spark":{"primary":{"used_percent":6,"window_minutes":300,"reset_at":1774013333},"secondary":{"used_percent":5,"window_minutes":10080,"reset_at":1774512222}}}}"#

        try runSQLite(
            sql: """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                ts_nanos INTEGER NOT NULL,
                level TEXT NOT NULL,
                target TEXT NOT NULL,
                message TEXT
            );
            INSERT INTO logs (ts, ts_nanos, level, target, message) VALUES
              (1773950500, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(olderMessage.replacingOccurrences(of: "'", with: "''"))'),
              (1773951000, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(newerMessage.replacingOccurrences(of: "'", with: "''"))');
            """,
            databaseURL: databaseURL
        )

        let service = CodexQuotaSyncService(
            provider: .codexSpark,
            sourceMode: .codexSparkApp,
            additionalRateLimitName: "GPT-5.3-Codex-Spark",
            databaseURL: databaseURL
        )
        let payload = try await service.fetchPayload()

        #expect(payload.provider == .codexSpark)
        #expect(abs(payload.usageSnapshot.usedUnits - 5) < 0.1)
        #expect(payload.usageSnapshot.resetAt == Date(timeIntervalSince1970: 1_774_512_222))
        #expect(payload.historyPoints?.count == 2)
        #expect(abs((payload.historyPoints?.last?.remainingPercent ?? 0) - 95) < 0.1)

        guard case let .codex(detail)? = payload.detail else {
            Issue.record("Missing Codex Spark detail payload")
            return
        }

        #expect(abs(detail.primaryRemainingPercent - 94) < 0.1)
        #expect(detail.primaryResetAt == Date(timeIntervalSince1970: 1_774_013_333))
        #expect(detail.secondaryRemainingPercent == 95)
    }

    @Test
    func codexSyncReadsLatestRateLimitsFromSqliteLog() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = tempDirectory.appendingPathComponent("logs_1.sqlite")

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let olderMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":4,"window_minutes":300,"reset_at":1774000000},"secondary":{"used_percent":12,"window_minutes":10080,"reset_at":1774500000}}}"#
        let currentWindowOlderMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":9,"window_minutes":300,"reset_at":1774010000},"secondary":{"used_percent":13,"window_minutes":10080,"reset_at":1774512222}}}"#
        let newerMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":18,"window_minutes":300,"reset_at":1774011111},"secondary":{"used_percent":15,"window_minutes":10080,"reset_at":1774512222}}}"#

        try runSQLite(
            sql: """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                ts_nanos INTEGER NOT NULL,
                level TEXT NOT NULL,
                target TEXT NOT NULL,
                message TEXT
            );
            INSERT INTO logs (ts, ts_nanos, level, target, message) VALUES
              (1773950000, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(olderMessage.replacingOccurrences(of: "'", with: "''"))'),
              (1773950500, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(currentWindowOlderMessage.replacingOccurrences(of: "'", with: "''"))'),
              (1773951000, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(newerMessage.replacingOccurrences(of: "'", with: "''"))');
            """,
            databaseURL: databaseURL
        )

        let service = CodexQuotaSyncService(databaseURL: databaseURL)
        let payload = try await service.fetchPayload()

        #expect(payload.provider == .codex)
        #expect(abs(payload.usageSnapshot.usedUnits - 15) < 0.1)
        #expect(payload.usageSnapshot.resetAt == Date(timeIntervalSince1970: 1_774_512_222))
        #expect(payload.historyPoints?.count == 2)
        #expect(abs((payload.historyPoints?.last?.remainingPercent ?? 0) - 85) < 0.1)

        guard case let .codex(detail)? = payload.detail else {
            Issue.record("Missing Codex detail payload")
            return
        }

        #expect(abs(detail.primaryRemainingPercent - 82) < 0.1)
        #expect(detail.primaryResetAt == Date(timeIntervalSince1970: 1_774_011_111))
        #expect(detail.planType == "pro")
    }

    @Test
    func codexSyncPrefersLiveUsageSnapshotWhenAvailable() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = tempDirectory.appendingPathComponent("logs_1.sqlite")
        let authURL = tempDirectory.appendingPathComponent("auth.json")

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            URLProtocolStub.requestHandler = nil
        }

        let currentWindowOlderMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":9,"window_minutes":300,"reset_at":1774010000},"secondary":{"used_percent":13,"window_minutes":10080,"reset_at":1774512222}}}"#
        let newerMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":18,"window_minutes":300,"reset_at":1774011111},"secondary":{"used_percent":15,"window_minutes":10080,"reset_at":1774512222}}}"#

        try runSQLite(
            sql: """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                ts_nanos INTEGER NOT NULL,
                level TEXT NOT NULL,
                target TEXT NOT NULL,
                message TEXT
            );
            INSERT INTO logs (ts, ts_nanos, level, target, message) VALUES
              (1773950500, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(currentWindowOlderMessage.replacingOccurrences(of: "'", with: "''"))'),
              (1773951000, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(newerMessage.replacingOccurrences(of: "'", with: "''"))');
            """,
            databaseURL: databaseURL
        )

        try Data(#"{"tokens":{"access_token":"test-token"}}"#.utf8).write(to: authURL)

        URLProtocolStub.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            let body = Data(
                #"""
                {
                  "plan_type": "pro",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 2,
                      "limit_window_seconds": 18000,
                      "reset_at": 1774013333
                    },
                    "secondary_window": {
                      "used_percent": 20,
                      "limit_window_seconds": 604800,
                      "reset_at": 1774512222
                    }
                  }
                }
                """#.utf8
            )

            return (response, body)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        let service = CodexQuotaSyncService(
            databaseURL: databaseURL,
            authURL: authURL,
            usageURL: URL(string: "https://example.com/backend-api/wham/usage")!,
            urlSession: session
        )

        let payload = try await service.fetchPayload()

        #expect(payload.provider == .codex)
        #expect(abs(payload.usageSnapshot.usedUnits - 20) < 0.1)
        #expect(payload.usageSnapshot.resetAt == Date(timeIntervalSince1970: 1_774_512_222))
        #expect(payload.historyPoints?.count == 2)
        #expect(abs((payload.historyPoints?.last?.remainingPercent ?? 0) - 85) < 0.1)

        guard case let .codex(detail)? = payload.detail else {
            Issue.record("Missing Codex detail payload")
            return
        }

        #expect(abs(detail.primaryRemainingPercent - 98) < 0.1)
        #expect(detail.primaryResetAt == Date(timeIntervalSince1970: 1_774_013_333))
        #expect(detail.secondaryRemainingPercent == 80)
    }

    @Test
    func codexSparkSyncPrefersLiveUsageSnapshotWhenAvailable() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = tempDirectory.appendingPathComponent("logs_1.sqlite")
        let authURL = tempDirectory.appendingPathComponent("auth.json")

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            URLProtocolStub.requestHandler = nil
        }

        let olderMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":9,"window_minutes":300,"reset_at":1774010000},"secondary":{"used_percent":13,"window_minutes":10080,"reset_at":1774512222}},"additional_rate_limits":{"GPT-5.3-Codex-Spark":{"primary":{"used_percent":3,"window_minutes":300,"reset_at":1774010000},"secondary":{"used_percent":4,"window_minutes":10080,"reset_at":1774512222}}}}"#
        let newerMessage = #"websocket event: {"type":"codex.rate_limits","plan_type":"pro","rate_limits":{"primary":{"used_percent":18,"window_minutes":300,"reset_at":1774011111},"secondary":{"used_percent":15,"window_minutes":10080,"reset_at":1774512222}},"additional_rate_limits":{"GPT-5.3-Codex-Spark":{"primary":{"used_percent":6,"window_minutes":300,"reset_at":1774013333},"secondary":{"used_percent":5,"window_minutes":10080,"reset_at":1774512222}}}}"#

        try runSQLite(
            sql: """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                ts_nanos INTEGER NOT NULL,
                level TEXT NOT NULL,
                target TEXT NOT NULL,
                message TEXT
            );
            INSERT INTO logs (ts, ts_nanos, level, target, message) VALUES
              (1773950500, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(olderMessage.replacingOccurrences(of: "'", with: "''"))'),
              (1773951000, 0, 'INFO', 'codex_api::endpoint::responses_websocket', '\(newerMessage.replacingOccurrences(of: "'", with: "''"))');
            """,
            databaseURL: databaseURL
        )

        try Data(#"{"tokens":{"access_token":"test-token"}}"#.utf8).write(to: authURL)

        URLProtocolStub.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            let body = Data(
                #"""
                {
                  "plan_type": "pro",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 2,
                      "limit_window_seconds": 18000,
                      "reset_at": 1774013333
                    },
                    "secondary_window": {
                      "used_percent": 20,
                      "limit_window_seconds": 604800,
                      "reset_at": 1774512222
                    }
                  },
                  "additional_rate_limits": [
                    {
                      "limit_name": "GPT-5.3-Codex-Spark",
                      "rate_limit": {
                        "primary_window": {
                          "used_percent": 1,
                          "limit_window_seconds": 18000,
                          "reset_at": 1774016666
                        },
                        "secondary_window": {
                          "used_percent": 2,
                          "limit_window_seconds": 604800,
                          "reset_at": 1774512222
                        }
                      }
                    }
                  ]
                }
                """#.utf8
            )

            return (response, body)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        let service = CodexQuotaSyncService(
            provider: .codexSpark,
            sourceMode: .codexSparkApp,
            additionalRateLimitName: "GPT-5.3-Codex-Spark",
            databaseURL: databaseURL,
            authURL: authURL,
            usageURL: URL(string: "https://example.com/backend-api/wham/usage")!,
            urlSession: session
        )

        let payload = try await service.fetchPayload()

        #expect(payload.provider == .codexSpark)
        #expect(abs(payload.usageSnapshot.usedUnits - 2) < 0.1)
        #expect(payload.usageSnapshot.resetAt == Date(timeIntervalSince1970: 1_774_512_222))
        #expect(payload.historyPoints?.count == 2)
        #expect(abs((payload.historyPoints?.last?.remainingPercent ?? 0) - 95) < 0.1)

        guard case let .codex(detail)? = payload.detail else {
            Issue.record("Missing Codex Spark detail payload")
            return
        }

        #expect(abs(detail.primaryRemainingPercent - 99) < 0.1)
        #expect(detail.primaryResetAt == Date(timeIntervalSince1970: 1_774_016_666))
        #expect(detail.secondaryRemainingPercent == 98)
    }

    private func runSQLite(sql: String, databaseURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw SQLiteHarnessError.failed(stderr)
        }
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum SQLiteHarnessError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}
