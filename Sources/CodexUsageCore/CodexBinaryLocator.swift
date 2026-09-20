import Foundation

public protocol CodexBinaryLocating: Sendable {
    func locate() -> URL?
}

public struct CodexBinaryLocator: CodexBinaryLocating, Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (@Sendable (String) -> Bool)? = nil
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable ?? { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func locate() -> URL? {
        var paths: [String] = []
        if let override = environment["CODEX_BIN"], !override.isEmpty {
            paths.append(override)
        }
        paths.append(homeDirectory.appendingPathComponent(".local/bin/codex").path)
        paths.append("/Applications/ChatGPT.app/Contents/Resources/codex")
        paths.append("/opt/homebrew/bin/codex")
        paths.append("/usr/local/bin/codex")
        paths.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path })

        var seen = Set<String>()
        for path in paths {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard seen.insert(normalized).inserted else { continue }
            if isExecutable(normalized) {
                return URL(fileURLWithPath: normalized)
            }
        }
        return nil
    }
}
