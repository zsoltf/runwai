import Foundation
import Testing
@testable import runwai

@MainActor
struct AgentActivityTests {
    @Test(arguments: [false, true])
    func originalRecoveryRequiresCompleteMatchingReadAndKeepsOtherFailures(fileBacked: Bool) async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        model.selectProject("/project")
        let text = String(repeating: "x", count: fileBacked ? 1_048_577 : 8)
        var a = message("a", text: ""), b = message("b", text: "")
        a["original_text"] = NSNull(); a["text_complete"] = false
        b["original_text"] = NSNull(); b["text_complete"] = false
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [a, b]]))
        let first = try #require(model.messages.first { $0.id == "a" })
        let second = try #require(model.messages.first { $0.id == "b" })
        let failedA = try #require(model.loadOriginal(first))
        let failedB = try #require(model.loadOriginal(second))
        await model.apply(try event("error", generation: 1, requestID: failedA,
            payload: ["operation": "read_message", "code": "read_failed", "message": "A failed"]))
        await model.apply(try event("error", generation: 1, requestID: failedB,
            payload: ["operation": "read_message", "code": "read_failed", "message": "B failed"]))
        let retry = try #require(model.loadOriginal(first))
        #expect(model.errorMessage == "A failed")
        await model.apply(try event("message_text", generation: 1, requestID: failedA,
            payload: ["message_id": "a", "byte_offset": 0, "total_bytes": text.utf8.count, "text": text, "done": true]))
        #expect(model.errorMessage == "A failed")
        await model.apply(try event("message_text", generation: 1, requestID: retry,
            payload: ["message_id": "a", "byte_offset": 0, "total_bytes": text.utf8.count, "text": "x", "done": false]))
        #expect(model.errorMessage == "A failed")
        #expect(model.fullTexts["a"] == nil)
        #expect(model.originalFiles["a"] == nil)
        await model.apply(try event("message_text", generation: 1, requestID: retry,
            payload: ["message_id": "a", "byte_offset": 1, "total_bytes": text.utf8.count, "text": String(text.dropFirst()), "done": true]))
        if fileBacked {
            #expect(try String(contentsOf: #require(model.originalFiles["a"]), encoding: .utf8) == text)
        } else { #expect(model.fullTexts["a"] == text) }
        #expect(model.errorMessage == "B failed")
        let retryB = try #require(model.loadOriginal(second))
        await model.apply(try event("message_text", generation: 1, requestID: retryB,
            payload: ["message_id": "b", "byte_offset": 0, "total_bytes": 1, "text": "B", "done": true]))
        #expect(model.errorMessage == nil)
    }

    @Test
    func onlyCurrentModelOutputRecoversSummaryFailureAndLaterFailureReturns() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        model.selectProject("/project")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [message("a", text: "Original")]]))
        let failure: [String: Any] = ["operation": "summarize", "code": "model_failed", "message": "Summary failed"]
        let items = [["message_id": "a", "text": "Summary"]]
        await model.apply(try event("error", generation: 1, payload: failure))
        await model.apply(try event("state", generation: 1, payload: ["summary_status": "ready"]))
        #expect(model.errorMessage == "Summary failed")
        await model.apply(try event("summaries", generation: 1, payload: ["source": "cache", "items": items]))
        #expect(model.summaries["a"] == "Summary")
        #expect(model.errorMessage == "Summary failed")
        await model.apply(try event("summaries", generation: 1, payload: ["source": "model", "items": []]))
        await model.apply(try event("summaries", generation: 0, payload: ["source": "model", "items": items]))
        await model.apply(try event("summaries", generation: 1, revision: "stale", payload: ["source": "model", "items": items]))
        #expect(model.errorMessage == "Summary failed")
        await model.apply(try event("summaries", generation: 1, payload: ["source": "model", "items": items]))
        #expect(model.errorMessage == nil)
        await model.apply(try event("error", generation: 1, payload: failure))
        #expect(model.errorMessage == "Summary failed")
        await model.apply(try event("reset", generation: 1, revision: "replacement", payload: [:]))
        #expect(model.errorMessage == nil)
        await model.apply(try event("snapshot", generation: 1, revision: "replacement", payload: ["messages": []]))
        await model.apply(try event("error", generation: 1, revision: "replacement", payload: failure))
        await model.apply(try event("summaries", generation: 1, payload: ["source": "model", "items": items]))
        #expect(model.errorMessage == "Summary failed")
        model.selectProject("/other")
        #expect(model.errorMessage == nil)
        await model.apply(try event("error", generation: 1, payload: failure))
        #expect(model.errorMessage == nil)
    }

    @Test
    func pageRecoveryClearsOnlyMatchingFailureNotSummaryFailure() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        model.selectProject("/project")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [], "has_more": true, "before_cursor": "older"]))
        let page = try #require(model.loadOlder())
        await model.apply(try event("error", generation: 1, requestID: page, payload: ["operation": "load_older", "code": "read_failed", "message": "Page failed"]))
        await model.apply(try event("error", generation: 1, payload: ["operation": "summarize", "code": "model_failed", "message": "Summary failed"]))
        let retry = try #require(model.loadOlder())
        #expect(model.errorMessage == "Page failed")
        await model.apply(try event("page", generation: 1, requestID: page, payload: ["messages": []]))
        #expect(model.errorMessage == "Page failed")
        await model.apply(try event("page", generation: 1, requestID: retry, payload: ["messages": []]))
        #expect(model.errorMessage == "Summary failed")
        await model.apply(try event("summaries", generation: 1, payload: ["source": "model", "items": [["message_id": "a", "text": "Fresh"]]]))
        #expect(model.errorMessage == nil)
    }

    @Test
    func followRecoveryRequiresExactFailureScopeAndPreservesOtherFailures() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        model.selectProject("/project")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [message("a", text: "Original")]]))
        let failure: [String: Any] = ["operation": "follow", "code": "read_failed", "message": "Follow failed"]
        await model.apply(try event("error", generation: 1, sequence: 10, payload: failure))
        await model.apply(try event("error", generation: 1, sequence: 11, payload: failure))
        await model.apply(try event("error", generation: 1, payload: ["operation": "summarize", "code": "cache_busy", "message": "Cache busy"]))
        await model.apply(try event("state", generation: 1, payload: ["loading": false]))
        #expect(model.errorMessage == "Follow failed")
        await model.apply(try event("updates", generation: 1, payload: ["messages": [message("b", text: "New update")]]))
        #expect(model.errorMessage == "Follow failed")
        let recovery: [String: Any] = ["operation": "follow", "error_seq": 11]
        await model.apply(try event("recovered", generation: 1, payload: ["operation": "follow", "error_seq": 10]))
        await model.apply(try event("recovered", generation: 0, payload: recovery))
        await model.apply(try event("recovered", generation: 1, revision: "old", payload: recovery))
        await model.apply(try event("recovered", generation: 1, sessionID: "other", payload: recovery))
        await model.apply(try event("recovered", generation: 1, requestID: "other", payload: recovery))
        await model.apply(try event("recovered", generation: 1, payload: ["operation": "summarize", "error_seq": 11]))
        #expect(model.errorMessage == "Follow failed")
        await model.apply(try event("recovered", generation: 1, payload: recovery))
        #expect(model.errorMessage == "Cache busy")
        await model.apply(try event("summaries", generation: 1, payload: ["source": "cache", "items": [["message_id": "a", "text": "Cached"]]]))
        #expect(model.errorMessage == "Cache busy")
        await model.apply(try event("summaries", generation: 1, payload: ["source": "model", "items": [["message_id": "a", "text": "Fresh"]]]))
        #expect(model.errorMessage == nil)
        await model.apply(try event("error", generation: 1, sequence: 20, payload: failure))
        await model.apply(try event("recovered", generation: 1, payload: recovery))
        #expect(model.errorMessage == "Follow failed")
        await model.apply(try event("reset", generation: 1, revision: "replacement", payload: [:]))
        #expect(model.errorMessage == nil)
        await model.apply(try event("snapshot", generation: 1, revision: "replacement", payload: ["messages": []]))
        await model.apply(try event("error", generation: 1, revision: "replacement", sequence: 21, payload: failure))
        await model.apply(try event("recovered", generation: 1, payload: ["operation": "follow", "error_seq": 21]))
        #expect(model.errorMessage == "Follow failed")
        model.selectProject("/other")
        #expect(model.errorMessage == nil)
        await model.apply(try event("error", generation: 1, sequence: 22, payload: failure))
        #expect(model.errorMessage == nil)
    }

    @Test(arguments: [8, 1_048_577])
    func invalidOriginalCompletionKeepsFailureUntilValidRetry(total: Int) async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        model.selectProject("/project")
        var deferred = message("a", text: "")
        deferred["original_text"] = NSNull(); deferred["text_complete"] = false
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [deferred]]))
        let original = try #require(model.messages.first)
        let request = try #require(model.loadOriginal(original))
        await model.apply(try event("message_text", generation: 1, requestID: request,
            payload: ["message_id": "a", "byte_offset": 0, "total_bytes": total, "text": "half", "done": true]))
        let failure = try #require(model.errorMessage)
        #expect(model.fullTexts["a"] == nil)
        #expect(model.originalFiles["a"] == nil)
        #expect(!model.isOriginalLoading("a"))
        let retry = try #require(model.loadOriginal(original))
        #expect(model.errorMessage == failure)
        await model.apply(try event("message_text", generation: 1, requestID: retry, revision: "stale",
            payload: ["message_id": "a", "byte_offset": 0, "total_bytes": total, "text": String(repeating: "x", count: total), "done": true]))
        #expect(model.errorMessage == failure)
        await model.apply(try event("message_text", generation: 1, requestID: retry,
            payload: ["message_id": "a", "byte_offset": 0, "total_bytes": total, "text": String(repeating: "x", count: total), "done": true]))
        #expect(model.errorMessage == nil)
    }

    @Test
    func partialCatalogRetainsFailureAndOnlyLaterFullRevisionRecovers() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        await model.apply(try event("error", generation: nil, requestID: "discover",
            payload: ["operation": "discover", "catalog_revision": 1, "code": "discovery_failed", "message": "Catalog failed"]))
        await model.apply(try event("projects", generation: nil, requestID: "discover",
            payload: ["revision": 1, "partial": true, "items": []]))
        #expect(model.catalogPartial)
        #expect(model.errorMessage == "Catalog failed")
        let selection = model.selectProject("/project")
        await model.apply(try event("snapshot", generation: 1, requestID: selection, payload: ["messages": []]))
        #expect(model.errorMessage == "Catalog failed")
        await model.apply(try event("error", generation: nil,
            payload: ["operation": "discover", "catalog_revision": 2, "code": "discovery_failed", "message": "Periodic catalog failed"]))
        await model.apply(try event("projects", generation: nil, payload: ["revision": 2, "partial": true, "items": []]))
        await model.apply(try event("projects", generation: nil, payload: ["revision": 1, "partial": false, "items": []]))
        #expect(model.errorMessage == "Periodic catalog failed")
        #expect(model.catalogPartial)
        await model.apply(try event("error", generation: 1,
            payload: ["operation": "summarize", "code": "model_failed", "message": "Summary failed"]))
        await model.apply(try event("projects", generation: nil, payload: ["revision": 3, "partial": false, "items": []]))
        #expect(!model.catalogPartial)
        #expect(model.errorMessage == "Summary failed")
        await model.apply(try event("error", generation: nil, payload: ["message": "Connection failed"]))
        await model.apply(try event("projects", generation: nil, payload: ["revision": 4, "partial": false, "items": []]))
        #expect(model.errorMessage == "Connection failed")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": []]))
        #expect(model.errorMessage == "Connection failed")
        await model.apply(try event("hello", generation: 0, payload: [:]))
        #expect(model.errorMessage == nil)
    }

    @Test
    func newConnectionCatalogRevisionsDoNotPrematurelyClearOldWarning() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        await model.apply(try event("error", generation: nil, payload: [
            "operation": "discover", "catalog_revision": 50, "message": "Catalog failed"]))
        await model.apply(try event("hello", generation: 0, payload: [:]))
        #expect(model.errorMessage == "Catalog failed")
        await model.apply(try event("projects", generation: nil, payload: ["revision": 1, "partial": true, "items": []]))
        #expect(model.errorMessage == "Catalog failed")
        await model.apply(try event("projects", generation: nil, payload: ["revision": 2, "partial": false, "items": []]))
        #expect(model.errorMessage == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func discoveryCommandFailureRequiresActiveRequestAndAcceptedRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-helper")
        // Capture command IDs from the real model/transport. Replies below are
        // protocol fixtures; periodic scan recovery is covered by the real helper.
        let script = """
        #!/bin/sh
        printf '%s\\n' '{"v":1,"event":"hello","seq":1,"payload":{}}'
        /bin/cat > "$0.commands"
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: executable)
        defer { model.shutdown() }
        model.popupOpened()
        model.show()
        func commands() -> [[String: Any]] {
            guard let text = try? String(contentsOfFile: executable.path + ".commands", encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            }.filter { $0["command"] as? String == "discover" }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while commands().isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let first = try #require(commands().first?["id"] as? String)
        #expect(model.isLoading)
        let rejected: [String: Any] = ["operation": "discover", "code": "limit_exceeded", "message": "Discovery busy"]
        await model.apply(try event("error", generation: nil, requestID: "unrelated", payload: rejected))
        await model.apply(try event("error", generation: nil, payload: rejected))
        #expect(model.errorMessage == nil)
        #expect(model.isLoading)
        await model.apply(try event("error", generation: nil, requestID: first, payload: rejected))
        #expect(model.errorMessage == "Discovery busy")
        #expect(!model.isLoading)
        #expect(model.isConnected)
        await model.apply(try event("error", generation: nil, payload: [
            "operation": "discover", "catalog_revision": 1, "message": "Catalog incomplete"]))
        await model.apply(try event("projects", generation: nil, payload: ["revision": 1, "partial": true, "items": []]))
        #expect(model.errorMessage == "Discovery busy")
        model.show()
        while commands().count < 2, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let retry = try #require(commands().last?["id"] as? String)
        #expect(retry != first)
        #expect(model.errorMessage == "Discovery busy")
        await model.apply(try event("projects", generation: nil, requestID: first, payload: ["revision": 1, "partial": true, "items": []]))
        #expect(model.errorMessage == "Discovery busy")
        await model.apply(try event("projects", generation: nil, requestID: retry, payload: ["revision": 2, "partial": true, "items": []]))
        #expect(model.errorMessage == "Catalog incomplete")
        await model.apply(try event("error", generation: nil, requestID: first, payload: rejected))
        #expect(model.errorMessage == "Catalog incomplete")
        await model.apply(try event("projects", generation: nil, payload: ["revision": 3, "partial": false, "items": []]))
        #expect(model.errorMessage == nil)
    }

    @Test
    func partialReadCoverageStaysQuietAndIsScopedToSelection() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        model.selectProject("/project")
        await model.apply(try event("snapshot", generation: 1, payload: [
            "messages": [message("recent", text: "Readable recent update")],
            "read_coverage": ["oversized_records_skipped": true, "scan_limited": false]
        ]))
        #expect(model.historyPartial)
        #expect(model.hasActiveSelection)
        #expect(model.errorMessage == nil)
        await model.apply(try event("updates", generation: 1, payload: [
            "messages": [], "read_coverage": ["oversized_records_skipped": false, "scan_limited": false]
        ]))
        #expect(model.historyPartial)
        model.selectProject("/other")
        #expect(!model.historyPartial)
        await model.apply(try event("updates", generation: 1, payload: [
            "read_coverage": ["oversized_records_skipped": true]
        ]))
        #expect(!model.historyPartial)
        await model.apply(try event("snapshot", generation: 2, payload: [
            "messages": [], "read_coverage": ["scan_limited": true]
        ]))
        #expect(model.historyPartial)
        await model.apply(try event("reset", generation: 2, payload: [:]))
        #expect(!model.historyPartial)
    }

    @Test
    func recentProjectsUseParsedActivityTimesAndLimitTheMenuToTen() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        var items: [[String: Any]] = (1...12).map { index in
            ["id": "p\(index)", "root": "/p\(index)", "name": "Project \(index)",
             "last_activity": String(format: "2026-09-06T%02d:00:00Z", index)]
        }
        items += [
            ["id": "offset", "root": "/offset", "name": "Offset", "last_activity": "2026-09-06T06:00:00-07:00"],
            ["id": "fractional", "root": "/fractional", "name": "Fractional", "last_activity": "2026-09-06T13:00:00.100Z"],
            ["id": "unknown", "root": "/unknown", "name": "Unknown", "last_activity": "invalid"]
        ]
        await model.apply(try event("projects", generation: 0, payload: ["items": items]))
        #expect(model.projects.count == 15)
        #expect(model.recentProjects.map(\.id) == ["fractional", "offset", "p12", "p11", "p10", "p9", "p8", "p7", "p6", "p5"])
    }

    @Test
    func switchingIgnoresOldResultsAndRestoresCachedMessages() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        model.selectProject("/project-a")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [message("a", text: "Original A")]]))
        await model.apply(try event("summaries", generation: 1, payload: ["items": [["message_id": "a", "text": "Summary A"]]]))
        model.selectProject("/project-b")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [message("late", text: "Wrong project")]]))
        #expect(model.messages.isEmpty)
        await model.apply(try event("snapshot", generation: 2, payload: ["messages": [message("b", text: "Original B")]]))
        model.selectProject("/project-a")
        #expect(model.messages.map(\.id) == ["a"])
        #expect(model.summaries["a"] == "Summary A")
        #expect(model.isLoading)
        #expect(defaults.string(forKey: "runwai.activity.project") == "/project-a")
        model.shutdown()
    }

    @Test
    func pagingDoesNotReplaceLatestAnswerAndFailuresPreserveOriginals() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        model.selectProject("/project")
        await model.apply(try event("snapshot", generation: 1, payload: [
            "messages": [message("a", text: "Progress")], "latest_answer": message("final", text: "Full answer", kind: "final")]))
        await model.apply(try event("page", generation: 1, payload: ["messages": [message("older", text: "Older answer", kind: "final")]]))
        await model.apply(try event("error", generation: 1, payload: ["operation": "summarize", "code": "model_unavailable", "message": "Codex unavailable", "recoverable": true]))
        #expect(model.latestAnswer?.id == "final")
        #expect(model.messages.count == 2)
        #expect(model.messages.contains { $0.originalText == "Progress" })
        #expect(model.errorMessage == "Codex unavailable")
        model.shutdown()
    }

    @Test
    func largeOriginalStorePreservesExactUTF8() async throws {
        let store = LowdownOriginalStore()
        let text = "Full original: \u{1F680}\nSecond line."
        let bytes = text.utf8.count
        let url = try await store.append(key: "message", offset: 0, text: text, total: bytes, done: true)
        #expect(try String(contentsOf: #require(url), encoding: .utf8) == text)
        await store.clear()
        #expect(!FileManager.default.fileExists(atPath: try #require(url).path))
    }

    @Test
    func failedSelectionClearsCachedViewAndPreservesAnswerStatus() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        model.selectProject("/a")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [message("a", text: "A")], "answer_status": "known_absent"]))
        #expect(model.answerStatus == "known_absent")
        model.selectProject("/b")
        let request = model.selectProject("/a")
        #expect(!model.messages.isEmpty)
        await model.apply(try event("error", generation: 3, requestID: request,
            payload: ["operation": "select", "code": "not_found", "message": "Session removed", "recoverable": true]))
        #expect(model.messages.isEmpty)
        #expect(model.latestAnswer == nil)
        #expect(!model.hasActiveSelection)
        #expect(model.status != "following")
        model.shutdown()
    }

    @Test
    func oneFailedOriginalDoesNotCancelAnotherReadOrPage() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        model.selectProject("/a")
        var first = message("a", text: "A")
        var second = message("b", text: "B")
        first["original_text"] = NSNull(); first["text_complete"] = false
        second["original_text"] = NSNull(); second["text_complete"] = false
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [first, second], "before_cursor": "older", "has_more": true]))
        let a = try #require(model.messages.first { $0.id == "a" })
        let b = try #require(model.messages.first { $0.id == "b" })
        let aRequest = model.loadOriginal(a)
        let bRequest = model.loadOriginal(b)
        let page = model.loadOlder()
        await model.apply(try event("error", generation: 1, requestID: aRequest,
            payload: ["operation": "read_message", "code": "read_failed", "message": "Missing original", "recoverable": true]))
        #expect(model.isOriginalLoading("b"))
        #expect(model.isLoadingOlder)
        await model.apply(try event("message_text", generation: 1, requestID: bRequest,
            payload: ["message_id": "b", "byte_offset": 0, "total_bytes": 1, "text": "B", "done": true]))
        await model.apply(try event("page", generation: 1, requestID: page,
            payload: ["messages": [message("old", text: "Earlier")], "has_more": false]))
        #expect(model.originalText(for: b) == "B")
        #expect(model.messages.contains { $0.id == "old" })
        #expect(!model.isLoadingOlder)
        model.shutdown()
    }

    @Test
    func originalRetryAndIndependentStoreCleanup() async throws {
        let old = LowdownOriginalStore(), current = LowdownOriginalStore()
        _ = try await old.append(key: "failed", offset: 0, text: "half", total: 8, done: false)
        await old.discard(key: "failed")
        let retried = try await old.append(key: "failed", offset: 0, text: "complete", total: 8, done: true)
        #expect(try String(contentsOf: #require(retried), encoding: .utf8) == "complete")
        let newFile = try await current.append(key: "new", offset: 0, text: "new", total: 3, done: true)
        await old.clear()
        #expect(try String(contentsOf: #require(newFile), encoding: .utf8) == "new")
        await current.clear()
    }

    @Test
    func cachedDeferredOriginalWaitsForResolvedSelection() async throws {
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: nil)
        defer { model.shutdown() }
        var deferred = message("large", text: "")
        deferred["original_text"] = NSNull(); deferred["text_complete"] = false
        model.selectProject("/a")
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [deferred]]))
        model.selectProject("/b")
        model.selectProject("/a")
        let cached = try #require(model.messages.first)
        #expect(model.loadOriginal(cached) == nil)
        #expect(!model.isOriginalLoading(cached.id))
        await model.apply(try event("snapshot", generation: 3, payload: ["messages": [deferred]]))
        #expect(model.loadOriginal(cached) != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func helperExitClearsPartialOriginalAndAllowsReconnect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-helper")
        let snapshot: [String: Any] = ["v": 1, "event": "snapshot", "seq": 2, "generation": 1,
            "session_id": "session", "session_revision": "r1", "payload": ["messages": []]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: snapshot), as: UTF8.self)
        let script = """
        #!/bin/sh
        printf '%s\\n' '\(line)'
        while IFS= read -r command; do
          case "$command" in
            *read_message*)
              id=$(printf '%s' "$command" | /usr/bin/sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
              printf '{"v":1,"event":"message_text","seq":3,"generation":1,"session_revision":"r1","request_id":"%s","payload":{"message_id":"large","byte_offset":0,"total_bytes":8,"text":"half","done":false}}\\n' "$id"
              exit 0
              ;;
          esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let suite = "runwai.activity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AgentActivityModel(defaults: defaults, executable: executable)
        defer { model.shutdown() }
        model.show()
        model.selectProject(directory.path)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !model.hasActiveSelection, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(model.hasActiveSelection)
        var deferred = message("large", text: "")
        deferred["original_text"] = NSNull(); deferred["text_complete"] = false
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let original = try decoder.decode(LowdownMessage.self, from: JSONSerialization.data(withJSONObject: deferred))
        model.loadOriginal(original)
        #expect(model.isOriginalLoading("large"))
        while model.errorMessage == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.errorMessage != nil)
        #expect(!model.isOriginalLoading("large"))
        #expect(!model.hasActiveSelection)
        // Resolve a replacement connection before a new offset-zero request.
        await model.apply(try event("snapshot", generation: 1, payload: ["messages": [deferred]]))
        let retry = model.loadOriginal(original)
        #expect(retry != nil)
        await model.apply(try event("message_text", generation: 1, requestID: retry,
            payload: ["message_id": "large", "byte_offset": 0, "total_bytes": 8, "text": "complete", "done": true]))
        #expect(model.originalText(for: original) == "complete")
    }

    private func message(_ id: String, text: String, kind: String = "progress") -> [String: Any] {
        ["id": id, "kind": kind, "timestamp": "2026-09-06T18:00:00Z", "original_text": text,
         "text_bytes": text.utf8.count, "text_complete": true,
         "source_ref": ["session_path": "/fixture/rollout.jsonl", "byte_offset": 120]]
    }

    private func event(_ name: String, generation: UInt64?, requestID: String? = nil, revision: String? = nil,
                       sequence: UInt64 = 1, sessionID: String = "session", payload: [String: Any]) throws -> LowdownEvent {
        let json: [String: Any] = ["v": 1, "seq": sequence, "event": name, "generation": generation as Any? ?? NSNull(),
            "request_id": requestID as Any? ?? NSNull(), "session_id": generation.map { _ in sessionID } as Any? ?? NSNull(),
            "session_revision": generation.map { revision ?? "r\($0)" } as Any? ?? NSNull(), "payload": payload]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LowdownEvent.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

struct LowdownTransportTests {
    @Test(.timeLimit(.minutes(1)))
    func fullTextBurstKeepsEveryChunkAndInterleavedCacheEvent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-helper")
        let script = "#!/bin/sh\n/bin/cat \"$0.events\"\n/bin/cat >/dev/null\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var wire = Data()
        var seq = 0
        func emit(_ name: String, _ payload: [String: Any]) throws {
            seq += 1
            let event: [String: Any] = ["v": 1, "event": name, "seq": seq, "generation": 1,
                "request_id": "text", "session_id": "s", "session_revision": "r", "payload": payload]
            wire.append(try JSONSerialization.data(withJSONObject: event))
            wire.append(10)
        }
        let chunk = String(repeating: "x", count: 32_768)
        for index in 0..<64 {
            if index == 32 { try emit("summaries", ["source": "cache", "items": [["message_id": "other", "text": "Cached now"]]]) }
            try emit("message_text", ["message_id": "large", "byte_offset": index * 32_768,
                "total_bytes": 64 * 32_768, "text": chunk, "done": index == 63])
        }
        try wire.write(to: URL(fileURLWithPath: executable.path + ".events"))
        let bridge = LowdownBridge(executable: executable)
        defer { bridge.stop() }
        let store = LowdownOriginalStore()
        var file: URL?
        var cacheSeen = false
        for try await event in bridge.events() {
            if event.event == "summaries" { cacheSeen = true; continue }
            file = try await store.append(key: "large", offset: #require(event.payload.byteOffset),
                text: #require(event.payload.text), total: #require(event.payload.totalBytes), done: event.payload.done == true)
            try await Task.sleep(for: .milliseconds(3))
            if event.payload.done == true { bridge.stop() }
        }
        #expect(cacheSeen)
        #expect(try Data(contentsOf: #require(file)).count == 2_097_152)
        await store.clear()
    }

    @Test(.timeLimit(.minutes(1)))
    func realPipeDecodesHelloAndShutsDownOnEOF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-helper")
        let script = """
        #!/bin/sh
        printf '%s\\n' '{"v":1,"event":"hello","seq":1,"payload":{"helper_version":"fixture","capabilities":[]}}'
        /bin/cat >/dev/null
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let bridge = LowdownBridge(executable: executable)
        defer { bridge.stop() }
        var count = 0
        for try await event in bridge.events() {
            #expect(event.event == "hello")
            count += 1
            bridge.stop()
        }
        #expect(count == 1)
    }
}
