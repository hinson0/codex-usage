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
        get { AppAppearance(rawValue: defaults.string(forKey: appearanceKey) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: appearanceKey) }
    }

    public var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: languageKey) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: languageKey) }
    }

    public var lastReset: LastResetRecord? {
        guard let data = defaults.data(forKey: lastResetKey) else { return nil }
        return try? JSONDecoder().decode(LastResetRecord.self, from: data)
    }

    public func saveLastReset(_ record: LastResetRecord) throws {
        defaults.set(try JSONEncoder().encode(record), forKey: lastResetKey)
    }
}
