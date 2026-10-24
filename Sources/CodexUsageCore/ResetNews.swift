import Foundation

/// A single public website record, never the account's reset history.
public struct ResetAnnouncement: Equatable, Sendable {
    public enum Stage: String, Sendable {
        case scheduled
        case rollingOut = "rolling_out"
        case completed
    }

    public let summary: String
    public let occasion: String?
    public let updatedAt: Date?
    public let stage: Stage
    public let announcedAt: Date
    public let forecastAt: Date?
    public let forecastBound: String?

    public func statusText(language: AppLanguage, now: Date) -> String {
        if stage == .completed { return LocalizationCatalog.string(.newsCompleted, language: language) }
        // Match the website's one-hour grace for estimates expressed as "around".
        // An elapsed estimate is not evidence of completion.
        let overdue = forecastAt.map {
            now.timeIntervalSince($0) > (forecastBound == "around" ? 3_600 : 0)
        } ?? (now.timeIntervalSince(announcedAt) > 86_400)
        let key: LocalizationKey = overdue ? .newsAwaitingConfirmation
            : (stage == .rollingOut ? .newsRollingOut : .resetPending)
        return LocalizationCatalog.string(key, language: language)
    }
}

public struct ResetNews: Equatable, Sendable {
    public let latest: ResetAnnouncement?
    public static let sourceURL = URL(string: "https://divin.cc/")!

    public static func decode(_ data: Data, now: Date = .now) throws -> ResetNews {
        let events = try JSONDecoder().decode(Feed.self, from: data).events
        let records = events.filter {
            $0.tool == "codex" && ["usage_reset", "reset_card", "credit_grant"].contains($0.type)
                && $0.announcedDate.map { $0 <= now } == true
                && ResetAnnouncement.Stage(rawValue: $0.stage) != nil
                && !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        // The website's banner prefers its latest pending signal from the past
        // seven days. If there is no signal, show just the latest timeline record.
        let latest = records.first {
            $0.stage != "completed" && $0.announcedDate.map { now.timeIntervalSince($0) < 7 * 86_400 } == true
        } ?? records.first
        return ResetNews(latest: latest.flatMap { event in
            guard let announcedAt = event.announcedDate,
                  let stage = ResetAnnouncement.Stage(rawValue: event.stage) else { return nil }
            return ResetAnnouncement(summary: event.summary, occasion: event.occasion,
                updatedAt: parseDate(event.updatedAt), stage: stage, announcedAt: announcedAt,
                forecastAt: parseDate(event.forecast?.at), forecastBound: event.forecast?.bound)
        })
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string)
    }

    private struct Feed: Decodable {
        let events: [Event]
    }

    private struct Event: Decodable {
        let tool: String
        let type: String
        let stage: String
        let summary: String
        let occasion: String?
        let announcedAt: String?
        let completedAt: String?
        let updatedAt: String?
        let forecast: Forecast?
        var announcedDate: Date? { ResetNews.parseDate(announcedAt) }
        var date: Date? { ResetNews.parseDate(completedAt) ?? announcedDate }

        struct Forecast: Decodable {
            let at: String?
            let bound: String?
        }
    }
}

public protocol ResetNewsService: Sendable {
    func readNews() async throws -> ResetNews
}

public struct DivinResetNewsService: ResetNewsService {
    public init() {}
    public func readNews() async throws -> ResetNews {
        // Public feed: no Codex credentials, browser cookies, or persistent cache.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "https://divin.cc/api/events")!)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200, data.count <= 2_000_000 else {
            throw URLError(.badServerResponse)
        }
        return try ResetNews.decode(data)
    }
}
