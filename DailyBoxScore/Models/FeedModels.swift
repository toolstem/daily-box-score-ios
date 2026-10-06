import Foundation

/// One daily edition, as published in feed/editions.json on the website.
struct Edition: Identifiable, Codable, Hashable {
    let date: String          // "2026-09-24"
    let label: String         // "Thursday, September 24, 2026"
    let games: Int
    let pdfURL: URL
    let gamesURL: URL
    let size: Int

    var id: String { date }

    /// Short label for navigation titles, e.g. "Sep 24, 2026".
    var shortLabel: String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = .none
        if let d = input.date(from: date) {
            return output.string(from: d)
        }
        return date
    }

    enum CodingKeys: String, CodingKey {
        case date, label, games, size
        case pdfURL = "pdf_url"
        case gamesURL = "games_url"
    }
}

struct EditionsFeed: Codable {
    let updated: String
    let editions: [Edition]
}

/// One game in a club's season log, as published in feed/teams.json.
struct TeamGame: Codable, Identifiable {
    let date: String        // "2026-09-30"
    let label: String       // "Wednesday, September 30, 2026"
    let opp: String         // opponent abbrev, e.g. "NYY"
    let ha: String          // "vs" or "at"
    let scored: Int?
    let allowed: Int?
    let won: Bool
    let series: String?     // e.g. "AL Wild Card, G2"; nil for regular season
    let pdfURL: URL
    let page: Int?

    var id: String { "\(date)-\(ha)-\(opp)-\(scored ?? -1)x\(allowed ?? -1)" }

    /// e.g. "Sep 30, 2026"
    var shortDate: String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = .none
        if let d = input.date(from: date) {
            return output.string(from: d)
        }
        return date
    }

    /// e.g. "W 4–3" from this team's perspective.
    var resultLine: String {
        let s = scored.map(String.init) ?? "-"
        let a = allowed.map(String.init) ?? "-"
        return "\(won ? "W" : "L") \(s)–\(a)"
    }

    enum CodingKeys: String, CodingKey {
        case date, label, opp, ha, scored, allowed, won, series, page
        case pdfURL = "pdf_url"
    }
}

/// One club's season entry in feed/teams.json.
struct TeamEntry: Codable, Identifiable {
    let abbrev: String
    let name: String        // "Boston Red Sox"
    let season: String      // "2026"
    let wins: Int
    let losses: Int
    let games: [TeamGame]

    var id: String { abbrev }

    /// Season record, or nil when unavailable (0–0 means "not computed").
    var record: String? {
        guard wins + losses > 0 else { return nil }
        return "\(wins)–\(losses)"
    }
}

struct TeamsFeed: Codable {
    let updated: String
    let teams: [TeamEntry]
}

/// One game inside an edition, as published in feed/games_<date>.json.
/// `page` is the 1-based page of the PDF this game's box score is printed on.
struct GameEntry: Codable, Identifiable {
    let awayName: String?
    let awayTeam: String?
    let awayAbbrev: String?
    let homeName: String?
    let homeTeam: String?
    let homeAbbrev: String?
    let awayScore: Int?
    let homeScore: Int?
    let page: Int?

    var id: String {
        "\(awayAbbrev ?? "A")@\(homeAbbrev ?? "H")"
    }

    func involves(abbrev: String) -> Bool {
        awayAbbrev == abbrev || homeAbbrev == abbrev
    }

    /// e.g. "Mets 1, Rangers 3"
    var headline: String {
        let a = "\(awayTeam ?? "?") \(awayScore.map(String.init) ?? "-")"
        let h = "\(homeTeam ?? "?") \(homeScore.map(String.init) ?? "-")"
        return "\(a), \(h)"
    }

    /// e.g. "New York Mets at Texas Rangers"
    var matchup: String {
        "\(awayName ?? awayTeam ?? "?") at \(homeName ?? homeTeam ?? "?")"
    }

    enum CodingKeys: String, CodingKey {
        case awayName = "away_name"
        case awayTeam = "away_team"
        case awayAbbrev = "away_abbrev"
        case homeName = "home_name"
        case homeTeam = "home_team"
        case homeAbbrev = "home_abbrev"
        case awayScore = "away_score"
        case homeScore = "home_score"
        case page
    }
}
