import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.openWindow) var openWindow
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorScheme) var colorScheme
    @Bindable var model: UsageMonitorModel
    let showsHeaderUtilities: Bool
    @Namespace private var providerSelection
    @State private var showsQuickUpdate = false

    init(model: UsageMonitorModel, showsHeaderUtilities: Bool = true) {
        self.model = model
        self.showsHeaderUtilities = showsHeaderUtilities
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            providerTabs
            issueBanners
            if model.isPlaceholderSnapshot {
                setupSection
            } else {
                focusSection
                weeklySection

                if showsQuickUpdate {
                    quickUpdateSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(20)
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
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: showsQuickUpdate)
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

    private var providerTabs: some View {
        HStack(spacing: 4) {
            ForEach(UsageProvider.visibleProviders) { provider in
                Button {
                    model.selectedProvider = provider
                } label: {
                    Text(provider.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(provider == model.selectedProvider ? headerText : subtleText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                        .background {
                            if provider == model.selectedProvider {
                                Capsule(style: .continuous)
                                    .fill(providerTint(provider).opacity(0.16))
                                    .matchedGeometryEffect(id: "provider-selection", in: providerSelection)
                            } else {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.0001))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule(style: .continuous)
                .fill(panelFillStyle)
                .shadow(color: insetGlowColor.opacity(controlShadowOpacity), radius: 6, x: 0, y: -1)
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.todaySectionTitle.lowercased())
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(subtleText)

            HStack(alignment: .top, spacing: 16) {
                metricBlock(
                    value: model.focusHeroPrimaryValue,
                    label: model.focusHeroPrimaryLabel,
                    note: model.focusHeroPrimaryNote,
                    alignment: .leading,
                    size: 56,
                    tint: dailyTint
                )

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    statusLine

                    compactMetricBlock(
                        value: model.focusHeroSecondaryValue,
                        label: model.focusHeroSecondaryLabel,
                        alignment: .trailing,
                        size: 30
                    )
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.todayUsedValue)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(headerText)

                Text(model.todayUsedLabel)
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(subtleText)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(model.focusTargetValue)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(headerText)

                    Text(model.focusTargetLabel)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(subtleText)
                }
            }

            DailyBudgetBarView(
                progressFraction: model.dailyBarProgressFraction,
                targetFraction: model.dailyBarTargetFraction,
                fillTint: dailyTint,
                budgetTint: progressTint,
                trackTint: trackTint,
                isOverBudget: model.isTodayOverBudget
            )
            .frame(height: model.isTodayOverBudget ? 54 : 22)

            if model.isTodayOverBudget {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(model.postLimitOutcomeLine)
                            .font(.caption)
                            .foregroundStyle(subtleText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        Text(model.borrowedBufferSummaryLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(dailyTint)
                    }
                }
            }

            if model.isTodayOverBudget == false {
                HStack(alignment: .top, spacing: 12) {
                    Text(model.estimatedStopCountdownLine)
                        .font(.caption)
                        .foregroundStyle(subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background {
            glassPanelBackground(tint: dailyTint, tintOpacity: colorScheme == .dark ? 0.10 : 0.06)
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.windowLabel.lowercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(subtleText)

                Spacer(minLength: 0)

                Text(model.compactResetLine.lowercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(subtleText.opacity(0.82))
            }

            HStack(alignment: .top, spacing: 16) {
                metricBlock(
                    value: model.weeklyHeroPrimaryValue,
                    label: model.weeklyHeroPrimaryLabel,
                    note: "",
                    alignment: .leading,
                    size: 44,
                    tint: progressTint
                )

                Spacer(minLength: 12)

                compactMetricBlock(
                    value: model.weeklyHeroSecondaryValue,
                    label: model.weeklyHeroSecondaryLabel,
                    alignment: .trailing,
                    size: 26
                )
            }

            PaceBarView(
                actualFraction: model.summary.remainingFraction,
                targetFraction: model.expectedRemainingFraction,
                milestoneFractions: model.dailyTargetMilestoneFractions,
                fillTint: progressTint,
                milestoneTint: headerText.opacity(0.18),
                markerTint: headerText.opacity(0.72),
                trackTint: trackTint
            )
            .frame(height: 28)

            HStack(alignment: .top, spacing: 12) {
                Text(model.safeRateHeadline)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(headerText)

                Spacer(minLength: 0)

                Text(model.paceSummaryLine.lowercased())
                    .font(.caption)
                    .foregroundStyle(subtleText)
                    .multilineTextAlignment(.trailing)
            }

            if model.shouldShowTrend {
                trendSection
            }
        }
        .padding(16)
        .background {
            glassPanelBackground(tint: progressTint, tintOpacity: colorScheme == .dark ? 0.08 : 0.045)
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.windowLabel.lowercased()) trend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(subtleText)

                Spacer()

                Text(model.trendSummaryLine.lowercased())
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
            .frame(height: 52)
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
