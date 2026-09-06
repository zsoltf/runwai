import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.openWindow) var openWindow
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorScheme) var colorScheme
    @Bindable var model: UsageMonitorModel
    let showsHeaderUtilities: Bool
    @State private var showsQuickUpdate = false
    @State private var selectedPage: DashboardPage

    enum DashboardPage: String, CaseIterable {
        case overview = "Overview"
        case activity = "Activity"
    }

    init(model: UsageMonitorModel, showsHeaderUtilities: Bool = true, initialPage: DashboardPage = .overview) {
        self.model = model
        self.showsHeaderUtilities = showsHeaderUtilities
        _selectedPage = State(initialValue: initialPage)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                header
                pageTabs
                issueBanners
                if model.isPlaceholderSnapshot {
                    setupSection
                } else {
                    if selectedPage == .overview {
                        focusSection
                        weeklySection
                    } else {
                        activitySection
                    }

                    if showsQuickUpdate {
                        quickUpdateSection
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(popoverFillStyle)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(popoverGlow)
                }
        }
        .shadow(color: Color.black.opacity(shellShadowOpacity), radius: 22, y: 12)
        .padding(10)
    }

    private var pageTabs: some View {
        HStack(spacing: 22) {
            ForEach(DashboardPage.allCases, id: \.self) { page in
                Button {
                    selectedPage = page
                } label: {
                    VStack(spacing: 5) {
                        Label(page.rawValue.lowercased(), systemImage: page == .overview ? "rectangle.grid.1x2" : "waveform.path")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedPage == page ? headerText : subtleText)
                        Capsule()
                            .fill(selectedPage == page ? providerTint(model.selectedProvider) : .clear)
                            .frame(height: 2)
                    }
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var activitySection: some View {
        UsageActivityView(
            model: model, tint: providerTint(model.selectedProvider),
            text: headerText, secondaryText: subtleText
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
                    Text(model.selectedProvider.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(providerTint(model.selectedProvider))

                    Text("•")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(subtleText.opacity(0.62))

                    Text(model.sourceStatusLine)
                        .font(.caption)
                        .foregroundStyle(sourceStatusText)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text(model.sourceBadgeText.lowercased())
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

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(subtleText)
                Spacer()
                overviewStatus(todayStatus, tint: sourceNeedsAttention ? subtleText : dailyTint)
            }

            overviewMetrics(
                primaryValue: model.focusHeroPrimaryValue,
                primaryLabel: model.focusHeroPrimaryLabel,
                secondaryValue: model.focusHeroSecondaryValue,
                secondaryLabel: model.focusHeroSecondaryLabel
            )

            VStack(spacing: 8) {
                HStack {
                    Text("\(model.todayUsedValue) used")
                    Spacer()
                    Text("\(model.focusTargetValue) budget")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(headerText)

                DailyBudgetBarView(
                    progressFraction: model.dailyBarProgressFraction,
                    targetFraction: model.dailyBarTargetFraction,
                    fillTint: dailyTint,
                    budgetTint: progressTint,
                    trackTint: trackTint,
                    labelTint: subtleText,
                    markerTint: headerText.opacity(0.72),
                    budgetLabel: model.focusTargetLabel,
                    bufferLabel: model.borrowedBufferTrackTitle,
                    isOverBudget: model.isTodayOverBudget
                )
                .frame(height: model.isTodayOverBudget ? 42 : 22)
            }
        }
        .help(model.isTodayOverBudget ? model.postLimitOutcomeLine : model.estimatedStopCountdownLine)
        .padding(16)
        .background {
            glassPanelBackground(tint: dailyTint, tintOpacity: colorScheme == .dark ? 0.10 : 0.06)
        }
    }

    private var todayStatus: String {
        if sourceNeedsAttention { return "last reading" }
        if model.trackedHistoryPoints.count < 2 { return "tracking" }
        return model.isTodayOverBudget ? model.overBudgetStatusLine : "within budget"
    }

    private var sourceNeedsAttention: Bool {
        model.hasSourceError || model.isAutomaticSourceStale
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("this week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(subtleText)
                Spacer()
                overviewStatus(sourceNeedsAttention ? "last reading" : model.paceStatusLine,
                               tint: sourceNeedsAttention ? subtleText : statusTint)
            }

            overviewMetrics(
                primaryValue: model.weeklyHeroPrimaryValue,
                primaryLabel: model.heroStyle == .remainingFirst ? "remaining" : model.weeklyHeroPrimaryLabel,
                secondaryValue: model.weeklyHeroSecondaryValue,
                secondaryLabel: model.heroStyle == .timeFirst ? "remaining" : model.weeklyHeroSecondaryLabel
            )

            PaceBarView(
                actualFraction: model.summary.remainingFraction,
                targetFraction: model.expectedRemainingFraction,
                milestoneFractions: model.dailyTargetMilestoneFractions,
                fillTint: progressTint,
                milestoneTint: headerText.opacity(0.18),
                markerTint: headerText.opacity(0.72),
                trackTint: trackTint
            )
            .frame(height: 38)

            if model.shouldShowTrend {
                trendSection
            } else {
                Text(model.compactResetLine.lowercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(subtleText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .help(model.paceSummaryLine)
        .padding(16)
        .background {
            glassPanelBackground(tint: progressTint, tintOpacity: colorScheme == .dark ? 0.08 : 0.045)
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("usage trend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(subtleText)

                Spacer()

                Text(model.compactResetLine.lowercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(subtleText.opacity(0.82))
            }

            TrendSparklineView(
                points: model.displayHistory,
                windowStart: model.windowStart,
                windowEnd: model.resetAt,
                targetRemainingPercent: model.expectedRemainingPercent,
                lineTint: progressTint,
                pointTint: statusTint,
                guideTint: subtleText.opacity(0.20),
                targetTint: headerText.opacity(0.72),
                deltaTint: statusTint.opacity(0.30)
            )
            .frame(height: 56)
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
