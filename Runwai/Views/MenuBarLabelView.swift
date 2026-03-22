import SwiftUI

struct MenuBarLabelView: View {
    let model: UsageMonitorModel

    var body: some View {
        HStack(spacing: 5) {
            RunwaiGlyphView(
                progress: model.menuBarGlyphProgress,
                tint: glyphTint,
                isOverBudget: model.isTodayOverBudget
            )

            Text(model.menuBarLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)

            Text(model.menuBarSecondaryLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(secondaryLabelTint)
                .frame(width: 32, alignment: .leading)
        }
        .help(model.menuBarHelpText)
    }

    private var glyphTint: Color {
        switch model.selectedProvider {
        case .codex:
            return Color(red: 0.47, green: 0.73, blue: 0.24)
        case .codexSpark:
            return Color(red: 0.92, green: 0.64, blue: 0.25)
        case .gemini:
            return Color(red: 0.40, green: 0.66, blue: 0.96)
        }
    }

    private var secondaryLabelTint: Color {
        if model.hasSourceError {
            return Color(red: 0.86, green: 0.39, blue: 0.28)
        }

        if model.isAutomaticSourceStale {
            return Color(red: 0.78, green: 0.57, blue: 0.12)
        }

        return .secondary
    }
}

private struct RunwaiGlyphView: View {
    let progress: Double
    let tint: Color
    let isOverBudget: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 16, height: 10)

            Capsule(style: .continuous)
                .fill(isOverBudget ? Color.red.opacity(0.92) : tint)
                .frame(width: fillWidth, height: 10)

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.primary.opacity(0.82))
                .frame(width: 2, height: 12)
                .offset(x: 9)
        }
        .frame(width: 16, height: 12)
        .accessibilityHidden(true)
        .drawingGroup()
    }

    private var fillWidth: CGFloat {
        max(3, min(16 * progress, 16))
    }
}
