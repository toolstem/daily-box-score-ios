import Foundation

/// Remote switches for the Archive Pass, read from one small JSON file
/// on our own website: feed/app_config.json. They let us turn paid
/// features off (or make them free) without an app update, for example
/// if MLB ever objects to charging for features built on its data.
///
/// File format (every key optional):
///
///     {
///       "version": 1,
///       "archive_pass": { "mode": "paid", "mlb_features": "paid" },
///       "tips_enabled": true,
///       "free_share_days": 7
///     }
///
/// mode / mlb_features:
///   "paid" = normal: Archive Pass features need the pass.
///   "free" = the features work for everyone and nothing is sold.
///   "off"  = the features are hidden.
/// mlb_features applies only to papers from 2001 on (MLB Stats API data);
/// mode applies to everything.
///
/// Safety rules:
/// - Missing file, network error, or a file that does not parse: keep the
///   last good switches (sticky), so a kill stays killed offline and a
///   deleted file never re-enables anything by surprise.
/// - Never fetched: defaults (paid, paid, tips on, 7 days).
/// - A value this version does not recognise counts as "free": never charge
///   on a setting we don't understand, never lock a paying user out.
/// - Fetch only our own https host, under 16 KB. Nothing about the user is
///   sent; it is a plain GET like the editions feed.
@MainActor
final class RemoteSwitches: ObservableObject {
    enum Mode: String {
        case paid, free, off
    }

    struct Values: Equatable {
        var passMode: Mode = .paid
        var mlbFeatures: Mode = .paid
        var tipsEnabled = true
        var freeShareDays = 7
    }

    @Published private(set) var values: Values

    var passMode: Mode { values.passMode }
    var mlbFeatures: Mode { values.mlbFeatures }
    var tipsEnabled: Bool { values.tipsEnabled }
    var freeShareDays: Int { values.freeShareDays }

    static let configURL = URL(
        string: "https://www.toolstem.com/daily-box-score/feed/app_config.json"
    )!
    private static let cacheKey = "remoteSwitchesV1"
    private static let maxBytes = 16_384

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = Self.parse(data) {
            values = cached
        } else {
            values = Values()
        }
    }

    /// Fetches the switches. Any failure leaves the current values alone.
    func refresh() async {
        var request = URLRequest(
            url: Self.configURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        guard let result = try? await URLSession.shared.data(for: request) else {
            return
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.host?.lowercased() == "www.toolstem.com",
              data.count <= Self.maxBytes,
              let parsed = Self.parse(data) else { return }
        values = parsed
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    /// Parses the config file. Returns nil only when the file is not a
    /// JSON object at all; individual bad or missing keys fall back as
    /// described above.
    nonisolated static func parse(_ data: Data) -> Values? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }
        var v = Values()
        if let pass = root["archive_pass"] as? [String: Any] {
            v.passMode = mode(pass["mode"])
            v.mlbFeatures = mode(pass["mlb_features"])
        }
        if let tips = root["tips_enabled"] as? Bool {
            v.tipsEnabled = tips
        }
        if let days = root["free_share_days"] as? Int {
            v.freeShareDays = min(max(days, 0), 3650)
        }
        return v
    }

    /// Missing key = paid (normal). Unknown value = free (fail open for
    /// users, fail closed for selling).
    nonisolated private static func mode(_ raw: Any?) -> Mode {
        guard let raw else { return .paid }
        guard let text = raw as? String,
              let m = Mode(rawValue: text.lowercased()) else { return .free }
        return m
    }
}
