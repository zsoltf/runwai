import CryptoKit
import Foundation
import Testing
import Darwin
@testable import runwai

// Runs the exact helper embedded in the test host. CI without a prepared
// helper skips this composition check, not the transport/model regressions.
@MainActor
struct LowdownIntegrationTests {
    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func overlappingOriginalCommandRejectionReleasesOnlyRejectedRead() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let project = try fixture.session(project: "originals", name: "overlap", count: 0)
        let firstText = String(repeating: "First original\n", count: 100_000)
        let secondText = String(repeating: "Second original\n", count: 100_000)
        try fixture.append(firstText, to: project.path)
        try fixture.append(secondText, to: project.path)
        try fixture.cache([firstText, secondText], for: project.path)
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { !model.projects.isEmpty }
        model.selectProject(project.root.path)
        try await wait { model.hasActiveSelection && !model.isLoading }
        let first = try #require(model.messages.first { $0.textBytes == firstText.utf8.count })
        let second = try #require(model.messages.first { $0.textBytes == secondText.utf8.count })
        #expect(model.errorMessage == nil)
        try #require(model.loadOriginal(first) != nil)
        try #require(model.loadOriginal(second) != nil)
        try await wait(description: "overlapping original preflight rejection") {
            model.errorMessage == "A text transfer is already active" && !model.isOriginalLoading(second.id)
        }
        #expect(model.isOriginalLoading(first.id))
        #expect(model.originalFiles[second.id] == nil)
        try await wait { model.originalFiles[first.id] != nil }
        #expect(!model.isOriginalLoading(first.id))
        #expect(model.errorMessage == "A text transfer is already active")
        let firstFile = try #require(model.originalFiles[first.id])
        #expect(try String(contentsOf: firstFile, encoding: .utf8) == firstText)
        try #require(model.loadOriginal(second) != nil)
        #expect(model.errorMessage == "A text transfer is already active")
        try await wait { model.originalFiles[second.id] != nil }
        let secondFile = try #require(model.originalFiles[second.id])
        #expect(try String(contentsOf: secondFile, encoding: .utf8) == secondText)
        #expect(!model.isOriginalLoading(second.id))
        #expect(model.errorMessage == nil)
        #expect(model.hasActiveSelection && model.isConnected)
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func staleCursorCommandRejectionIsRetryableAndPreservesSummaryWarning() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let project = try fixture.session(project: "paging", name: "stale", count: 40)
        try fixture.append("Uncached progress", to: project.path)
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { !model.projects.isEmpty }
        model.selectProject(project.root.path)
        try await wait { model.hasActiveSelection && model.summaryStatus == "unavailable" && model.errorMessage != nil }
        let summaryWarning = try #require(model.errorMessage)
        let revision = try #require(model.revision)
        let first = try #require(model.messages.first)
        let count = model.messages.count
        // Seed only cursor metadata to reproduce stale consumer state. Commands,
        // rejection events, and successful page contents come from the helper.
        func cursor(_ value: String) async throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "v": 1, "event": "page", "seq": 1, "generation": model.generation,
                "session_revision": revision,
                "payload": ["before_cursor": value, "has_more": true, "messages": []]])
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            await model.apply(try decoder.decode(LowdownEvent.self, from: data))
        }
        try await cursor("obsolete-revision:\(first.sourceRef.byteOffset)")
        try #require(model.loadOlder() != nil)
        try await wait(description: "stale cursor preflight rejection") {
            !model.isLoadingOlder && model.errorMessage == "History cursor is not current"
        }
        #expect(model.messages.count == count)
        #expect(model.hasActiveSelection && model.isConnected)
        try await cursor("\(revision):\(first.sourceRef.byteOffset)")
        try #require(model.loadOlder() != nil)
        #expect(model.errorMessage == "History cursor is not current")
        try await wait { !model.isLoadingOlder && model.messages.count > count }
        #expect(model.errorMessage == summaryWarning)
        #expect(model.messages.contains { $0.originalText == "stale update 0" })
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func missingSavedSessionCommandRejectionEndsLoadingAndAllowsSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let project = try fixture.session(project: "selection", name: "present", count: 0)
        fixture.defaults.set([project.root.path: "missing-session"], forKey: "runwai.activity.sessions")
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { !model.projects.isEmpty }
        model.selectProject(project.root.path)
        try await wait(description: "missing saved session preflight rejection") {
            !model.isLoading && model.errorMessage == "Session ID is not in the discovered catalog"
        }
        #expect(!model.hasActiveSelection)
        #expect(model.isConnected)
        model.selectSession(nil)
        try await wait { model.hasActiveSelection && !model.isLoading }
        #expect(model.latestAnswer?.originalText == "Complete answer for present")
        #expect(model.errorMessage == nil)
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func emptyFollowRecoveryPreservesUnrelatedSummaryWarning() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let project = try fixture.session(project: "follow", name: "recover", count: 0)
        try fixture.append("Uncached progress", to: project.path)
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { !model.projects.isEmpty }
        model.selectProject(project.root.path)
        try await wait { model.hasActiveSelection && model.summaryStatus == "unavailable" && model.errorMessage != nil }
        let summaryWarning = try #require(model.errorMessage)
        let revision = model.revision
        let generation = model.generation
        let messageIDs = model.messages.map(\.id)
        let held = project.path.appendingPathExtension("held")
        try FileManager.default.moveItem(at: project.path, to: held)
        try await wait(description: "actual follow read failure") { model.errorMessage != summaryWarning }
        #expect(model.errorMessage != nil)
        // Restore the same inode and bytes. A successful empty read emits only
        // the correlated recovery signal, not a replacement snapshot/update.
        try FileManager.default.moveItem(at: held, to: project.path)
        try await wait(description: "empty follow recovery preserving summary failure") { model.errorMessage == summaryWarning }
        #expect(model.revision == revision)
        #expect(model.generation == generation)
        #expect(model.messages.map(\.id) == messageIDs)
        #expect(model.hasActiveSelection && model.isConnected)
        try await Task.sleep(for: .milliseconds(900))
        #expect(model.errorMessage == summaryWarning)
        #expect(model.messages.map(\.id) == messageIDs)
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(2)))
    func periodicPartialCatalogRetainsWarningUntilFullRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let project = try fixture.session(project: "catalog", name: "recover", count: 0)
        try fixture.append("Uncached progress", to: project.path)
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { !model.projects.isEmpty }
        model.selectProject(project.root.path)
        try await wait { model.hasActiveSelection && model.summaryStatus == "unavailable" && model.errorMessage != nil }
        let summaryWarning = try #require(model.errorMessage)
        let revision = model.revision
        let store = fixture.directory.appendingPathComponent("codex/sessions")
        let held = store.appendingPathExtension("held")
        try FileManager.default.moveItem(at: store, to: held)
        try Data("not a directory".utf8).write(to: store)
        // No discover command: the normal 30-second catalog poll has no request ID.
        try await wait(timeout: .seconds(35), description: "periodic partial catalog") { model.catalogPartial }
        let catalogWarning = try #require(model.errorMessage)
        #expect(catalogWarning != summaryWarning)
        #expect(model.isConnected)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.errorMessage == catalogWarning)
        try FileManager.default.removeItem(at: store)
        try FileManager.default.moveItem(at: held, to: store)
        try await wait(timeout: .seconds(35), description: "periodic full catalog recovery") { !model.catalogPartial }
        #expect(model.errorMessage == summaryWarning)
        #expect(model.revision == revision)
        #expect(model.hasActiveSelection && model.isConnected)
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func completionEchoesPreserveCanonicalIdentityAndDistinctEqualTextTurns() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let project = try fixture.session(project: "echoes", name: "echoes", count: 0)
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { !model.projects.isEmpty }
        model.selectProject(project.root.path)
        try await wait { model.hasActiveSelection && !model.summaries.isEmpty }
        let first = try #require(model.latestAnswer)
        let text = try #require(first.originalText)
        #expect(model.messages.count == 1)
        #expect(model.summaries[first.id] == "Cached answer for echoes")
        #expect(ISO8601DateFormatter().date(from: first.timestamp) == ISO8601DateFormatter().date(from: fixture.stamp))

        var offsets = [first.sourceRef.byteOffset]
        for turn in 1...35 {
            try fixture.appendEvent(["type": "task_started", "turn_id": "turn-\(turn)"], to: project.path)
            try fixture.append("Turn \(turn) progress", to: project.path)
            offsets.append(try fixture.appendEvent(
                ["type": "agent_message", "phase": "final_answer", "message": text], to: project.path))
            if turn < 35 { try fixture.complete(text, turn: "turn-\(turn)", to: project.path) }
        }
        try await wait { model.latestAnswer?.sourceRef.byteOffset == offsets.last }
        let canonical = try #require(model.latestAnswer)
        try fixture.complete(text, turn: "turn-35", to: project.path)
        try fixture.append("After live completion", to: project.path)
        try await wait { model.messages.contains { $0.originalText == "After live completion" } }
        #expect(model.latestAnswer?.id == canonical.id)
        #expect(model.latestAnswer?.timestamp == canonical.timestamp)
        #expect(model.latestAnswer?.sourceRef.byteOffset == canonical.sourceRef.byteOffset)
        #expect(model.messages.filter { $0.kind == "final" }.count == 36)

        // Reload through the bounded snapshot and physical-source history cursor.
        model.selectProject(project.root.path)
        try await wait { model.hasActiveSelection && !model.isLoading }
        #expect(model.hasMore)
        for _ in 0..<3 where model.hasMore {
            try #require(model.loadOlder() != nil)
            try await wait { !model.isLoadingOlder }
        }
        #expect(!model.hasMore)
        let finals = model.messages.filter { $0.kind == "final" }
        #expect(finals.count == 36)
        #expect(finals.map(\.sourceRef.byteOffset) == offsets)
        #expect(Set(finals.map(\.id)).count == 36)
        #expect(finals.allSatisfy { $0.originalText == text && $0.timestamp == first.timestamp })
        #expect(model.messages.contains { $0.originalText == "Turn 1 progress" })
        #expect(model.latestAnswer?.id == canonical.id)
        try await wait(description: "cached summaries for all paged finals") {
            finals.allSatisfy { model.summaries[$0.id] == "Cached answer for echoes" }
        }
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func oversizedSourceStillLoadsRecentDataAndCachedAnswerSummary() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let project = try fixture.session(project: "large", name: "final-only", count: 0)
        try fixture.append(String(repeating: "x", count: 9 * 1_048_576), to: project.path)
        try fixture.append("Recent readable update", to: project.path)
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { !model.projects.isEmpty }
        model.selectProject(project.root.path)
        try await wait { model.hasActiveSelection && !model.isLoading }
        #expect(model.historyPartial)
        #expect(model.errorMessage == nil)
        #expect(model.messages.contains { $0.originalText == "Recent readable update" })
        let answer = try #require(model.latestAnswer)
        #expect(answer.originalText == "Complete answer for final-only")
        try await wait { model.summaries[answer.id] == "Cached answer for final-only" }
        model.loadOriginal(answer)
        #expect(model.originalText(for: answer) == "Complete answer for final-only")
        try fixture.append("Next live arrival", to: project.path)
        try await wait { model.messages.contains { $0.originalText == "Next live arrival" } }
        #expect(model.historyPartial)
        #expect(model.hasActiveSelection)
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func popupSelectsNewestProjectButTabSwitchingPreservesManualChoice() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var projects: [(root: URL, path: URL)] = []
        let now = Date()
        for index in 0..<12 {
            let project = try fixture.session(project: "project-\(index)", name: "session-\(index)", count: 1)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(Double(index - 12) * 60)],
                                                  ofItemAtPath: project.path.path)
            projects.append(project)
        }
        fixture.defaults.set(projects[0].root.path, forKey: "runwai.activity.project")
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.popupOpened()
        model.show()
        try await wait { model.hasActiveSelection && model.summaries.values.contains("Cached session-11 update") }
        #expect(model.selectedRoot == projects[11].root.path)
        #expect(model.recentProjects.map(\.root) == projects.suffix(10).reversed().map { $0.root.path })

        model.selectProject(projects[3].root.path)
        try await wait { model.latestAnswer?.originalText == "Complete answer for session-3" }
        model.hide()
        try await wait { model.isPaused }
        model.show()
        try await wait { !model.isPaused }
        #expect(model.selectedRoot == projects[3].root.path)

        model.popupClosed()
        try await wait { model.isPaused }
        try fixture.append("Newest project now", to: projects[0].path)
        model.popupOpened()
        model.show()
        try await wait { model.selectedRoot == projects[0].root.path && model.hasActiveSelection }
        try await wait { model.messages.contains { $0.originalText == "Newest project now" } }

        // A user choice wins even when this opening's catalog is still in flight.
        model.popupClosed()
        model.popupOpened()
        model.show()
        model.selectProject(projects[3].root.path)
        try await wait { model.latestAnswer?.originalText == "Complete answer for session-3" }
        #expect(model.selectedRoot == projects[3].root.path)
        model.popupClosed()
    }

    @Test(.enabled(if: LowdownBridge.bundledExecutable != nil), .timeLimit(.minutes(1)))
    func bundledHelperFollowsProjectsAndPreservesOriginalsWithoutCodex() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let alpha = try fixture.session(project: "alpha", name: "first", count: 40)
        let beta = try fixture.session(project: "beta", name: "second", count: 2)
        let model = AgentActivityModel(defaults: fixture.defaults,
            executable: try #require(LowdownBridge.bundledExecutable), environment: fixture.environment)
        defer { model.shutdown() }
        model.show()
        try await wait { model.projects.count == 2 }
        let alias = fixture.directory.appendingPathComponent("alpha-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: alpha.root)
        model.selectProject(alias.path)
        try await wait { model.hasActiveSelection && !model.summaries.isEmpty }
        #expect(model.selectedRoot == alpha.root.path)
        #expect(model.messages.count == 31)
        #expect(model.latestAnswer?.originalText == "Complete answer for first")
        #expect(model.summaries.values.contains("Cached first update"))
        #expect(model.hasMore)
        model.loadOlder()
        try await wait { !model.isLoadingOlder }
        #expect(model.messages.count == 41)

        try await wait { !model.sessions.isEmpty }
        let sessionID = try #require(model.sessions.first?.id)
        model.selectSession(sessionID)
        try await wait { model.hasActiveSelection && !model.isLoading }
        model.reconnect()
        try await wait { model.hasActiveSelection && !model.summaries.isEmpty }
        #expect(model.selectedSession == sessionID)
        #expect(model.latestAnswer?.originalText == "Complete answer for first")

        model.selectProject(beta.root.path)
        try await wait { model.latestAnswer?.originalText == "Complete answer for second" }
        let third = try fixture.session(project: "beta", name: "third", count: 1)
        try await wait(timeout: .seconds(35)) { model.sessions.count == 2 }
        #expect(model.latestAnswer?.originalText == "Complete answer for second")
        let newSession = try #require(model.sessions.first { $0.path == third.path.path })
        model.selectSession(newSession.id)
        try await wait { model.latestAnswer?.originalText == "Complete answer for third" }
        model.selectProject(alpha.root.path)
        #expect(model.latestAnswer?.originalText == "Complete answer for first")
        try await wait { model.hasActiveSelection }
        try fixture.append("A live arrival", to: alpha.path)
        try await wait { model.messages.contains { $0.originalText == "A live arrival" } }
        try await wait { model.summaryStatus == "unavailable" || model.summaryStatus == "error" }
        #expect(model.summaries.values.contains("Cached first update"))

        let original = String(repeating: "Full UTF-8 original \u{1F680}\n", count: 60_000)
        try fixture.appendEvent(["type": "task_started", "turn_id": "large-final"], to: alpha.path)
        try fixture.append(original, to: alpha.path, final: true)
        try await wait { model.latestAnswer?.textBytes == original.utf8.count }
        let answer = try #require(model.latestAnswer)
        #expect(answer.originalText == nil)
        model.loadOriginal(answer)
        try await wait { model.originalFiles[answer.id] != nil }
        let file = try #require(model.originalFiles[answer.id])
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
        try fixture.complete(original, turn: "large-final", to: alpha.path)
        try fixture.append("After large completion", to: alpha.path)
        try await wait { model.messages.contains { $0.originalText == "After large completion" } }
        #expect(model.latestAnswer?.id == answer.id)
        #expect(model.latestAnswer?.sourceRef.byteOffset == answer.sourceRef.byteOffset)
        #expect(model.latestAnswer?.timestamp == answer.timestamp)
        #expect(model.messages.filter { $0.textBytes == original.utf8.count }.count == 1)
        #expect(try String(contentsOf: file, encoding: .utf8) == original)

        model.hide()
        try await wait { model.isPaused }
        model.show()
        try await wait { !model.isPaused }
        let revision = model.revision
        try fixture.rewrite(alpha.path, root: alpha.root)
        try await wait { model.revision != revision && model.hasActiveSelection }
        #expect(model.messages.count == 1)
        #expect(model.messages.first?.originalText == "After reset")
        #expect(model.originalFiles.isEmpty)
        model.shutdown()
        try await Task.sleep(for: .milliseconds(200))
    }

    private func wait(timeout: Duration = .seconds(8), description: String = "the bundled helper", _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(predicate(), "Timed out waiting for \(description)")
    }

    private final class Fixture {
        let directory: URL
        let defaults: UserDefaults
        let suite = "runwai.integration.\(UUID().uuidString)"
        let stamp = "2026-09-06T18:00:00Z"

        init() throws {
            let base = FileManager.default.temporaryDirectory
            let canonical = realpath(base.path, nil)!
            defer { free(canonical) }
            directory = URL(fileURLWithPath: String(cString: canonical)).appendingPathComponent(UUID().uuidString)
            defaults = UserDefaults(suiteName: suite)!
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("codex/sessions"), withIntermediateDirectories: true)
        }

        var environment: [String: String] {
            var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("LOWDOWN_") }
            env["CODEX_HOME"] = directory.appendingPathComponent("codex").path
            env["LOWDOWN_CACHE_DIR"] = directory.appendingPathComponent("cache").path
            env["LOWDOWN_CODEX_BIN"] = directory.appendingPathComponent("missing-codex").path
            env["LOWDOWN_SUMMARY_CODEX_MODEL"] = "gpt-5.6-luna"
            env["LOWDOWN_SUMMARY_CODEX_REASONING_EFFORT"] = "none"
            return env
        }

        func session(project: String, name: String, count: Int) throws -> (root: URL, path: URL) {
            let root = directory.appendingPathComponent(project)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("codex/sessions/rollout-\(name).jsonl")
            try record(["type": "session_meta", "payload": ["id": name, "cwd": root.path]]).write(to: path)
            var entries: [String: Any] = [:]
            let milliseconds = Int64(ISO8601DateFormatter().date(from: stamp)!.timeIntervalSince1970 * 1000)
            for index in 0..<count {
                let text = "\(name) update \(index)"
                try append(text, to: path)
                entries["\(milliseconds):\(hash(text))"] = [
                    "summary_version": "rust-codex-scanline-v2:gpt-5.6-luna:none",
                    "summary": "Cached \(name) update", "source": "codex_exec"]
            }
            let answer = "Complete answer for \(name)"
            try appendEvent(["type": "task_started", "turn_id": name], to: path)
            try append(answer, to: path, final: true)
            try complete(answer, turn: name, to: path)
            entries["\(milliseconds):\(hash(answer))"] = [
                "summary_version": "rust-codex-scanline-v2:gpt-5.6-luna:none",
                "summary": "Cached answer for \(name)", "source": "codex_exec"]
            let cache = directory.appendingPathComponent("cache/summaries")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["schema_version": 1, "session_path": path.path, "entries": entries])
                .write(to: cache.appendingPathComponent("\(hash(path.path)).json"))
            return (root, path)
        }

        func append(_ text: String, to path: URL, final: Bool = false) throws {
            try appendEvent(["type": "agent_message", "phase": final ? "final_answer" : "commentary", "message": text], to: path)
        }

        func cache(_ texts: [String], for path: URL) throws {
            let file = directory.appendingPathComponent("cache/summaries/\(hash(path.path)).json")
            var cache = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var entries = try #require(cache["entries"] as? [String: Any])
            let milliseconds = Int64(ISO8601DateFormatter().date(from: stamp)!.timeIntervalSince1970 * 1000)
            for text in texts {
                entries["\(milliseconds):\(hash(text))"] = [
                    "summary_version": "rust-codex-scanline-v2:gpt-5.6-luna:none",
                    "summary": "Cached large original", "source": "codex_exec"]
            }
            cache["entries"] = entries
            try JSONSerialization.data(withJSONObject: cache).write(to: file)
        }

        func complete(_ text: String, turn: String, to path: URL) throws {
            try appendEvent(["type": "task_complete", "turn_id": turn, "last_agent_message": text],
                to: path, timestamp: "2026-09-06T18:00:00.500Z")
        }

        @discardableResult
        func appendEvent(_ payload: [String: Any], to path: URL, timestamp: String? = nil) throws -> UInt64 {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            let offset = try handle.seekToEnd()
            try handle.write(contentsOf: record(["type": "event_msg", "timestamp": timestamp ?? stamp, "payload": payload]))
            return offset
        }

        func rewrite(_ path: URL, root: URL) throws {
            try record(["type": "session_meta", "payload": ["id": "replacement", "cwd": root.path]])
                .write(to: path, options: .atomic)
            try append("After reset", to: path)
        }

        private func record(_ value: [String: Any]) throws -> Data {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            return data
        }

        private func hash(_ text: String) -> String {
            Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
