import Foundation

public enum AppVersion {
    public static var current: String? {
        displayString(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    public static func displayString(infoDictionary: [String: Any]) -> String? {
        guard let raw = infoDictionary["CFBundleShortVersionString"] as? String else {
            return nil
        }
        let version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : "v\(version)"
    }
}
