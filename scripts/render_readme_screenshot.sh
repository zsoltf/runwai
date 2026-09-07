#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-$repo_root/docs/assets/runwai-codex.png}"
provider="${2:-codex}"
appearance="${3:-light}"
range="${4:-Day}"
tmp_swift_base="$(mktemp -t runwai-readme-render)"
tmp_swift="${tmp_swift_base}.swift"
mv "$tmp_swift_base" "$tmp_swift"
tmp_binary="$(mktemp -t runwai-readme-render-bin)"

cleanup() {
  rm -f "$tmp_swift" "$tmp_binary"
}
trap cleanup EXIT

mkdir -p "$(dirname "$output_path")"

cat > "$tmp_swift" <<'SWIFT'
import SwiftUI
import AppKit
import Observation

@main
struct RenderRunwaiScreenshot {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: render_readme_screenshot.sh <output-path> [provider]\n", stderr)
            exit(1)
        }

        let outputPath = CommandLine.arguments[1]
        let providerRawValue = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "codex"
        let appearanceRawValue = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "light"
        let provider = UsageProvider(rawValue: providerRawValue) ?? .codex
        let colorScheme: ColorScheme = appearanceRawValue == "dark" ? .dark : .light
        let previewSuiteName = "app.runwai.preview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: previewSuiteName) else {
            fatalError("Could not create isolated preview defaults")
        }
        defer { defaults.removePersistentDomain(forName: previewSuiteName) }
        let store = ManualUsageStore(defaults: defaults)
        let referenceNow = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 15, minute: 42))!

        seedPreviewData(store: store, now: referenceNow)

        let model = UsageMonitorModel(store: store, automaticSyncServices: [:])
        model.refreshTimer?.invalidate()
        model.selectedProvider = provider
        model.now = referenceNow

        let range = CommandLine.arguments.count > 4 ? UsageActivityRange(rawValue: CommandLine.arguments[4]) ?? .today : .today
        let view = MenuBarContentView(model: model, initialUsageRange: range)
            .frame(width: 420, height: 640)
            .environment(\.colorScheme, colorScheme)

        // A hosting view renders the actual AppKit scroll surface, unlike ImageRenderer.
        _ = NSApplication.shared
        let bounds = NSRect(x: 0, y: 0, width: 420, height: 640)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = bounds
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else {
            fatalError("Could not allocate preview bitmap")
        }
        host.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("failed to render image\n", stderr)
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
            print(outputPath)
        } catch {
            fputs("failed to write image: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func seedPreviewData(store: ManualUsageStore, now: Date) {
        for provider in UsageProvider.visibleProviders {
            var snapshot = UsageSnapshot.sample(provider: provider, now: now)
            let history: [UsageHistoryPoint]

            switch provider {
            case .codex:
                snapshot.usedUnits = 78
                snapshot.resetAt = now.addingTimeInterval(4 * 86_400)
                history = [
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(72 * 3_600)), remainingPercent: 86),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(48 * 3_600)), remainingPercent: 75),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-4.5 * 3_600), remainingPercent: 49),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-3.5 * 3_600), remainingPercent: 40),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-3 * 3_600), remainingPercent: 40),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-2.5 * 3_600), remainingPercent: 33),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-1.5 * 3_600), remainingPercent: 26),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-0.5 * 3_600), remainingPercent: 23),
                    UsageHistoryPoint(timestamp: now, remainingPercent: 22)
                ]
                store.saveMode(.codexApp, for: provider)

            case .codexSpark:
                snapshot.usedUnits = 18
                snapshot.resetAt = now.addingTimeInterval(5 * 86_400)
                history = [
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(96 * 3_600)), remainingPercent: 95),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(48 * 3_600)), remainingPercent: 90),
                    UsageHistoryPoint(timestamp: Calendar.current.startOfDay(for: now), remainingPercent: 85),
                    UsageHistoryPoint(timestamp: now, remainingPercent: 82)
                ]
                store.saveMode(.codexSparkApp, for: provider)

            case .gemini:
                snapshot.usedUnits = 6
                snapshot.resetAt = now.addingTimeInterval(20 * 3_600)
                history = [
                    UsageHistoryPoint(timestamp: Calendar.current.startOfDay(for: now), remainingPercent: 100),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(6 * 3_600)), remainingPercent: 97),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(2 * 3_600)), remainingPercent: 95),
                    UsageHistoryPoint(timestamp: now, remainingPercent: 94)
                ]
                store.saveMode(.geminiCLI, for: provider)
            }

            snapshot.lastUpdatedAt = now
            store.save(snapshot, for: provider)
            store.saveHistory(history, for: provider)
        }

        store.saveSelectedProvider(.codex)
        store.saveGlassAppearance(.translucent)
        store.saveHeroStyle(.remainingFirst)
    }
}
SWIFT

sources=()
while IFS= read -r -d '' source; do
  sources+=("$source")
done < <(find "$repo_root/Runwai" -name '*.swift' ! -name RunwaiApp.swift -print0)

swiftc -swift-version 6 -target "$(uname -m)-apple-macos14.0" -framework SwiftUI -framework AppKit \
  "${sources[@]}" "$tmp_swift" -o "$tmp_binary"

"$tmp_binary" "$output_path" "$provider" "$appearance" "$range"
