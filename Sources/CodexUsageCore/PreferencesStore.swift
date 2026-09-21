import Foundation

public enum LastResetResult: Codable, Equatable, Sendable {
    case outcome(ResetOutcome)
    case failure(UsageDisplayError)
}

public struct LastResetRecord: Codable, Equatable, Sendable {
    public let attemptedAt: Date
    public let result: LastResetResult

    public init(attemptedAt: Date, result: LastResetResult) {
        self.attemptedAt = attemptedAt
        self.result = result
    }
}

public final class PreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let appearanceKey: String
    private let languageKey: String
    private let lastResetKey: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "local.codexusage") {
        self.defaults = defaults
        appearanceKey = "\(keyPrefix).appearance"
        languageKey = "\(keyPrefix).language"
        lastResetKey = "\(keyPrefix).lastReset"
    }

    public var appearance: AppAppearance {
        get {
            let stored = AppAppearance(rawValue: defaults.string(forKey: appearanceKey) ?? "")
            return stored == .dark ? .dark : .light
        }
        set { defaults.set(newValue.rawValue, forKey: appearanceKey) }
    }

    public var language: AppLanguage {
        get {
            let stored = AppLanguage(rawValue: defaults.string(forKey: languageKey) ?? "")
            return stored == .zhHans ? .zhHans : .english
        }
        set { defaults.set(newValue.rawValue, forKey: languageKey) }
    }

    public var resetHistory: [LastResetRecord] {
        guard let data = defaults.data(forKey: lastResetKey) else { return [] }
        if let records = try? JSONDecoder().decode([LastResetRecord].self, from: data) {
            return Array(records.prefix(3))
        }
        if let legacyRecord = try? JSONDecoder().decode(LastResetRecord.self, from: data) {
            return [legacyRecord]
        }
        return []
    }

    public var lastReset: LastResetRecord? {
        resetHistory.first
    }

    public func saveLastReset(_ record: LastResetRecord) throws {
        try saveResetHistory([record] + resetHistory)
    }

    public func saveResetHistory(_ records: [LastResetRecord]) throws {
        defaults.set(
            try JSONEncoder().encode(Array(records.prefix(3))),
            forKey: lastResetKey
        )
    }
}
