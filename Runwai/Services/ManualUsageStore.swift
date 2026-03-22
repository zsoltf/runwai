import Foundation

struct ManualUsageStore {
    private let defaults: UserDefaults
    private let selectedProviderKey = "tokenwatcher.selectedProvider"
    private let glassAppearanceKey = "tokenwatcher.glassAppearance"
    private let heroStyleKey = "tokenwatcher.heroStyle"

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
    }

    func hasSavedSnapshot(for provider: UsageProvider) -> Bool {
        defaults.data(forKey: snapshotKey(for: provider)) != nil
    }

    func loadSnapshot(for provider: UsageProvider) -> UsageSnapshot {
        loadSnapshotData(forKey: snapshotKey(for: provider))
            ?? UsageSnapshot.placeholder(provider: provider)
    }

    func save(_ snapshot: UsageSnapshot, for provider: UsageProvider) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKey(for: provider))
    }

    func clearSnapshot(for provider: UsageProvider) {
        defaults.removeObject(forKey: snapshotKey(for: provider))
    }

    func loadHistory(for provider: UsageProvider) -> [UsageHistoryPoint] {
        loadHistoryData(forKey: historyKey(for: provider)) ?? []
    }

    func saveHistory(_ history: [UsageHistoryPoint], for provider: UsageProvider) {
        guard let data = try? JSONEncoder().encode(history) else {
            return
        }

        defaults.set(data, forKey: historyKey(for: provider))
    }

    func clearHistory(for provider: UsageProvider) {
        defaults.removeObject(forKey: historyKey(for: provider))
    }

    func loadMode(for provider: UsageProvider) -> UsageSourceMode {
        loadModeData(forKey: modeKey(for: provider)) ?? provider.defaultSourceMode
    }

    func saveMode(_ mode: UsageSourceMode, for provider: UsageProvider) {
        defaults.set(mode.rawValue, forKey: modeKey(for: provider))
    }

    func clearMode(for provider: UsageProvider) {
        defaults.removeObject(forKey: modeKey(for: provider))
    }

    func loadSelectedProvider() -> UsageProvider {
        guard
            let rawValue = defaults.string(forKey: selectedProviderKey),
            let provider = UsageProvider(rawValue: rawValue)
        else {
            return .codex
        }

        return provider
    }

    func saveSelectedProvider(_ provider: UsageProvider) {
        defaults.set(provider.rawValue, forKey: selectedProviderKey)
    }

    func loadGlassAppearance() -> GlassAppearance {
        guard
            let rawValue = defaults.string(forKey: glassAppearanceKey),
            let appearance = GlassAppearance(rawValue: rawValue)
        else {
            return .translucent
        }

        return appearance
    }

    func saveGlassAppearance(_ appearance: GlassAppearance) {
        defaults.set(appearance.rawValue, forKey: glassAppearanceKey)
    }

    func loadHeroStyle() -> HeroStyle {
        guard
            let rawValue = defaults.string(forKey: heroStyleKey),
            let heroStyle = HeroStyle(rawValue: rawValue)
        else {
            return .remainingFirst
        }

        return heroStyle
    }

    func saveHeroStyle(_ heroStyle: HeroStyle) {
        defaults.set(heroStyle.rawValue, forKey: heroStyleKey)
    }

    private func loadSnapshotData(forKey key: String) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    private func loadHistoryData(forKey key: String) -> [UsageHistoryPoint]? {
        guard
            let data = defaults.data(forKey: key),
            let history = try? JSONDecoder().decode([UsageHistoryPoint].self, from: data)
        else {
            return nil
        }

        return history
    }

    private func loadModeData(forKey key: String) -> UsageSourceMode? {
        guard
            let rawValue = defaults.string(forKey: key),
            let mode = UsageSourceMode(rawValue: rawValue)
        else {
            return nil
        }

        return mode
    }

    private func snapshotKey(for provider: UsageProvider) -> String {
        "tokenwatcher.snapshot.\(provider.rawValue)"
    }

    private func historyKey(for provider: UsageProvider) -> String {
        "tokenwatcher.history.\(provider.rawValue)"
    }

    private func modeKey(for provider: UsageProvider) -> String {
        "tokenwatcher.sourceMode.\(provider.rawValue)"
    }
}
