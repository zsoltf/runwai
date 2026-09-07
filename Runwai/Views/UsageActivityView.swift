import Charts
import SwiftUI

struct UsageActivityView: View {
    @Bindable var model: UsageMonitorModel
    let tint: Color
    let text: Color
    let secondaryText: Color
    @State private var range: UsageActivityRange = .today
    @State private var selectedDate: Date?

    init(model: UsageMonitorModel, tint: Color, text: Color, secondaryText: Color,
         initialRange: UsageActivityRange = .today) {
        self.model = model
        self.tint = tint
        self.text = text
        self.secondaryText = secondaryText
        _range = State(initialValue: initialRange)
    }

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
                Picker("Chart range", selection: $range) {
                    ForEach(UsageActivityRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let rate = data.pointsPerHour {
                        Text(model.formattedNumber(rate))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(text)
                        Text("pts / hour \u{00b7} average burn")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(secondaryText)
                    } else {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(tint)
                            .padding(.bottom, 6)
                        Text(data.points.isEmpty ? "A fresh start" : "Learning your pace")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(text)
                    }
                }
                Spacer()
                if let reading {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(model.formattedNumber(reading.remainingPercent))%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(text)
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                    }
                }
            }

            chart(data, reading: reading)
                .frame(height: 250)
                .focusable()
                .onKeyPress(.leftArrow) { moveReading(-1, in: data); return .handled }
                .onKeyPress(.rightArrow) { moveReading(1, in: data); return .handled }
                .accessibilityLabel("Recorded remaining allowance")
                .accessibilityValue(reading.map { "\(model.formattedNumber($0.remainingPercent)) percent" } ?? "No readings")
                .accessibilityAdjustableAction { direction in
                    moveReading(direction == .increment ? 1 : -1, in: data)
                }

            if !data.points.isEmpty {
                HStack(spacing: 18) {
                    legend("recorded usage", dashed: false)
                    if data.showsPace { legend("even pace", dashed: true) }
                }
            }

            Rectangle().fill(secondaryText.opacity(0.15)).frame(height: 1)

            HStack(alignment: .top, spacing: 20) {
                if let reading {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedDate == nil ? "latest reading" : "selected reading")
                            .font(.caption).foregroundStyle(secondaryText)
                        Text(reading.timestamp, format: .dateTime.hour().minute())
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(text).monospacedDigit()
                        Text(reading.timestamp, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2).foregroundStyle(secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if let used = data.observedUse {
                    metric("\(model.formattedNumber(used))%", label: "of allowance", caption: "recorded use")
                }
            }

            if data.pointsPerHour == nil {
                Text(data.points.isEmpty ? "Your next readings will appear here." : "Collecting readings for your burn rate.")
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
            if data.showsPace && !data.points.isEmpty {
              ForEach([data.domain.lowerBound, data.domain.upperBound], id: \.self) { date in
                LineMark(x: .value("Time", date), y: .value("Remaining", data.expectedRemaining(at: date)), series: .value("Series", "pace"))
                    .foregroundStyle(secondaryText.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
              }
            }
            ForEach(data.segments) { segment in
              ForEach(segment.points) { point in
                AreaMark(x: .value("Time", point.timestamp), yStart: .value("Base", 0), yEnd: .value("Remaining", point.remainingPercent), series: .value("Segment", segment.id))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.timestamp), y: .value("Remaining", point.remainingPercent), series: .value("Series", segment.id))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
              }
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

    private func moveReading(_ offset: Int, in data: UsageActivitySeries) {
        guard !data.points.isEmpty else { return }
        let current = data.nearest(to: selectedDate)
        let index = data.points.firstIndex { $0.id == current?.id } ?? data.points.count - 1
        selectedDate = data.points[min(max(index + offset, 0), data.points.count - 1)].timestamp
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
