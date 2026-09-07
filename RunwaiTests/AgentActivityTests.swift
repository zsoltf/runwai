import Foundation
import Testing
@testable import runwai

@MainActor
struct AgentActivityTests {
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
        await model.apply(try event("error", generation: 1, payload: ["code": "model_unavailable", "message": "Codex unavailable", "recoverable": true]))
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
            payload: ["code": "not_found", "message": "Session removed", "recoverable": true]))
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
            payload: ["code": "read_failed", "message": "Missing original", "recoverable": true]))
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

    private func event(_ name: String, generation: UInt64, requestID: String? = nil, payload: [String: Any]) throws -> LowdownEvent {
        let json: [String: Any] = ["v": 1, "seq": 1, "event": name, "generation": generation,
            "request_id": requestID as Any? ?? NSNull(), "session_id": "session", "session_revision": "r\(generation)", "payload": payload]
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
