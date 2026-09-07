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
        var lastActivity: Date? = nil
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
    var errorMessage: String? {
        if let failure = connectionFailure ?? discoveryCommandFailure ?? catalogFailure?.message { return failure }
        if let failure = selectionFailure?.message { return failure }
        if let failure = followFailure?.message ?? pageFailure ?? summaryFailure { return failure }
        return originalFailures.sorted { $0.key < $1.key }.first?.value
    }
    var catalogPartial = false
    var historyPartial = false
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
    private var connectionFailure: String?
    private var discoveryCommandFailure: String?
    private var catalogRequestID: String?
    private var catalogFailure: (revision: UInt64?, message: String)?
    private var catalogRevision: UInt64?
    private var selectionFailure: (requestID: String?, message: String)?
    private var followFailure: (sequence: UInt64, generation: UInt64, sessionID: String?, revision: String, message: String)?
    private var pageFailure: String?
    private var summaryFailure: String?
    private var originalFailures: [String: String] = [:]
    private var visible = false
    private var wantsRecentProject = false
    private var recentDiscoveryID: String?
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
    var recentProjects: [Project] {
        Array(projects.sorted {
            let left = $0.lastActivity ?? .distantPast
            let right = $1.lastActivity ?? .distantPast
            return left == right ? $0.root < $1.root : left > right
        }.prefix(10))
    }
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

    func popupOpened() {
        wantsRecentProject = true
        recentDiscoveryID = nil
    }

    func popupClosed() {
        cancelRecentSelection()
        hide()
    }

    func show() {
        visible = true
        if bridge == nil { connect() }
        else if isConnected {
            if wantsRecentProject { discoverMostRecent() }
            else if generation > 0 { send("resume") }
        }
    }

    func hide() {
        visible = false
        recentDiscoveryID = nil
        if generation > 0 { send("pause") }
    }

    func shutdown() {
        reader?.cancel()
        reader = nil
        bridge?.stop()
        bridge = nil
        isConnected = false
        recentDiscoveryID = nil
        hasActiveSelection = false
        clearPendingReads()
        originalFiles = [:]
        resetOriginalStore()
    }

    func reconnect() { shutdown(); connect() }

    private func connect() {
        guard let executable else {
            connectionFailure = LowdownBridgeError.unavailable.localizedDescription
            return
        }
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
                self?.connectionFailure = error.localizedDescription
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
        cancelRecentSelection()
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
        cancelRecentSelection()
        let request = activateProject(root)
        discover()
        return request
    }

    private func activateProject(_ root: String) -> String? {
        rememberCurrent()
        let root = Self.canonicalRoot(root)
        selectedRoot = root
        selectedSession = savedSessions[root]
        defaults.set(root, forKey: "runwai.activity.project")
        defaults.set(Array(([root] + savedRoots.filter { $0 != root }).prefix(20)), forKey: "runwai.activity.recentProjects")
        return selectCurrent()
    }

    func selectSession(_ id: String?) {
        cancelRecentSelection()
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
        historyPartial = false
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
        retireSelectionFailures()
        requests = [:]
        let command = LowdownCommand(command: "select", generation: generation,
            projectRoot: root, sessionId: selectedSession)
        requests[command.id] = .selection
        bridge?.send(command)
        return command.id
    }

    private func discover() {
        let command = LowdownCommand(command: "discover", projectRoots: savedRoots)
        catalogRequestID = command.id
        bridge?.send(command)
    }

    private func discoverMostRecent() {
        guard recentDiscoveryID == nil else { return }
        let command = LowdownCommand(command: "discover", projectRoots: savedRoots)
        recentDiscoveryID = command.id
        catalogRequestID = command.id
        bridge?.send(command)
    }

    private func cancelRecentSelection() {
        wantsRecentProject = false
        recentDiscoveryID = nil
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
            connectionFailure = nil
            catalogRevision = nil
            if let failure = catalogFailure { catalogFailure = (nil, failure.message) }
            if wantsRecentProject && visible {
                isLoading = true
                discoverMostRecent()
                return
            }
            discover()
            isLoading = selectedRoot != nil
            // Opaque saved IDs must be resolved by the new helper's catalog.
            if selectedRoot != nil && selectedSession == nil { selectCurrent() }
            if !visible && generation > 0 { send("pause") }
            return
        }
        if event.event == "projects" {
            if let received = payload.revision {
                guard catalogRevision.map({ received >= $0 }) ?? true else { return }
                catalogRevision = received
                if payload.partial == false, let failure = catalogFailure,
                   failure.revision.map({ received > $0 }) ?? true { catalogFailure = nil }
                if let requestID = event.requestId, requestID == catalogRequestID {
                    discoveryCommandFailure = nil
                    catalogRequestID = nil
                }
            }
            projects = (payload.items ?? []).compactMap {
                guard let id = $0.id, let root = $0.root, let name = $0.name else { return nil }
                return Project(id: id, root: root, name: name,
                               lastActivity: Self.activityDate($0.lastActivity))
            }
            catalogPartial = payload.partial ?? false
            // Only this opening's discovery can choose a project. Periodic
            // catalogs and late replies must never override a manual choice.
            if visible, wantsRecentProject, let recentDiscoveryID,
               event.requestId == recentDiscoveryID {
                cancelRecentSelection()
                if let latest = recentProjects.first {
                    _ = activateProject(latest.root)
                    send("resume")
                } else {
                    isLoading = false
                }
            }
            return
        }
        if event.event == "sessions", let project = payload.projectId {
            if let received = payload.revision, let catalogRevision, received < catalogRevision { return }
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
        if event.event == "error", payload.operation == "discover" {
            guard event.generation == nil, event.sessionId == nil, event.sessionRevision == nil else { return }
            guard let received = payload.catalogRevision else {
                // Command validation failed before any catalog scan was accepted.
                guard let requestID = event.requestId, requestID == catalogRequestID else { return }
                discoveryCommandFailure = payload.message
                catalogRequestID = nil
                if generation == 0 || requestID == recentDiscoveryID { isLoading = false }
                if requestID == recentDiscoveryID { recentDiscoveryID = nil }
                return
            }
            guard catalogRevision.map({ received >= $0 }) ?? true else { return }
            catalogRevision = received
            catalogFailure = payload.message.map { (received, $0) }
            if generation == 0 { isLoading = false }
            return
        }
        if let generation = event.generation, generation != self.generation { return }
        if event.event == "error", event.generation == nil {
            guard event.requestId == nil else { return }
            connectionFailure = payload.message
            if generation == 0 { isLoading = false }
            return
        }
        guard event.generation == generation else { return }
        if event.event == "reset" {
            retireSelectionFailures()
            historyPartial = false
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
            revision = event.sessionRevision; hasActiveSelection = true
        }
        switch event.event {
        case "snapshot", "updates", "page":
            if event.event == "snapshot", let failure = selectionFailure,
               failure.requestID == event.requestId { selectionFailure = nil }
            if event.event == "page", let id = event.requestId, case .page = requests[id] { pageFailure = nil }
            if let coverage = payload.readCoverage {
                historyPartial = historyPartial || coverage.oversizedRecordsSkipped == true || coverage.scanLimited == true
            }
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
            // Ready/cache events do not establish that the model has recovered.
            if revision != nil, event.sessionRevision == revision,
               payload.source == "model", payload.items?.isEmpty == false {
                summaryFailure = nil
            }
        case "state":
            isLoading = payload.loading ?? isLoading
            isPaused = payload.paused ?? isPaused
            summaryStatus = payload.summaryStatus ?? summaryStatus
        case "recovered":
            if payload.operation == "follow", event.requestId == nil, let failure = followFailure,
               payload.errorSeq == failure.sequence, event.generation == failure.generation,
               event.sessionId == failure.sessionID, event.sessionRevision == failure.revision {
                followFailure = nil
            }
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
                    if let url {
                        originalFiles[id] = url; pendingText.remove(id); requests[requestID] = nil
                        originalFailures[id] = nil
                    }
                } catch {
                    guard event.generation == generation, event.sessionRevision == revision else { return }
                    originalFailures[id] = "Original text could not be loaded."
                    pendingText.remove(id)
                    requests[requestID] = nil
                    await store.discard(key: requestID)
                }
                return
            }
            var bytes = textTransfers[id] ?? Data()
            guard bytes.count == offset, total >= 0, offset <= total,
                  text.utf8.count <= total - offset else {
                originalFailures[id] = "Original text was incomplete."
                pendingText.remove(id); textTransfers[id] = nil
                requests[requestID] = nil
                return
            }
            bytes.append(contentsOf: text.utf8)
            if payload.done == true {
                guard bytes.count == total else {
                    originalFailures[id] = "Original text was incomplete."
                    pendingText.remove(id); textTransfers[id] = nil; requests[requestID] = nil
                    return
                }
                fullTexts[id] = String(decoding: bytes, as: UTF8.self)
                originalFailures[id] = nil
                pendingText.remove(id); textTransfers[id] = nil
                requests[requestID] = nil
            } else { textTransfers[id] = bytes }
        case "error":
            if let id = event.requestId, let request = requests[id] {
                switch (request, payload.operation) {
                case (.selection, "select"):
                    requests[id] = nil
                    selectionFailure = payload.message.map { (id, $0) }
                    messages = []; summaries = [:]; latestAnswer = nil; revision = nil
                    hasActiveSelection = false; isLoading = false
                case (.page, "load_older"):
                    requests[id] = nil
                    pageFailure = payload.message
                    isLoadingOlder = false
                case (.original(let messageID), "read_message"):
                    requests[id] = nil
                    originalFailures[messageID] = payload.message
                    pendingText.remove(messageID); textTransfers[messageID] = nil
                    await originalStore.discard(key: id)
                default:
                    connectionFailure = payload.message
                }
            } else if payload.operation == "summarize" {
                summaryFailure = payload.message
                summaryStatus = "unavailable"
            } else if payload.operation == "follow", event.requestId == nil,
                      let current = revision, event.sessionRevision == current {
                followFailure = payload.message.map { (event.seq, generation, event.sessionId, current, $0) }
            } else if !["select", "follow", "load_older", "read_message", "summarize"].contains(payload.operation ?? "") {
                connectionFailure = payload.message
            }
        default: break
        }
    }

    private func retireSelectionFailures() {
        selectionFailure = nil
        followFailure = nil
        pageFailure = nil
        summaryFailure = nil
        originalFailures = [:]
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

    private static func activityDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
