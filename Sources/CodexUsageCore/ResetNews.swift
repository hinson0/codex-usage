import Foundation

public struct ResetForecast: Equatable, Sendable {
    public let announcedAt: Date
    public let date: Date?
    public let isDeadline: Bool

    public func statusText(language: AppLanguage, now: Date) -> String {
        LocalizationCatalog.string(date.map { $0 <= now } == true ? .newsAwaitingConfirmation : .resetPending,
                                   language: language)
    }
}

/// Public global announcements, never the account's own reset history.
public struct ResetNews: Equatable, Sendable {
    public let completedAt: Date?
    public let forecast: ResetForecast?
    public static let sourceURL = URL(string: "https://divin.cc/")!

    public static func decode(_ data: Data) throws -> ResetNews {
        let events = try JSONDecoder().decode([Event].self, from: data)
        let resets = events.filter { $0.tool == "codex" && $0.eventType == "额度重置" }
        let completedAt = resets.filter { $0.eventStatus == "completed" }.compactMap(\.date).max()
        let scheduled = resets.filter {
            $0.eventStatus == "scheduled" && $0.date != nil
                && $0.date! > (completedAt ?? .distantPast)
        }.max { $0.date! < $1.date! }
        return ResetNews(completedAt: completedAt, forecast: scheduled.map {
            ResetForecast(announcedAt: $0.date!, date: Self.parseDate($0.forecast?.at),
                          isDeadline: $0.forecast?.deadline == true)
        })
    }

    public func forecastText(language: AppLanguage, timeZone: TimeZone = .current) -> String {
        guard let date = forecast?.date else {
            return LocalizationCatalog.string(.newsTimeUnknown, language: language)
        }
        return LocalizationCatalog.format(forecast?.isDeadline == true ? .newsExpectedBefore : .newsExpectedAt,
                                          language: language,
                                          LocalizationCatalog.dateTime(date, language: language, timeZone: timeZone))
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string)
    }

    private struct Event: Decodable {
        let tool: String?
        let eventType: String?
        let eventStatus: String?
        let sortTime: String?
        let forecast: Forecast?
        var date: Date? { ResetNews.parseDate(sortTime) }
        struct Forecast: Decodable {
            let at: String?
            let deadline: Bool?
        }
    }
}

public protocol ResetNewsService: Sendable {
    func readNews() async throws -> ResetNews
}

public struct DivinResetNewsService: ResetNewsService {
    public init() {}
    public func readNews() async throws -> ResetNews {
        // An ephemeral, unauthenticated session keeps this public feed separate
        // from Codex credentials and the browser's cookies.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://divin.cc/api/reset-events")!
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200, data.count <= 2_000_000 else {
            throw URLError(.badServerResponse)
        }
        return try ResetNews.decode(data)
    }
}
