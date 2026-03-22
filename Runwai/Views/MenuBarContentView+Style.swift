import AppKit
import SwiftUI

extension MenuBarContentView {
    var statusLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.isTodayOverBudget ? dailyTint : statusTint)
                .frame(width: 7, height: 7)

            Text(model.overBudgetStatusLine.lowercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.isTodayOverBudget ? dailyTint : statusTint)
        }
    }

    func metricBlock(
        value: String,
        label: String,
        note: String,
        alignment: HorizontalAlignment,
        size: CGFloat,
        tint: Color
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(headerText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(subtleText)

            if note.isEmpty == false {
                Text(note)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }

    func compactMetricBlock(
        value: String,
        label: String,
        alignment: HorizontalAlignment,
        size: CGFloat
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(headerText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(subtleText)
        }
    }

    func headerIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(subtleText)
            .frame(width: 28, height: 28)
            .background {
                badgeSurface(tint: Color.black.opacity(0.012))
            }
    }

    func providerTint(_ provider: UsageProvider) -> Color {
        switch provider {
        case .codex:
            return Color(red: 0.47, green: 0.73, blue: 0.24)
        case .codexSpark:
            return Color(red: 0.92, green: 0.64, blue: 0.25)
        case .gemini:
            return Color(red: 0.40, green: 0.66, blue: 0.96)
        }
    }

    var progressTint: Color {
        if model.isPlaceholderSnapshot {
            return Color(red: 0.36, green: 0.60, blue: 0.92)
        }

        switch model.summary.status {
        case .ahead:
            return Color(red: 0.22, green: 0.76, blue: 0.38)
        case .onPace:
            return Color(red: 0.60, green: 0.78, blue: 0.24)
        case .behind:
            return Color(red: 0.95, green: 0.62, blue: 0.18)
        case .exhausted:
            return Color(red: 0.90, green: 0.31, blue: 0.29)
        }
    }

    var statusTint: Color {
        if model.isPlaceholderSnapshot {
            return Color(red: 0.36, green: 0.60, blue: 0.92)
        }

        switch model.summary.status {
        case .ahead:
            return Color(red: 0.22, green: 0.76, blue: 0.38)
        case .onPace:
            return Color(red: 0.50, green: 0.66, blue: 0.20)
        case .behind:
            return Color(red: 0.95, green: 0.62, blue: 0.18)
        case .exhausted:
            return Color(red: 0.90, green: 0.31, blue: 0.29)
        }
    }

    var dailyTint: Color {
        if model.isPlaceholderSnapshot {
            return Color(red: 0.36, green: 0.60, blue: 0.92)
        }

        if model.isTodayOverBudget {
            return Color(red: 0.90, green: 0.31, blue: 0.29)
        }

        return Color(red: 0.47, green: 0.73, blue: 0.24)
    }

    var sourceStatusText: Color {
        if model.hasSourceError {
            return warningText
        }

        if model.isAutomaticSourceStale {
            return staleText
        }

        if model.isSourceRefreshing {
            return providerTint(model.selectedProvider)
        }

        return subtleText
    }

    var headerText: Color {
        colorScheme == .dark
            ? Color(red: 0.95, green: 0.96, blue: 0.98)
            : Color(red: 0.07, green: 0.10, blue: 0.16)
    }

    var subtleText: Color {
        colorScheme == .dark
            ? Color(red: 0.68, green: 0.72, blue: 0.78)
            : Color(red: 0.31, green: 0.37, blue: 0.44)
    }

    var popoverFillStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color(red: 0.14, green: 0.16, blue: 0.19)
                    : Color(red: 0.96, green: 0.97, blue: 0.99)
            )
        }

        switch model.glassAppearance {
        case .frosted:
            return AnyShapeStyle(.regularMaterial)
        case .translucent:
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.black.opacity(0.18)
                    : Color.white.opacity(0.42)
            )
        case .transparent:
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.black.opacity(0.01)
                    : Color.white.opacity(0.04)
            )
        }
    }

    var panelFillStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color(red: 0.19, green: 0.21, blue: 0.25)
                    : Color.white.opacity(0.96)
            )
        }

        switch model.glassAppearance {
        case .frosted:
            return AnyShapeStyle(.thickMaterial)
        case .translucent:
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.white.opacity(0.05)
                    : Color.white.opacity(0.28)
            )
        case .transparent:
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.white.opacity(0.004)
                    : Color.white.opacity(0.035)
            )
        }
    }

    var controlFillStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color(red: 0.21, green: 0.23, blue: 0.27)
                    : Color.white.opacity(0.96)
            )
        }

        switch model.glassAppearance {
        case .frosted:
            return AnyShapeStyle(.regularMaterial)
        case .translucent:
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.white.opacity(0.035)
                    : Color.white.opacity(0.22)
            )
        case .transparent:
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color.white.opacity(0.004)
                    : Color.white.opacity(0.025)
            )
        }
    }

    var popoverGlow: LinearGradient {
        let whiteOpacity: Double
        let blueOpacity: Double
        let greenOpacity: Double

        switch (colorScheme, model.glassAppearance) {
        case (.dark, .frosted):
            whiteOpacity = 0.10
            blueOpacity = 0.03
            greenOpacity = 0.02
        case (.dark, .translucent):
            whiteOpacity = 0.018
            blueOpacity = 0.006
            greenOpacity = 0.004
        case (.dark, .transparent):
            whiteOpacity = 0.0002
            blueOpacity = 0.0001
            greenOpacity = 0.0001
        case (.light, .frosted):
            whiteOpacity = 0.56
            blueOpacity = 0.14
            greenOpacity = 0.10
        case (.light, .translucent):
            whiteOpacity = 0.11
            blueOpacity = 0.025
            greenOpacity = 0.018
        case (.light, .transparent), (_, _):
            whiteOpacity = 0.002
            blueOpacity = 0.0004
            greenOpacity = 0.0004
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(whiteOpacity),
                Color(red: 0.75, green: 0.90, blue: 1.0).opacity(blueOpacity),
                Color(red: 0.87, green: 0.96, blue: 0.91).opacity(greenOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var warningText: Color {
        if model.isPlaceholderSnapshot {
            return Color(red: 0.20, green: 0.36, blue: 0.68)
        }

        if colorScheme == .dark {
            return Color(red: 1.0, green: 0.90, blue: 0.88)
        }

        return Color(red: 0.53, green: 0.08, blue: 0.08)
    }

    var warningTint: Color {
        if model.isPlaceholderSnapshot {
            return Color(red: 0.45, green: 0.72, blue: 1.0).opacity(0.16)
        }

        if colorScheme == .dark {
            return Color(red: 0.72, green: 0.18, blue: 0.16).opacity(0.34)
        }

        return Color(red: 0.97, green: 0.41, blue: 0.36).opacity(0.22)
    }

    var staleText: Color {
        if colorScheme == .dark {
            return Color(red: 1.0, green: 0.86, blue: 0.62)
        }

        return Color(red: 0.53, green: 0.35, blue: 0.06)
    }

    var staleTint: Color {
        if colorScheme == .dark {
            return Color(red: 0.62, green: 0.38, blue: 0.08).opacity(0.34)
        }

        return Color(red: 0.95, green: 0.74, blue: 0.24).opacity(0.22)
    }

    func statusBanner(text: String, symbol: String, textColor: Color, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(panelFillStyle)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint)
                    }
                    .shadow(color: insetGlowColor.opacity(insetShadowOpacity), radius: 8, x: 0, y: -1)
            }
    }

    func badgeSurface(tint: Color) -> some View {
        Capsule(style: .continuous)
            .fill(controlFillStyle)
            .overlay {
                Capsule(style: .continuous)
                    .fill(tint.opacity(model.glassAppearance == .transparent ? 0.18 : 1))
            }
            .shadow(color: insetGlowColor.opacity(controlShadowOpacity), radius: 6, x: 0, y: -1)
    }

    func glassPanelBackground(
        tint: Color,
        tintOpacity: Double,
        cornerRadius: CGFloat = 22
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(panelFillStyle)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(adjustedTintOpacity(tintOpacity)))
            }
            .shadow(color: insetGlowColor.opacity(insetShadowOpacity), radius: 8, x: 0, y: -1)
    }

    func openProvider() {
        guard let url = model.selectedProvider.launchURL else {
            return
        }

        openURL(url)
    }

    func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    var trackTint: Color {
        if reduceTransparency {
            return colorScheme == .dark
                ? Color.white.opacity(0.14)
                : Color.white.opacity(0.94)
        }

        switch (colorScheme, model.glassAppearance) {
        case (.dark, .frosted):
            return Color.white.opacity(0.18)
        case (.dark, .translucent):
            return Color.white.opacity(0.12)
        case (.dark, .transparent):
            return Color.white.opacity(0.035)
        case (.light, .frosted):
            return Color.white.opacity(0.80)
        case (.light, .translucent):
            return Color.white.opacity(0.54)
        case (.light, .transparent), (_, _):
            return Color.white.opacity(0.10)
        }
    }

    var insetGlowColor: Color {
        if model.glassAppearance == .transparent {
            return colorScheme == .dark
                ? Color.white.opacity(0.015)
                : Color.white.opacity(0.06)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.55)
            : Color.white
    }

    var shellShadowOpacity: Double {
        switch model.glassAppearance {
        case .frosted:
            return 0.07
        case .translucent:
            return 0.02
        case .transparent:
            return 0
        }
    }

    var insetShadowOpacity: Double {
        if reduceTransparency {
            return 0.08
        }

        switch model.glassAppearance {
        case .frosted:
            return 0.16
        case .translucent:
            return 0.04
        case .transparent:
            return 0.002
        }
    }

    var controlShadowOpacity: Double {
        if reduceTransparency {
            return 0.06
        }

        switch model.glassAppearance {
        case .frosted:
            return 0.14
        case .translucent:
            return 0.03
        case .transparent:
            return 0.001
        }
    }

    func adjustedTintOpacity(_ baseOpacity: Double) -> Double {
        switch model.glassAppearance {
        case .frosted:
            return baseOpacity
        case .translucent:
            return baseOpacity * 0.45
        case .transparent:
            return baseOpacity * 0.04
        }
    }
}
