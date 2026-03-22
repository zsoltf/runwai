import Foundation

struct UsageHistoryPoint: Codable, Equatable, Identifiable {
    let timestamp: Date
    let remainingPercent: Double

    var id: Date { timestamp }
}
