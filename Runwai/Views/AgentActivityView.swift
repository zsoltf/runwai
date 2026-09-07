import AppKit
import SwiftUI

struct AgentActivityView: View {
    @Bindable var model: AgentActivityModel
    let tint: Color
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Menu {
                    Section("Recent projects") {
                        ForEach(model.recentProjects) { project in
                            Button { model.selectProject(project.root) } label: {
                                if project.root == model.selectedRoot {
                                    Label(project.name, systemImage: "checkmark")
                                } else {
                                    Text(project.name)
                                }
                            }
                            .help(project.root)
                        }
                    }
                    Divider()
                    Button("Choose Folder...") { model.chooseFolder() }
                } label: {
                    Label(model.projectName, systemImage: "folder")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .accessibilityLabel("Recent projects")
                Spacer()
                Text(model.status)
                    .font(.caption).foregroundStyle(.secondary)
            }

            if model.selectedRoot != nil {
                Picker("Session", selection: Binding(get: { model.selectedSession ?? "" },
                    set: { model.selectSession($0.isEmpty ? nil : $0) })) {
                    Text("Latest session").tag("")
                    ForEach(model.sessions) { session in
                        Text(sessionLabel(session)).tag(session.id)
                    }
                }
                .font(.caption)
                .pickerStyle(.menu)
            }

            if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    if !model.isConnected {
                        Button("Reconnect") { model.reconnect() }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }

            if model.selectedRoot == nil {
                ContentUnavailableView {
                    Label("Follow a project", systemImage: "text.bubble")
                } actions: {
                    Button("Choose Folder") { model.chooseFolder() }
                }
            } else if model.messages.isEmpty && !model.isLoading {
                ContentUnavailableView(model.answerStatus == "known_absent" ? "No updates yet" : "No recent updates", systemImage: "text.bubble")
            }
            if model.isLoading { ProgressView().controlSize(.small) }

            if let answer = model.latestAnswer {
                messageRow(answer, latest: true)
            }
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.messages.reversed().filter { $0.id != model.latestAnswer?.id }) { message in
                    messageRow(message)
                }
            }
            if model.hasMore {
                Button(model.isLoadingOlder ? "Loading..." : "Earlier updates") { model.loadOlder() }
                    .disabled(model.isLoadingOlder)
                    .frame(maxWidth: .infinity)
            }
            if model.historyPartial {
                Label("Recent readable updates", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Some source records were too large or outside the read window. Showing the available updates.")
            }
        }
        .onChange(of: model.generation) { expanded = [] }
        .onChange(of: model.revision) { expanded = [] }
    }

    private func messageRow(_ message: LowdownMessage, latest: Bool = false) -> some View {
        let isExpanded = expanded.contains(message.id)
        let isFinal = message.kind == "final"
        let headline = MarkdownDocument.inline(model.summaries[message.id] ?? preview(message))
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded { expanded.remove(message.id) }
                else { expanded.insert(message.id); model.loadOriginal(message) }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(latest ? "latest answer" : isFinal ? "answer" : timestamp(message.timestamp))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(model.summaries[message.id] == nil ? "original" : "summary")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(headline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.hasActiveSelection && model.originalText(for: message) == nil && model.originalFiles[message.id] == nil)
            .accessibilityLabel(Text(headline))
            .accessibilityHint(isExpanded ? "Collapse original" : "Read full original")
            if isExpanded {
                if let original = model.originalText(for: message) {
                    Divider()
                    MarkdownText(source: original)
                } else if let file = model.originalFiles[message.id] {
                    Button("Read complete original") { NSWorkspace.shared.open(file) }
                        .font(.callout)
                } else if model.isOriginalLoading(message.id) {
                    ProgressView("Loading original").controlSize(.small)
                } else {
                    Button("Retry original") { model.loadOriginal(message) }
                }
                Button("Open source") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: message.sourceRef.sessionPath))
                }
                .font(.caption2)
            }
        }
        .padding(12)
        .background(tint.opacity(isFinal ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func preview(_ message: LowdownMessage) -> String {
        guard let original = model.originalText(for: message) else {
            return message.kind == "final" ? "Read full answer" : "Read full update"
        }
        return original.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? original
    }

    private func timestamp(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        return date?.formatted(.dateTime.hour().minute()) ?? raw
    }

    private func sessionLabel(_ session: AgentActivityModel.Session) -> String {
        let shortID = String(session.id.suffix(6))
        return session.lastActivity.map { "\(timestamp($0)) - \(shortID)" } ?? shortID
    }
}
