import Foundation

public enum UsageFormatting {
    public static func remainingPercent(usedPercent: Double?) -> Int? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        let remaining = min(100, max(0, 100 - usedPercent))
        return Int(remaining.rounded())
    }

    public static func statusTitle(
        remainingPercent: Int?,
        availableResets: Int,
        language: AppLanguage
    ) -> String {
        guard let remainingPercent else { return "Codex --%" }
        let base = "Codex \(min(100, max(0, remainingPercent)))%"
        guard availableResets > 0 else { return base }

        switch language.resolved() {
        case .zhHans:
            return "\(base)(\(availableResets) 次)"
        case .english, .system:
            let noun = availableResets == 1 ? "reset" : "resets"
            return "\(base) (\(availableResets) \(noun))"
        }
    }
}
