import Foundation

/// One bucket of usage from `mmx quota show --output json`.
///
/// `mmx` returns an array of these under `model_remains`. Known names include
/// `general` (text/vision/audio pool), `video`, and others. The `video` bucket
/// is filtered out in `QuotaStore.refresh()` because we don't display it.
/// Field names mirror the CLI JSON.
struct ModelQuota: Identifiable, Hashable, Codable {
    var id: String { modelName }

    let modelName: String
    let intervalStart: Date
    let intervalEnd: Date
    let intervalRemainsMs: Int
    let intervalTotalCount: Int
    let intervalUsageCount: Int
    let intervalRemainingPercent: Int
    let intervalStatus: Int
    let intervalBoostPermille: Int?

    let weeklyStart: Date
    let weeklyEnd: Date
    let weeklyRemainsMs: Int
    let weeklyTotalCount: Int
    let weeklyUsageCount: Int
    let weeklyRemainingPercent: Int
    let weeklyStatus: Int
    let weeklyBoostPermille: Int?

    /// Explicit CodingKeys: the wire format is snake_case, our properties are
    /// mixed case. `JSONDecoder.convertFromSnakeCase` would have lowercased the
    /// leading "Interval" which we want to keep capitalized for Swift style.
    enum CodingKeys: String, CodingKey {
        case modelName                      = "model_name"
        case intervalStart                  = "start_time"
        case intervalEnd                    = "end_time"
        case intervalRemainsMs              = "remains_time"
        case intervalTotalCount             = "current_interval_total_count"
        case intervalUsageCount             = "current_interval_usage_count"
        case intervalRemainingPercent       = "current_interval_remaining_percent"
        case intervalStatus                 = "current_interval_status"
        case intervalBoostPermille          = "interval_boost_permille"
        case weeklyStart                    = "weekly_start_time"
        case weeklyEnd                      = "weekly_end_time"
        case weeklyRemainsMs                = "weekly_remains_time"
        case weeklyTotalCount               = "current_weekly_total_count"
        case weeklyUsageCount               = "current_weekly_usage_count"
        case weeklyRemainingPercent         = "current_weekly_remaining_percent"
        case weeklyStatus                   = "current_weekly_status"
        case weeklyBoostPermille            = "weekly_boost_permille"
    }

    /// Window length derived from the timestamps. mmx returns different windows
    /// for different models (e.g. general uses 4h, video uses 24h). The percentage
    /// is what matters for display, but the window length is useful context.
    var intervalWindowSeconds: Int { Int(intervalEnd.timeIntervalSince(intervalStart)) }
    var weeklyWindowSeconds: Int { Int(weeklyEnd.timeIntervalSince(weeklyStart)) }

    /// Used in the UI: "general" → "General", "video" → "Video".
    var displayName: String {
        switch modelName.lowercased() {
        case "general": return "General"
        case "video":   return "Video"
        case "speech":  return "Speech"
        case "image":   return "Image"
        case "music":   return "Music"
        case "search":  return "Search"
        case "vision":  return "Vision"
        default:        return modelName.capitalized
        }
    }

    /// Human-readable window length: 4h, 24h, 7d, etc.
    var intervalWindowLabel: String { Self.formatDuration(intervalWindowSeconds) }
    var weeklyWindowLabel: String { Self.formatDuration(weeklyWindowSeconds) }

    static func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "—" }
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        if seconds >= 3600  { return "\(seconds / 3600)h" }
        return "\(seconds / 60)m"
    }
}

/// Top-level wrapper for the JSON returned by `mmx quota show --output json`.
struct QuotaResponse: Codable {
    let modelRemains: [ModelQuota]
    let baseRespStatusCode: Int
    let baseRespStatusMsg: String

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }

    enum BaseRespKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelRemains = try c.decode([ModelQuota].self, forKey: .modelRemains)
        let base = try c.nestedContainer(keyedBy: BaseRespKeys.self, forKey: .baseResp)
        baseRespStatusCode = try base.decode(Int.self, forKey: .statusCode)
        baseRespStatusMsg = try base.decode(String.self, forKey: .statusMsg)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelRemains, forKey: .modelRemains)
        var base = c.nestedContainer(keyedBy: BaseRespKeys.self, forKey: .baseResp)
        try base.encode(baseRespStatusCode, forKey: .statusCode)
        try base.encode(baseRespStatusMsg, forKey: .statusMsg)
    }
}

private let isoDecoder: JSONDecoder = {
    let d = JSONDecoder()
    // mmx returns unix milliseconds for *_time fields
    d.dateDecodingStrategy = .custom { decoder in
        let c = try decoder.singleValueContainer()
        let ms = try c.decode(Int64.self)
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }
    return d
}()

/// Fetches quota by spawning `mmx quota show --output json` and decoding the result.
///
/// Spawning the CLI (vs. talking HTTP directly) is the only way to use whatever
/// auth `mmx auth login` has cached — which is exactly the workflow the user asked
/// for. If `mmx` ever stops shipping a `quota` subcommand we'll need to revisit.
enum QuotaFetcher {
    enum FetchError: Error, LocalizedError {
        case nonZeroExit(Int32, String)
        case parseFailed(String)
        case apiError(statusCode: Int, msg: String)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code, let stderr):
                return "mmx exited with code \(code): \(stderr)"
            case .parseFailed(let body):
                return "Failed to parse mmx response: \(body.prefix(200))"
            case .apiError(let c, let m):
                return "mmx API error \(c): \(m)"
            }
        }
    }

    static func fetch() async throws -> QuotaResponse {
        // Locate `mmx` at runtime instead of hardcoding /opt/homebrew/bin/mmx.
        // Recipients of this app may have installed mmx via npm, brew (Intel
        // vs Apple Silicon), or nix — all of which land in different paths.
        guard let mmxPath = Self.locateMmx() else {
            throw FetchError.parseFailed(
                "`mmx` CLI not found. Install with `brew install mmx-cli` " +
                "or `npm install -g mmx-cli`, then relaunch."
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mmxPath)
        process.arguments = ["quota", "show", "--output", "json", "--non-interactive"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw FetchError.parseFailed("could not spawn \(mmxPath): \(error)")
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw FetchError.nonZeroExit(process.terminationStatus, errStr)
        }

        let parsed: QuotaResponse
        do {
            parsed = try isoDecoder.decode(QuotaResponse.self, from: outData)
        } catch {
            throw FetchError.parseFailed(outStr)
        }

        if parsed.baseRespStatusCode != 0 {
            throw FetchError.apiError(statusCode: parsed.baseRespStatusCode,
                                      msg: parsed.baseRespStatusMsg)
        }
        return parsed
    }

    /// Find the `mmx` binary by consulting PATH, then a handful of common
    /// install locations. We do this in-process instead of via `/usr/bin/which`
    /// because the latter can lie when the process PATH differs from the
    /// user's interactive shell PATH (common with launchd-launched apps).
    private static func locateMmx() -> String? {
        // 1. Known absolute paths (most common installs).
        let absoluteProbe: [String] = [
            "/opt/homebrew/bin/mmx",         // Apple Silicon + Homebrew (default)
            "/usr/local/bin/mmx",            // Intel + Homebrew / older macs
            "/opt/local/bin/mmx",            // Homebrew on custom prefix
            "/usr/bin/mmx",                  // system (unlikely but cheap to check)
            "\(NSHomeDirectory())/.local/bin/mmx",            // pipx / pip --user
            "\(NSHomeDirectory())/.npm-global/bin/mmx",      // npm with custom prefix
        ]
        for path in absoluteProbe {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }

        // 2. nvm: look in the latest installed Node version's bin.
        let nvmDir = "\(NSHomeDirectory())/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions
                .filter { $0.hasPrefix("v") }
                .sorted { lhs, rhs in
                    let l = lhs.dropFirst().split(separator: ".").compactMap { Int($0) }
                    let r = rhs.dropFirst().split(separator: ".").compactMap { Int($0) }
                    for (a, b) in zip(l, r) where a != b { return a < b }
                    return l.count < r.count
                }
            for v in sorted.reversed() {
                let candidate = "\(nvmDir)/\(v)/bin/mmx"
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }

        // 3. Last resort: walk PATH from the current process.
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/mmx"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
}

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var quotas: [ModelQuota] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?
    /// Currently-configured refresh interval. Read by the UI to render the
    /// interval label. `start(interval:)` re-arms the timer when this changes.
    @Published private(set) var refreshInterval: TimeInterval = 60

    private var timer: Timer?

    /// Start a recurring fetch. `interval` seconds between polls; first fetch is
    /// immediate so the UI is never blank. Safe to call repeatedly: it
    /// invalidates the previous timer before scheduling a new one.
    func start(interval: TimeInterval = 60) {
        refreshInterval = interval
        Task { @MainActor in await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // Hop to MainActor explicitly. The store is @MainActor, so a plain
            // `Task { await self?.refresh() }` would inherit the timer thread's
            // isolation and then re-enter the actor — the explicit annotation
            // makes the intent (and any future bug) obvious.
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    /// Convenience for the menu items in the popup.
    func setRefreshInterval(_ seconds: TimeInterval) {
        start(interval: seconds)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Models to hide from the UI. The `mmx` API returns a `video` bucket we
    /// don't want to display, so we filter it out at the store level — that
    /// way every view (menu bar popup, floating window) gets the same list.
    static let hiddenModelNames: Set<String> = ["video"]

    func refresh() async {
        do {
            let r = try await QuotaFetcher.fetch()
            self.quotas = r.modelRemains
                .filter { !Self.hiddenModelNames.contains($0.modelName.lowercased()) }
                .sorted { $0.modelName < $1.modelName }
            self.lastError = nil
            self.lastUpdated = Date()
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}
