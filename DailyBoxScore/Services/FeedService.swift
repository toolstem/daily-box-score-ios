import Foundation
import PDFKit

/// Loads editions and game indexes from the public website feed,
/// and caches downloaded PDFs on-device for offline reading.
@MainActor
class FeedService: ObservableObject {
    @Published var editions: [Edition] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var teamEntries: [TeamEntry] = []
    @Published var isLoadingTeams = false
    @Published var teamsErrorMessage: String?

    private let feedURL = URL(
        string: "https://www.toolstem.com/daily-box-score/feed/editions.json"
    )!
    private let teamsURL = URL(
        string: "https://www.toolstem.com/daily-box-score/feed/teams.json"
    )!

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: feedURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let feed = try JSONDecoder().decode(EditionsFeed.self, from: data)
            editions = feed.editions
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load editions. Check your connection and try again."
        }
    }

    /// Dates (YYYY-MM-DD, user's local calendar) in the given range that
    /// have MLB games scheduled. A morning's reminder exists only when
    /// games were played the day before, so the app fetches a week of
    /// schedule at a time and puts a reminder on the calendar for each
    /// morning after a game day. Returns nil when the schedule can't be
    /// checked; callers must not cancel pending reminders on nil, only
    /// on a confirmed empty set.
    func gameDates(from start: Date, to end: Date) async -> Set<String>? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let startString = formatter.string(from: start)
        let endString = formatter.string(from: end)
        guard let url = URL(
            string: "https://statsapi.mlb.com/api/v1/schedule?sportId=1&startDate=\(startString)&endDate=\(endString)"
        ) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }
            let schedule = try JSONDecoder().decode(
                ScheduleRangeResponse.self, from: data
            )
            return Set(schedule.dates.filter { $0.totalGames > 0 }.map { $0.date })
        } catch {
            return nil
        }
    }

    func games(for edition: Edition) async throws -> [GameEntry] {
        guard Self.isAllowedFeedURL(edition.gamesURL) else {
            throw URLError(.unsupportedURL)
        }
        let (data, response) = try await URLSession.shared.data(from: edition.gamesURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([GameEntry].self, from: data)
    }

    /// Full per-game box scores for an edition, for the native game view.
    /// URL pattern: feed/boxscore_<date>.json (built by trim_boxscores.py).
    func boxScores(for edition: Edition) async throws -> [BoxScoreGame] {
        try await boxScores(forDate: edition.date)
    }

    func boxScores(forDate date: String) async throws -> [BoxScoreGame] {
        // The date comes from feed data; a bad date must not build a URL.
        guard Self.isValidDateString(date) else {
            throw URLError(.unsupportedURL)
        }
        guard let url = URL(
            string: "https://www.toolstem.com/daily-box-score/feed/boxscore_\(date).json"
        ) else {
            throw URLError(.unsupportedURL)
        }
        return try await cachedBoxScores(forDate: date, from: url)
    }

    /// Box scores cached on-device (like PDFs) so the native game view
    /// works offline after the first load. A cached file from 1.0.1 has
    /// no batting or pitching totals, so it is stale: refetch it instead
    /// of showing the old trimmed box score forever.
    private func cachedBoxScores(forDate date: String, from url: URL) async throws -> [BoxScoreGame] {
        let dir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
        let dest = dir.appendingPathComponent("boxscore_\(date).json")
        var cached: [BoxScoreGame]?
        if FileManager.default.fileExists(atPath: dest.path),
           let data = try? Data(contentsOf: dest),
           let decoded = try? JSONDecoder().decode([BoxScoreGame].self, from: data) {
            if isCompleteBoxScores(decoded) {
                return decoded
            }
            cached = decoded
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                if let cached { return cached }
                throw URLError(.badServerResponse)
            }
            // Validate before caching so a bad download isn't stored.
            let scores = try JSONDecoder().decode([BoxScoreGame].self, from: data)
            try? data.write(to: dest, options: .atomic)
            return scores
        } catch {
            if let cached { return cached }
            throw error
        }
    }

    /// True when every game carries the complete box score: batting and
    /// pitching totals for both teams. The 1.0.1 feed had no totals at
    /// all, so a cached file without them is from the old format.
    private func isCompleteBoxScores(_ scores: [BoxScoreGame]) -> Bool {
        !scores.isEmpty && scores.allSatisfy { game in
            game.away.battingTotals != nil && game.away.pitchingTotals != nil
                && game.home.battingTotals != nil && game.home.pitchingTotals != nil
        }
    }

    /// Loads the per-team season logs (cached after the first load).
    func loadTeams() async {
        guard teamEntries.isEmpty else { return }
        isLoadingTeams = true
        defer { isLoadingTeams = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: teamsURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let feed = try JSONDecoder().decode(TeamsFeed.self, from: data)
            teamEntries = feed.teams
            teamsErrorMessage = nil
        } catch {
            teamsErrorMessage = "Couldn't load teams. Check your connection and try again."
        }
    }

    func team(abbrev: String) -> TeamEntry? {
        teamEntries.first { $0.abbrev == abbrev }
    }

    /// Returns a local file URL for a PDF, downloading it first if needed.
    /// The download requires HTTP 200 and %PDF- magic bytes, so an error
    /// page is never stored as a PDF; a cached entry that no longer opens
    /// is deleted and re-downloaded instead of being served broken.
    func localPDF(for filename: String, from pdfURL: URL) async throws -> URL {
        // Both the remote URL and the cache filename come from feed data.
        guard Self.isAllowedFeedURL(pdfURL),
              isSafeCacheFilename(filename) else {
            throw URLError(.unsupportedURL)
        }
        let dir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
        let dest = dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) {
            if isOpenablePDF(at: dest) {
                return dest
            }
            // Cached entry is corrupt or not a PDF; evict it and re-download.
            try? FileManager.default.removeItem(at: dest)
        }
        let (data, response) = try await URLSession.shared.data(from: pdfURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        // Validate before caching so a bad download isn't stored.
        // Editions are ~50-70 KB; anything over 10 MB is not a box-score PDF.
        guard data.starts(with: Self.pdfMagic), data.count < 10_000_000 else {
            throw URLError(.badServerResponse)
        }
        try data.write(to: dest, options: .atomic)
        return dest
    }

    /// True when the file at url is a PDF that opens with at least one
    /// page. A cached HTML error page fails the magic check; a corrupt or
    /// truncated PDF fails the open check. Either way the caller evicts it.
    private func isOpenablePDF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard (try? handle.read(upToCount: Self.pdfMagic.count)) == Self.pdfMagic else {
            return false
        }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return false
        }
        return true
    }

    /// A cache filename must be one plain component: no separators, no
    /// dot-dot escape out of the caches directory.
    private func isSafeCacheFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename != "." && filename != ".."
            && !filename.contains("/") && !filename.contains("\\")
    }

    /// Returns a local file URL for the edition's PDF, downloading it first
    /// if it isn't cached yet.
    func localPDFURL(for edition: Edition) async throws -> URL {
        guard Self.isValidDateString(edition.date) else {
            throw URLError(.unsupportedURL)
        }
        try await localPDF(
            for: "boxscores_\(edition.date).pdf", from: edition.pdfURL)
    }

    /// Returns a local file URL for a team game's edition PDF.
    func localPDFURL(for game: TeamGame) async throws -> URL {
        try await localPDF(
            for: game.pdfURL.lastPathComponent, from: game.pdfURL)
    }

    // MARK: - Feed URL validation (M2)

    /// First bytes of every PDF file.
    private static let pdfMagic = Data("%PDF-".utf8)

    /// True only for feed URLs the app is willing to fetch: https on the
    /// default port, our host, under /daily-box-score/, and any
    /// YYYY-MM-DD date in the filename must be a real calendar date.
    /// Feed content is untrusted input, so every URL built from it is
    /// checked here before any network call.
    static func isAllowedFeedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host?.lowercased(), host == "www.toolstem.com",
              url.port == nil || url.port == 443,
              url.path.hasPrefix("/daily-box-score/") else { return false }
        return datesInFilename(url.lastPathComponent).allSatisfy(isValidDateString)
    }

    /// Every YYYY-MM-DD substring in a filename, e.g. ["2026-10-28"].
    private static func datesInFilename(_ filename: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}"#) else {
            return []
        }
        let range = NSRange(filename.startIndex..., in: filename)
        return regex.matches(in: filename, range: range).compactMap {
            Range($0.range, in: filename).map { String(filename[$0]) }
        }
    }

    /// True when the string is a real calendar date in YYYY-MM-DD form.
    /// A lenient parser would accept 2026-02-30 by rolling it to March,
    /// so the parsed date must format back to the same string.
    static func isValidDateString(_ date: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let parsed = formatter.date(from: date) else { return false }
        return formatter.string(from: parsed) == date
    }
}

/// One day of the official MLB schedule, as returned by statsapi.mlb.com.
private struct ScheduleDay: Decodable {
    let date: String        // "2026-10-26"
    let totalGames: Int
}

/// A range of schedule days, as returned by statsapi.mlb.com.
private struct ScheduleRangeResponse: Decodable {
    let dates: [ScheduleDay]
}
