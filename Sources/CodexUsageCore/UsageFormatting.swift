import Foundation

public struct UsageWindowSelection: Equatable, Sendable {
    public let fiveHour: RateLimitWindow?
    public let longer: RateLimitWindow?

    public init(fiveHour: RateLimitWindow?, longer: RateLimitWindow?) {
        self.fiveHour = fiveHour
        self.longer = longer
    }
}

public enum UsageFormatting {
    public static func remainingPercent(usedPercent: Double?) -> Int? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        let remaining = min(100, max(0, 100 - usedPercent))
        return Int(remaining.rounded())
    }

    public static func statusTitle(
        fiveHourRemainingPercent: Int?,
        longerRemainingPercent: Int?,
        availableResets: Int,
        language: AppLanguage
    ) -> String {
        let percentages = [fiveHourRemainingPercent, longerRemainingPercent]
            .compactMap { $0 }
            .map { "\(min(100, max(0, $0)))%" }
        guard !percentages.isEmpty else { return "Codex --%" }
        let base = "Codex \(percentages.joined(separator: "-"))"
        guard availableResets > 0 else { return base }

        switch language.resolved() {
        case .zhHans:
            return "\(base)(\(availableResets) 次)"
        case .english, .system:
            let noun = availableResets == 1 ? "reset" : "resets"
            return "\(base) (\(availableResets) \(noun))"
        }
    }

    public static func windows(in bucket: RateLimitBucket?) -> UsageWindowSelection {
        guard let bucket else {
            return UsageWindowSelection(fiveHour: nil, longer: nil)
        }

        let windows = [bucket.primary, bucket.secondary].compactMap { $0 }
        let fiveHour = windows.first { $0.windowDurationMins == 300 }
        let longer = windows
            .filter { $0.windowDurationMins != 300 }
            .max {
                ($0.windowDurationMins ?? -1) < ($1.windowDurationMins ?? -1)
            }

        return UsageWindowSelection(fiveHour: fiveHour, longer: longer)
    }
}
