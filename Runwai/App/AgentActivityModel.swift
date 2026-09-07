import AppKit
import Foundation
import Observation
import Darwin

@MainActor
@Observable
final class AgentActivityModel {
    struct Project: Identifiable, Equatable {
        let id: String
        let root: String
        let name: String
    }
    struct Session: Identifiable, Equatable {
        let id: String
        let path: String
        let lastActivity: String?
    }
    struct CachedSelection {
        let messages: [LowdownMessage]
        let summaries: [String: String]
        let latestAnswer: LowdownMessage?
    }

    var projects: [Project] = []
    var sessionsByProject: [String: [Session]] = [:]
    var selectedRoot: String?
    var selectedSession: String?
    var messages: [LowdownMessage] = []
    var summaries: [String: String] = [:]
    var fullTexts: [String: String] = [:]
    var originalFiles: [String: URL] = [:]
    var latestAnswer: LowdownMessage?
    var answerStatus = "outside_window_or_absent"
    var hasActiveSelection = false
    var isLoading = false
    var isConnected = false
    var isPaused = false
    var isLoadingOlder = false
    var summaryStatus = "raw"
    var errorMessage: String?
    var catalogPartial = false
    var hasMore = false
    var generation: UInt64 = 0
    var revision: String?
    var summariesEnabled: Bool {
        didSet {
            defaults.set(summariesEnabled, forKey: "runwai.activity.summariesEnabled")
            if bridge != nil { reconnect() }
        }
    }

    private let defaults: UserDefaults
    private let executable: URL?
    private let environment: [String: String]
    // Accessed on MainActor during life; nonisolated teardown only cancels Sendable handles.
    @ObservationIgnored nonisolated(unsafe) private var bridge: LowdownBridge?
    @ObservationIgnored nonisolated(unsafe) private var reader: Task<Void, Never>?
    private var beforeCursor: String?
    private var cache: [String: CachedSelection] = [:]
    private var cacheOrder: [String] = []
    private var textTransfers: [String: Data] = [:]
    private var pendingText: Set<String> = []
    private enum Request { case selection, page, original(String) }
    private var requests: [String: Request] = [:]
    private var visible = false
    private var originalStore = LowdownOriginalStore()

    init(defaults: UserDefaults = .standard, executable: URL? = LowdownBridge.bundledExecutable,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.executable = executable
        summariesEnabled = defaults.object(forKey: "runwai.activity.summariesEnabled") as? Bool ?? true
        var env = environment
        if env["LOWDOWN_CODEX_BIN"] == nil {
            let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                NSHomeDirectory() + "/.npm-global/bin/codex",
                "/Applications/Codex.app/Contents/Resources/codex"]
            env["LOWDOWN_CODEX_BIN"] = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        self.environment = env
        let savedRoot = defaults.string(forKey: "runwai.activity.project")
        selectedRoot = savedRoot.map(Self.canonicalRoot)
        selectedSession = savedSessions[savedRoot ?? ""]
    }

    deinit { reader?.cancel(); bridge?.stop() }

    var selectedProject: Project? { projects.first { $0.root == selectedRoot } }
    var sessions: [Session] { sessionsByProject[selectedProject?.id ?? ""] ?? [] }
    var projectName: String { selectedProject?.name ?? selectedRoot.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose project" }
    var status: String {
        if !isConnected { return "offline" }
        if isLoading { return "loading" }
        if !hasActiveSelection { return selectedRoot == nil ? "choose project" : "unavailable" }
        if isPaused { return "paused" }
        if summaryStatus == "hydrating" { return "summarizing" }
        if summaryStatus == "unavailable" || summaryStatus == "error" { return "originals" }
        return "following"
    }

    private var savedRoots: [String] { defaults.stringArray(forKey: "runwai.activity.recentProjects") ?? [] }
    private var savedSessions: [String: String] { defaults.dictionary(forKey: "runwai.activity.sessions") as? [String: String] ?? [:] }
    private var selectionKey: String { "\(selectedRoot ?? "")\n\(selectedSession ?? "latest")" }

    func show() {
        visible = true
        if bridge == nil { connect() }
        else if isConnected && generation > 0 { send("resume") }
    }

    func hide() {
        visible = false
        if generation > 0 { send("pause") }
    }

    func shutdown() {
        reader?.cancel()
        reader = nil
        bridge?.stop()
        bridge = nil
        isConnected = false
        hasActiveSelection = false
        clearPendingReads()
        originalFiles = [:]
        resetOriginalStore()
    }

    func reconnect() { shutdown(); connect() }

    private func connect() {
        guard let executable else {
            errorMessage = LowdownBridgeError.unavailable.localizedDescription
            return
        }
        errorMessage = nil
        var env = environment
        if !summariesEnabled { env["LOWDOWN_SUMMARY_PROVIDER"] = "fallback" }
        let connection = LowdownBridge(executable: executable, environment: env)
        bridge = connection
        generation = 0
        reader = Task { [weak self] in
            do {
                for try await event in connection.events() {
                    guard !Task.isCancelled else { return }
                    await self?.apply(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            self?.isConnected = false
            self?.hasActiveSelection = false
            self?.isLoading = false
            self?.isLoadingOlder = false
            self?.clearPendingReads()
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Follow project"
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.selectProject(url.resolvingSymlinksInPath().path)
        }
    }

    @discardableResult
    func selectProject(_ root: String) -> String? {
        rememberCurrent()
        let root = Self.canonicalRoot(root)
        selectedRoot = root
        selectedSession = savedSessions[root]
        defaults.set(root, forKey: "runwai.activity.project")
        defaults.set(Array(([root] + savedRoots.filter { $0 != root }).prefix(20)), forKey: "runwai.activity.recentProjects")
        let request = selectCurrent()
        discover()
        return request
    }

    func selectSession(_ id: String?) {
        rememberCurrent()
        selectedSession = id
        var saved = savedSessions
        if let root = selectedRoot { saved[root] = id }
        defaults.set(saved, forKey: "runwai.activity.sessions")
        selectCurrent()
    }

    private func rememberCurrent() {
        guard !messages.isEmpty else { return }
        cache[selectionKey] = CachedSelection(messages: Array(messages.suffix(100)), summaries: summaries, latestAnswer: latestAnswer)
        cacheOrder.removeAll { $0 == selectionKey }
        cacheOrder.append(selectionKey)
        while cacheOrder.count > 4 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    }

    @discardableResult
    private func selectCurrent() -> String? {
        guard let root = selectedRoot else { return nil }
        generation += 1
        revision = nil
        let cached = cache[selectionKey]
        messages = cached?.messages ?? []
        summaries = cached?.summaries ?? [:]
        latestAnswer = cached?.latestAnswer
        fullTexts = [:]
        originalFiles = [:]
        resetOriginalStore()
        pendingText = []
        textTransfers = [:]
        hasMore = false
        beforeCursor = nil
        isLoadingOlder = false
        isLoading = true
        hasActiveSelection = false
        answerStatus = "outside_window_or_absent"
        errorMessage = nil
        requests = [:]
        let command = LowdownCommand(command: "select", generation: generation,
            projectRoot: root, sessionId: selectedSession)
        requests[command.id] = .selection
        bridge?.send(command)
        return command.id
    }

    private func discover() {
        bridge?.send(LowdownCommand(command: "discover", projectRoots: savedRoots))
    }

    private func send(_ command: String) { bridge?.send(LowdownCommand(command: command, generation: generation)) }

    @discardableResult
    func loadOlder() -> String? {
        guard hasActiveSelection, let beforeCursor, hasMore, !isLoadingOlder else { return nil }
        isLoadingOlder = true
        let command = LowdownCommand(command: "load_older", generation: generation, beforeCursor: beforeCursor, limit: 30)
        requests[command.id] = .page
        bridge?.send(command)
        return command.id
    }

    func originalText(for message: LowdownMessage) -> String? { fullTexts[message.id] ?? message.originalText }

    func isOriginalLoading(_ id: String) -> Bool { pendingText.contains(id) }

    @discardableResult
    func loadOriginal(_ message: LowdownMessage) -> String? {
        guard hasActiveSelection, revision != nil, originalText(for: message) == nil,
              originalFiles[message.id] == nil, !pendingText.contains(message.id) else { return nil }
        pendingText.insert(message.id)
        let command = LowdownCommand(command: "read_message", generation: generation, messageId: message.id)
        requests[command.id] = .original(message.id)
        bridge?.send(command)
        return command.id
    }

    func apply(_ event: LowdownEvent) async {
        let payload = event.payload
        if event.event == "hello" {
            isConnected = true
            discover()
            isLoading = selectedRoot != nil
            // Opaque saved IDs must be resolved by the new helper's catalog.
            if selectedRoot != nil && selectedSession == nil { selectCurrent() }
            if !visible && generation > 0 { send("pause") }
            return
        }
        if event.event == "projects" {
            projects = (payload.items ?? []).compactMap {
                guard let id = $0.id, let root = $0.root, let name = $0.name else { return nil }
                return Project(id: id, root: root, name: name)
            }
            catalogPartial = payload.partial ?? false
            return
        }
        if event.event == "sessions", let project = payload.projectId {
            sessionsByProject[project] = (payload.items ?? []).compactMap {
                guard let id = $0.id, let path = $0.path else { return nil }
                return Session(id: id, path: path, lastActivity: $0.lastActivity)
            }
            if generation == 0, selectedSession != nil,
               projects.first(where: { $0.id == project })?.root == selectedRoot {
                selectCurrent()
                if !visible { send("pause") }
            }
            return
        }
        if let generation = event.generation, generation != self.generation { return }
        if event.event == "error", event.generation == nil {
            errorMessage = payload.message
            if generation == 0 { isLoading = false }
            return
        }
        guard event.generation == generation else { return }
        if event.event == "reset" {
            revision = event.sessionRevision
            messages = []; summaries = [:]; fullTexts = [:]; latestAnswer = nil
            pendingText = []; textTransfers = [:]; beforeCursor = nil; hasMore = false
            originalFiles = [:]
            requests = [:]; isLoadingOlder = false; hasActiveSelection = false
            resetOriginalStore()
            isLoading = true
            return
        }
        if let received = event.sessionRevision, let revision, received != revision { return }
        if event.event == "snapshot" {
            revision = event.sessionRevision; hasActiveSelection = true; errorMessage = nil
        }
        switch event.event {
        case "snapshot", "updates", "page":
            if event.event == "snapshot" { messages = [] }
            var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
            for message in payload.messages ?? [] { byID[message.id] = message }
            messages = byID.values.sorted { $0.sourceRef.byteOffset < $1.sourceRef.byteOffset }
            if event.event != "page" {
                latestAnswer = payload.latestAnswer
                answerStatus = payload.answerStatus ?? "outside_window_or_absent"
            }
            if event.event != "updates" {
                beforeCursor = payload.beforeCursor
                hasMore = payload.hasMore ?? false
            }
            isLoading = false
            isLoadingOlder = false
            if let id = event.requestId { requests[id] = nil }
        case "summaries":
            for item in payload.items ?? [] {
                if let id = item.messageId, let text = item.text { summaries[id] = text }
            }
        case "state":
            isLoading = payload.loading ?? isLoading
            isPaused = payload.paused ?? isPaused
            summaryStatus = payload.summaryStatus ?? summaryStatus
        case "message_text":
            guard let id = payload.messageId, let offset = payload.byteOffset, let text = payload.text,
                  let total = payload.totalBytes, let requestID = event.requestId,
                  case .original(let expectedID) = requests[requestID], expectedID == id else { return }
            if total > 1_048_576 {
                let store = originalStore
                do {
                    let url = try await store.append(key: requestID, offset: offset,
                        text: text, total: total, done: payload.done == true)
                    guard event.generation == generation, event.sessionRevision == revision else { return }
                    if let url { originalFiles[id] = url; pendingText.remove(id); requests[requestID] = nil }
                } catch {
                    guard event.generation == generation, event.sessionRevision == revision else { return }
                    errorMessage = "Original text could not be loaded."
                    pendingText.remove(id)
                    requests[requestID] = nil
                    await store.discard(key: requestID)
                }
                return
            }
            var bytes = textTransfers[id] ?? Data()
            guard bytes.count == offset, total >= 0, offset <= total,
                  text.utf8.count <= total - offset else {
                errorMessage = "Original text was incomplete."
                pendingText.remove(id); textTransfers[id] = nil
                requests[requestID] = nil
                return
            }
            bytes.append(contentsOf: text.utf8)
            if payload.done == true {
                guard bytes.count == total else {
                    errorMessage = "Original text was incomplete."
                    pendingText.remove(id); textTransfers[id] = nil; requests[requestID] = nil
                    return
                }
                fullTexts[id] = String(decoding: bytes, as: UTF8.self)
                pendingText.remove(id); textTransfers[id] = nil
                requests[requestID] = nil
            } else { textTransfers[id] = bytes }
        case "error":
            errorMessage = payload.message
            if let id = event.requestId, let request = requests.removeValue(forKey: id) {
                switch request {
                case .selection:
                    messages = []; summaries = [:]; latestAnswer = nil; revision = nil
                    hasActiveSelection = false; isLoading = false
                case .page: isLoadingOlder = false
                case .original(let messageID):
                    pendingText.remove(messageID); textTransfers[messageID] = nil
                    await originalStore.discard(key: id)
                }
            } else if payload.code == "model_failed" || payload.code == "model_unavailable" {
                summaryStatus = "unavailable"
            }
        default: break
        }
    }

    private func clearPendingReads() {
        let store = originalStore
        let keys = requests.compactMap { id, request in
            if case .original = request { return id }
            return nil as String?
        }
        requests = [:]; pendingText = []; textTransfers = [:]
        Task { for key in keys { await store.discard(key: key) } }
    }

    private func resetOriginalStore() {
        let old = originalStore
        originalStore = LowdownOriginalStore()
        Task { await old.clear() }
    }

    private static func canonicalRoot(_ root: String) -> String {
        guard let path = realpath(root, nil) else { return root }
        defer { free(path) }
        return String(cString: path)
    }
}
