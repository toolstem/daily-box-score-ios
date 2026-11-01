import Foundation

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
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let feed = try JSONDecoder().decode(EditionsFeed.self, from: data)
            editions = feed.editions
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load editions. Check your connection and try again."
        }
    }

    /// Whether MLB has games scheduled today (user's local date).
    /// The morning reminder is for tomorrow's edition, which exists
    /// only when games are played today, so the app checks this each
    /// time it opens and schedules or cancels the reminder accordingly.
    /// Returns nil when the schedule can't be checked; callers must not
    /// cancel a pending reminder on nil, only on a confirmed false.
    func gamesScheduledToday() async -> Bool? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        guard let url = URL(
            string: "https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=\(today)"
        ) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }
            let schedule = try JSONDecoder().decode(
                ScheduleResponse.self, from: data
            )
            return schedule.totalGames > 0
        } catch {
            return nil
        }
    }

    func games(for edition: Edition) async throws -> [GameEntry] {
        let (data, _) = try await URLSession.shared.data(from: edition.gamesURL)
        return try JSONDecoder().decode([GameEntry].self, from: data)
    }

    /// Full per-game box scores for an edition, for the native game view.
    /// URL pattern: feed/boxscore_<date>.json (built by trim_boxscores.py).
    func boxScores(for edition: Edition) async throws -> [BoxScoreGame] {
        try await boxScores(forDate: edition.date)
    }

    func boxScores(forDate date: String) async throws -> [BoxScoreGame] {
        let url = URL(
            string: "https://www.toolstem.com/daily-box-score/feed/boxscore_\(date).json"
        )!
        return try await cachedBoxScores(forDate: date, from: url)
    }

    /// Box scores cached on-device (like PDFs) so the native game view
    /// works offline after the first load.
    private func cachedBoxScores(forDate date: String, from url: URL) async throws -> [BoxScoreGame] {
        let dir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
        let dest = dir.appendingPathComponent("boxscore_\(date).json")
        if FileManager.default.fileExists(atPath: dest.path) {
            let data = try Data(contentsOf: dest)
            return try JSONDecoder().decode([BoxScoreGame].self, from: data)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        // Validate before caching so a bad download isn't stored.
        let scores = try JSONDecoder().decode([BoxScoreGame].self, from: data)
        try? data.write(to: dest, options: .atomic)
        return scores
    }

    /// Loads the per-team season logs (cached after the first load).
    func loadTeams() async {
        guard teamEntries.isEmpty else { return }
        isLoadingTeams = true
        defer { isLoadingTeams = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: teamsURL)
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
    func localPDF(for filename: String, from pdfURL: URL) async throws -> URL {
        let dir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
        let dest = dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        let (tmpURL, _) = try await URLSession.shared.download(from: pdfURL)
        // Move into place; if a race cached it first, just use the existing file.
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    /// Returns a local file URL for the edition's PDF, downloading it first
    /// if it isn't cached yet.
    func localPDFURL(for edition: Edition) async throws -> URL {
        try await localPDF(
            for: "boxscores_\(edition.date).pdf", from: edition.pdfURL)
    }

    /// Returns a local file URL for a team game's edition PDF.
    func localPDFURL(for game: TeamGame) async throws -> URL {
        try await localPDF(
            for: game.pdfURL.lastPathComponent, from: game.pdfURL)
    }
}

/// One day of the official MLB schedule, as returned by statsapi.mlb.com.
/// Only the game count is used: it decides whether tomorrow has an edition.
private struct ScheduleResponse: Decodable {
    let totalGames: Int
}
