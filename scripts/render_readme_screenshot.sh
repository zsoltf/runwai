#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-$repo_root/docs/assets/runwai-codex.png}"
provider="${2:-codex}"
appearance="${3:-light}"
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
        let previewSuiteName = "app.runwai.preview"
        let defaults = UserDefaults(suiteName: previewSuiteName) ?? .standard
        defaults.removePersistentDomain(forName: previewSuiteName)
        let store = ManualUsageStore(defaults: defaults)
        let referenceNow = Date()

        seedPreviewData(store: store, now: referenceNow)

        let model = UsageMonitorModel(store: store, automaticSyncServices: [:])
        model.selectedProvider = provider
        model.now = referenceNow

        let view = MenuBarContentView(model: model, showsHeaderUtilities: false)
            .frame(width: 380)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
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
                snapshot.usedUnits = 47
                snapshot.resetAt = now.addingTimeInterval(4 * 86_400)
                history = [
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(72 * 3_600)), remainingPercent: 86),
                    UsageHistoryPoint(timestamp: now.addingTimeInterval(-(48 * 3_600)), remainingPercent: 75),
                    UsageHistoryPoint(timestamp: Calendar.current.startOfDay(for: now), remainingPercent: 62),
                    UsageHistoryPoint(timestamp: now, remainingPercent: 53)
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

swiftc -target arm64-apple-macos14.0 -framework SwiftUI -framework AppKit \
  "$repo_root/Runwai/App/UsageMonitorModel.swift" \
  "$repo_root/Runwai/App/UsageMonitorModel+Sync.swift" \
  "$repo_root/Runwai/App/UsageMonitorModel+Storage.swift" \
  "$repo_root/Runwai/App/UsageMonitorModel+Tracking.swift" \
  "$repo_root/Runwai/Models/GlassAppearance.swift" \
  "$repo_root/Runwai/Models/HeroStyle.swift" \
  "$repo_root/Runwai/Models/RunwaiFormatters.swift" \
  "$repo_root/Runwai/Models/UsageHistoryPoint.swift" \
  "$repo_root/Runwai/Models/UsageProvider.swift" \
  "$repo_root/Runwai/Models/UsageSnapshot.swift" \
  "$repo_root/Runwai/Models/UsageSourceMode.swift" \
  "$repo_root/Runwai/Services/AutomaticUsageSyncing.swift" \
  "$repo_root/Runwai/Services/CodexQuotaSyncService.swift" \
  "$repo_root/Runwai/Services/ManualUsageStore.swift" \
  "$repo_root/Runwai/Services/GeminiQuotaSyncService.swift" \
  "$repo_root/Runwai/Services/PacingCalculator.swift" \
  "$repo_root/Runwai/Views/MenuBarContentView.swift" \
  "$repo_root/Runwai/Views/MenuBarContentView+Style.swift" \
  "$repo_root/Runwai/Views/MenuBarLabelView.swift" \
  "$repo_root/Runwai/Views/RunwaiPacingBars.swift" \
  "$repo_root/Runwai/Views/SettingsView.swift" \
  "$tmp_swift" \
  -o "$tmp_binary"

"$tmp_binary" "$output_path" "$provider" "$appearance"
