import Charts
import SwiftUI

struct UsageActivityView: View {
    @Bindable var model: UsageMonitorModel
    let tint: Color
    let text: Color
    let secondaryText: Color
    @State private var range: UsageActivityRange = .window
    @State private var selectedDate: Date?

    private var series: UsageActivitySeries {
        UsageActivitySeries(
            history: model.trackedHistoryPoints, range: range,
            windowStart: model.windowStart, windowEnd: model.resetAt, now: model.now
        )
    }

    var body: some View {
        let data = series
        let reading = data.nearest(to: selectedDate)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("usage history")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
                Spacer()
                Picker("Chart range", selection: $range) {
                    ForEach(UsageActivityRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 174)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.map { "\(model.formattedNumber($0.remainingPercent))%" } ?? "--")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(text)
                    Text("allowance remaining")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryText)
                }
                Spacer()
                if let reading {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(reading.timestamp, format: .dateTime.hour().minute())
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(text)
                        Text(reading.timestamp, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                    }
                }
            }

            chart(data, reading: reading)
                .frame(height: 210)

            HStack(spacing: 18) {
                legend("recorded usage", dashed: false)
                legend("even pace", dashed: true)
            }

            Rectangle().fill(secondaryText.opacity(0.15)).frame(height: 1)

            HStack(alignment: .top, spacing: 20) {
                metric(data.pointsPerHour.map { "\(model.formattedNumber($0))" } ?? "--", label: "pts / hour", caption: "average burn")
                    .help("Allowance percentage points used per hour between the first and last readings in this view, including breaks.")
                Spacer(minLength: 0)
                metric(data.observedUse.map { "\(model.formattedNumber($0))%" } ?? "--", label: "of allowance", caption: "used in view")
            }

            if data.points.count < 2 {
                Text("Collecting history")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
        }
        .help("Hover over the chart to inspect recorded allowance. Percentages are not raw token counts.")
        .onChange(of: range) { selectedDate = nil }
        .onChange(of: model.selectedProvider) { selectedDate = nil }
    }

    private func chart(_ data: UsageActivitySeries, reading: UsageHistoryPoint?) -> some View {
        Chart {
            ForEach([data.domain.lowerBound, data.domain.upperBound], id: \.self) { date in
                LineMark(x: .value("Time", date), y: .value("Remaining", data.expectedRemaining(at: date)), series: .value("Series", "pace"))
                    .foregroundStyle(secondaryText.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
            }
            ForEach(data.points) { point in
                AreaMark(x: .value("Time", point.timestamp), yStart: .value("Base", 0), yEnd: .value("Remaining", point.remainingPercent))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.timestamp), y: .value("Remaining", point.remainingPercent), series: .value("Series", "recorded"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            if let reading {
                RuleMark(x: .value("Reading", reading.timestamp))
                    .foregroundStyle(secondaryText.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                PointMark(x: .value("Time", reading.timestamp), y: .value("Remaining", reading.remainingPercent))
                    .foregroundStyle(tint)
                    .symbolSize(65)
                    .accessibilityLabel("Recorded remaining allowance")
                    .accessibilityValue("\(model.formattedNumber(reading.remainingPercent)) percent")
            }
        }
        .chartXScale(domain: data.domain)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(secondaryText.opacity(0.12))
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%").font(.caption2).foregroundStyle(secondaryText)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: range == .today ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(secondaryText)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let x = location.x - geometry[frame].origin.x
                            selectedDate = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            selectedDate = nil
                        }
                    }
            }
        }
    }

    private func legend(_ title: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 20, y: 4))
            }
            .stroke(dashed ? secondaryText.opacity(0.6) : tint, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
            .frame(width: 20, height: 8)
            Text(title).font(.caption2).foregroundStyle(secondaryText)
        }
    }

    private func metric(_ value: String, label: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.caption.weight(.medium)).foregroundStyle(secondaryText)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(text)
            Text(label).font(.caption2).foregroundStyle(secondaryText)
        }
    }
}
