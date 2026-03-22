import Observation
import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var model: UsageMonitorModel
    @State private var showsClearConfirmation = false

    var body: some View {
        Form {
            Section("General") {
                Picker("Provider", selection: $model.selectedProvider) {
                    ForEach(UsageProvider.visibleProviders) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                if model.availableSourceModes.count > 1 {
                    Picker("Source", selection: $model.selectedSourceMode) {
                        ForEach(model.availableSourceModes) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    LabeledContent("Source") {
                        Text(model.sourceModeDisplayName)
                            .fontWeight(.semibold)
                    }
                }

                LabeledContent("Window") {
                    Text(model.windowLabel)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.settingsLastUpdatedLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.localDataDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    openSelectedProvider()
                } label: {
                    Label(model.selectedProvider.launchActionLabel, systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            }

            Section("Appearance") {
                Picker("Glass style", selection: $model.glassAppearance) {
                    ForEach(GlassAppearance.allCases) { appearance in
                        Text(appearance.displayName)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.glassAppearance.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Hero style", selection: $model.heroStyle) {
                    ForEach(HeroStyle.allCases) { heroStyle in
                        Text(heroStyle.displayName)
                            .tag(heroStyle)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.heroStyleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("\(model.providerName) Snapshot") {
                LabeledContent("Remaining") {
                    HStack(spacing: 12) {
                        TextField("90", value: $model.remainingPercentInput, format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)

                        Text("%")
                            .foregroundStyle(.secondary)

                        Stepper("", value: $model.remainingPercentInput, in: 0...100, step: 1)
                            .labelsHidden()
                    }
                }

                LabeledContent("Reset at") {
                    DatePicker(
                        "",
                        selection: $model.resetAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }

                Text(model.manualSnapshotDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.selectedProvider.setupExample)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.selectedProvider.quickUpdateHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Snapshot Actions") {
                HStack {
                    Button("Start fresh cycle") {
                        model.startFreshWindow()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Load sample") {
                        model.applySampleValues()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Clear provider data", role: .destructive) {
                        showsClearConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }

                Text("Clear provider data removes the saved snapshot and local history for just this provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 10) {
                    PreviewRow(label: "Remaining", value: model.remainingHeadline)
                    PreviewRow(label: "Window", value: model.remainingUnitsLine)
                    PreviewRow(label: "Safe pace", value: model.safeUnitsPerDayLine)
                    PreviewRow(label: "Today", value: "\(model.todayUsedValue) \(model.todayUsedLabel)")
                    PreviewRow(label: "Pace", value: model.paceStatusLine)
                    PreviewRow(label: "Pace detail", value: model.paceDetailLine)
                    PreviewRow(label: "Updated", value: model.compactUpdatedLine)
                    PreviewRow(label: "Reset", value: model.resetAtLine)
                }
                .padding(.vertical, 4)
            }

            Section("About runwai") {
                PreviewRow(label: "Build", value: model.buildVersionLine)
                PreviewRow(label: "Data", value: "Local only")
                PreviewRow(label: "Current provider", value: model.providerName)
                PreviewRow(label: "Current source", value: model.sourceModeSummaryLine)

                Text("runwai is a local-first menu bar utility for keeping codex and gemini pacing legible at a glance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear \(model.providerName) data?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Data", role: .destructive) {
                model.clearSelectedProviderData()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved snapshot and history for \(model.providerName) on this Mac.")
        }
    }

    private func openSelectedProvider() {
        guard let url = model.selectedProvider.launchURL else {
            return
        }

        openURL(url)
    }
}

private struct PreviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}
