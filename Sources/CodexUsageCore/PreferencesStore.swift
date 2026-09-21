import Foundation

public final class PreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let appearanceKey: String
    private let languageKey: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "local.codexusage") {
        self.defaults = defaults
        appearanceKey = "\(keyPrefix).appearance"
        languageKey = "\(keyPrefix).language"
        defaults.removeObject(forKey: "\(keyPrefix).lastReset")
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
}
