import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.openWindow) var openWindow
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorScheme) var colorScheme
    @Bindable var model: UsageMonitorModel
    @Bindable var activity: AgentActivityModel
    let showsHeaderUtilities: Bool
    let initialUsageRange: UsageActivityRange
    @State private var showsQuickUpdate = false
    @State private var page: Page = .usage

    enum Page: String, CaseIterable { case usage = "Usage", activity = "Activity" }

    init(model: UsageMonitorModel, activity: AgentActivityModel = AgentActivityModel(), showsHeaderUtilities: Bool = true,
         initialUsageRange: UsageActivityRange = .today) {
        self.model = model
        self.activity = activity
        self.showsHeaderUtilities = showsHeaderUtilities
        self.initialUsageRange = initialUsageRange
    }

    var body: some View {
        VStack(spacing: 10) {
            header.padding(.horizontal, 14).padding(.top, 14)
            HStack(spacing: 20) {
                ForEach(Page.allCases, id: \.self) { value in
                    Button { page = value } label: {
                        VStack(spacing: 6) {
                            Text(value.rawValue.lowercased()).font(.caption.weight(.semibold))
                            Capsule().fill(page == value ? providerTint(.codex) : .clear).frame(height: 2)
                        }
                        .foregroundStyle(page == value ? headerText : subtleText)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == value ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if page == .activity {
                        AgentActivityView(model: activity, tint: providerTint(.codex))
                    } else {
                        issueBanners
                        if model.isPlaceholderSnapshot {
                            setupSection
                        } else {
                            usageSection
                            if showsQuickUpdate { quickUpdateSection }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(popoverFillStyle)
        .overlay { popoverGlow.allowsHitTesting(false) }
        .onChange(of: page) {
            if page == .activity { activity.show() } else { activity.hide() }
        }
        .onAppear {
            activity.popupOpened()
            if page == .activity { activity.show() }
        }
        .onDisappear { activity.popupClosed() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            activity.shutdown()
        }
    }

    private var usageSection: some View {
        UsageActivityView(
            model: model, tint: providerTint(model.selectedProvider),
            text: headerText, secondaryText: subtleText, initialRange: initialUsageRange
        )
        .padding(14)
        .background {
            glassPanelBackground(tint: providerTint(model.selectedProvider), tintOpacity: 0.05)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("runwai")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(headerText)

                HStack(spacing: 6) {
                    Text(page == .usage ? model.selectedProvider.shortName : "lowdown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(providerTint(model.selectedProvider))

                    Text("•")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(subtleText.opacity(0.62))

                    Text(page == .usage ? model.sourceStatusLine : activity.status)
                        .font(.caption)
                        .foregroundStyle(page == .usage ? sourceStatusText : subtleText)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text(page == .usage ? model.sourceBadgeText.lowercased() : activity.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(headerText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        badgeSurface(tint: Color(red: 0.35, green: 0.56, blue: 0.95).opacity(0.08))
                    }

                if showsHeaderUtilities {
                    Button {
                        openSettingsWindow()
                    } label: {
                        headerIcon(symbol: "gearshape")
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button(showsQuickUpdate ? "Hide snapshot editor" : "Update snapshot") {
                            showsQuickUpdate.toggle()
                        }

                        Button(model.selectedProvider.launchActionLabel) {
                            openProvider()
                        }

                        Button("Refresh now") {
                            model.refreshNow()
                        }

                        Divider()

                        Button("Quit runwai") {
                            NSApplication.shared.terminate(nil)
                        }
                    } label: {
                        headerIcon(symbol: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var issueBanners: some View {
        if let stalenessLine = model.stalenessLine {
            statusBanner(
                text: stalenessLine,
                symbol: model.hasSourceError ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark",
                textColor: model.hasSourceError ? warningText : staleText,
                tint: model.hasSourceError ? warningTint : staleTint
            )
        }

        if let warningLine = model.warningLine {
            statusBanner(
                text: warningLine,
                symbol: "flame.fill",
                textColor: warningText,
                tint: warningTint
            )
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedProvider.setupTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(headerText)

                Text(model.selectedProvider.setupSummary)
                    .font(.callout)
                    .foregroundStyle(subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("how it works")
                    .font(.caption.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(providerTint(model.selectedProvider))

                ForEach(Array(model.selectedProvider.setupSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(providerTint(model.selectedProvider))
                            .frame(width: 18, height: 18)
                            .background {
                                Circle()
                                    .fill(providerTint(model.selectedProvider).opacity(0.14))
                            }

                        Text(step)
                            .font(.caption)
                            .foregroundStyle(subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            quickUpdateCard(isSetup: true)
        }
    }

    private var quickUpdateSection: some View {
        quickUpdateCard(isSetup: false)
    }

    private func quickUpdateCard(isSetup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSetup ? "manual snapshot" : "update snapshot")
                        .font(.caption.weight(.semibold))
                        .tracking(0.7)
                        .foregroundStyle(providerTint(model.selectedProvider))

                    Text(isSetup ? "enter your first numbers" : "enter the latest remaining % and reset")
                        .font(.caption)
                        .foregroundStyle(subtleText)
                }

                Spacer(minLength: 12)

                Button {
                    openProvider()
                } label: {
                    Label(model.selectedProvider.launchActionLabel, systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(providerTint(model.selectedProvider))
            }

            if isSetup {
                Text(model.selectedProvider.quickUpdateHint)
                    .font(.caption)
                    .foregroundStyle(subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("remaining now")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(subtleText)

                    HStack(spacing: 8) {
                        TextField(
                            "90",
                            value: $model.remainingPercentInput,
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)

                        Text("%")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(subtleText)

                        Stepper("", value: $model.remainingPercentInput, in: 0...100, step: 1)
                            .labelsHidden()
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("reset")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(subtleText)

                    DatePicker(
                        "",
                        selection: $model.resetAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
            }

            HStack(spacing: 8) {
                if isSetup {
                    Button {
                        openSettingsWindow()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.applySampleValues()
                    } label: {
                        Label("Use sample", systemImage: "wand.and.stars")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                Text("auto-saves")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(subtleText.opacity(0.85))
            }
        }
        .padding(12)
        .background {
            glassPanelBackground(
                tint: providerTint(model.selectedProvider),
                tintOpacity: colorScheme == .dark ? 0.11 : 0.07,
                cornerRadius: 18
            )
        }
    }

}
