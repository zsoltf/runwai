import Foundation

struct UsageHistoryPoint: Codable, Equatable, Identifiable {
    let timestamp: Date
    let remainingPercent: Double
    var windowResetAt: Date? = nil

    var id: Date { timestamp }
}
