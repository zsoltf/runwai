import SwiftUI

struct DailyBudgetBarView: View {
    let progressFraction: Double
    let targetFraction: Double
    let fillTint: Color
    let budgetTint: Color
    let trackTint: Color
    let isOverBudget: Bool

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progressFraction, 0), 1)
            let clampedTarget = min(max(targetFraction, 0), 1)
            let fillWidth = clampedProgress == 0 ? 0 : max(proxy.size.width * clampedProgress, 14)
            let targetWidth = clampedTarget == 0 ? 0 : max(proxy.size.width * clampedTarget, 14)
            let overflowWidth = max(fillWidth - targetWidth, 0)
            let markerOffset = max(min((proxy.size.width * clampedTarget) - 1, proxy.size.width - 2), 0)

            VStack(alignment: .leading, spacing: isOverBudget ? 4 : 0) {
                if isOverBudget {
                    HStack {
                        Text("today")
                        Spacer()
                        Text("tomorrow")
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.56))
                    .padding(.horizontal, 2)

                    let labelWidth: CGFloat = 42
                    let labelOffset = max(min((proxy.size.width * clampedTarget) - (labelWidth / 2), proxy.size.width - labelWidth), 0)

                    Text("limit")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: labelWidth, alignment: .center)
                        .offset(x: labelOffset)
                }

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(trackTint)

                    if isOverBudget {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [budgetTint.opacity(0.86), budgetTint.opacity(0.68)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: targetWidth)

                        if overflowWidth > 0 {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [fillTint.opacity(0.96), fillTint.opacity(0.78)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: overflowWidth)
                                .offset(x: targetWidth, y: 0)
                        }

                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.white.opacity(0.78))
                            .frame(width: 2, height: 20)
                            .offset(x: markerOffset, y: 0)
                    } else {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [fillTint.opacity(0.96), fillTint.opacity(0.76)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth)
                    }
                }

                if isOverBudget {
                    HStack {
                        Text("safe")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(Color.white.opacity(0.62))

                        Spacer()

                        Text("borrowed")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(fillTint.opacity(0.95))

                        Spacer()

                        Text("left")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
}

struct PaceBarView: View {
    let actualFraction: Double
    let targetFraction: Double
    let milestoneFractions: [Double]
    let fillTint: Color
    let milestoneTint: Color
    let markerTint: Color
    let trackTint: Color

    var body: some View {
        GeometryReader { proxy in
            let clampedActual = min(max(actualFraction, 0), 1)
            let clampedTarget = min(max(targetFraction, 0), 1)
            let width = proxy.size.width
            let fillWidth = clampedActual == 0 ? 0 : max(width * clampedActual, 14)
            let markerOffset = max(min((width * clampedTarget) - 1, width - 2), 0)
            let labelWidth: CGFloat = 42
            let labelOffset = max(min((width * clampedTarget) - (labelWidth / 2), width - labelWidth), 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("target")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(markerTint)
                    .frame(width: labelWidth, alignment: .center)
                    .offset(x: labelOffset)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(trackTint)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [fillTint.opacity(0.95), fillTint.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)

                    ForEach(Array(milestoneFractions.enumerated()), id: \.offset) { _, fraction in
                        let milestoneOffset = max(min((width * fraction) - 1, width - 2), 0)

                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(milestoneTint)
                            .frame(width: 2, height: 7)
                            .offset(x: milestoneOffset, y: 0)
                    }

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(markerTint)
                        .frame(width: 2, height: 22)
                        .offset(x: markerOffset, y: -1)
                }
                .frame(height: 18)
            }
        }
    }
}

struct TrendSparklineView: View {
    let points: [UsageHistoryPoint]
    let windowStart: Date
    let windowEnd: Date
    let targetRemainingPercent: Double
    let lineTint: Color
    let pointTint: Color
    let guideTint: Color
    let targetTint: Color
    let deltaTint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                guidePath(in: CGRect(origin: .zero, size: proxy.size))
                    .stroke(
                        guideTint,
                        style: StrokeStyle(lineWidth: 1.75, dash: [5, 4])
                    )

                actualPath(in: CGRect(origin: .zero, size: proxy.size))
                    .stroke(
                        lineTint,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )

                if let current = points.last {
                    let currentX = xPosition(for: current.timestamp, width: width)
                    let currentY = yPosition(for: current.remainingPercent, height: height)
                    let targetY = yPosition(for: targetRemainingPercent, height: height)

                    Circle()
                        .fill(pointTint)
                        .frame(width: 13, height: 13)
                        .position(x: currentX, y: currentY)

                    targetGapIndicator(
                        x: currentX,
                        currentY: currentY,
                        targetY: targetY
                    )

                    targetPoint(atX: currentX, targetY: targetY)
                }
            }
        }
    }

    private func guidePath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    private func actualPath(in rect: CGRect) -> Path {
        var path = Path()
        let plottedPoints = points.sorted { $0.timestamp < $1.timestamp }

        guard let first = plottedPoints.first else {
            return path
        }

        path.move(
            to: CGPoint(
                x: xPosition(for: first.timestamp, width: rect.width),
                y: yPosition(for: first.remainingPercent, height: rect.height)
            )
        )

        for point in plottedPoints.dropFirst() {
            path.addLine(
                to: CGPoint(
                    x: xPosition(for: point.timestamp, width: rect.width),
                    y: yPosition(for: point.remainingPercent, height: rect.height)
                )
            )
        }

        return path
    }

    private func xPosition(for timestamp: Date, width: CGFloat) -> CGFloat {
        let total = max(windowEnd.timeIntervalSince(windowStart), 1)
        let elapsed = min(max(timestamp.timeIntervalSince(windowStart), 0), total)
        return CGFloat(elapsed / total) * width
    }

    private func yPosition(for remainingPercent: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(remainingPercent, 0), 100)
        let normalized = 1 - (clamped / 100)
        let inset = min(max(height * 0.14, 4), 8)
        return inset + (CGFloat(normalized) * max(height - (inset * 2), 1))
    }

    private func targetPoint(atX x: CGFloat, targetY: CGFloat) -> some View {
        Circle()
            .fill(Color.white.opacity(0.96))
            .overlay {
                Circle()
                    .stroke(targetTint, lineWidth: 1.75)
            }
            .frame(width: 12, height: 12)
            .position(x: x, y: targetY)
    }

    private func targetGapIndicator(x: CGFloat, currentY: CGFloat, targetY: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: currentY))
            path.addLine(to: CGPoint(x: x, y: targetY))
        }
        .stroke(
            deltaTint,
            style: StrokeStyle(lineWidth: 1.75, dash: [4, 3])
        )
    }
}
