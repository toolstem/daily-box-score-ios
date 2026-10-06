import Foundation

/// Trimmed per-game box score, as published in site/feed/boxscore_<date>.json.
/// Built by trim_boxscores.py from the full games_<date>.json.
struct BoxScoreGame: Codable, Identifiable, Hashable {
    let pk: Int
    let away: BoxScoreTeam
    let home: BoxScoreTeam
    let linescore: BoxScoreLinescore
    let venue: String?
    let att: Int?
    let series: String?
    let winner: String?
    let loser: String?
    let save: String?

    var id: Int { pk }

    /// e.g. "PHILLIES 4, BRAVES 3"
    var headline: String {
        let a = (away.name ?? "Away").uppercased()
        let h = (home.name ?? "Home").uppercased()
        let ar = linescore.aR ?? 0
        let hr = linescore.hR ?? 0
        // Winner first, matching the newspaper style.
        if hr >= ar {
            return "\(h) \(hr), \(a) \(ar)"
        } else {
            return "\(a) \(ar), \(h) \(hr)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case pk, away, home, linescore, venue, att, series, winner, loser, save
    }
}

struct BoxScoreTeam: Codable {
    let name: String?
    let abbrev: String?
    let batting: [BoxScoreBatter]
    let pitching: [BoxScorePitcher]
}

struct BoxScoreBatter: Codable, Identifiable {
    let name: String?
    let pos: String?
    let ab: Int?
    let r: Int?
    let h: Int?
    let rbi: Int?
    let bb: Int?
    let so: Int?
    let doubles: Int?
    let triples: Int?
    let hr: Int?

    var id: String { "\(name ?? "?")-\(pos ?? "?")" }

    enum CodingKeys: String, CodingKey {
        case name, pos
        case ab = "AB", r = "R", h = "H", rbi = "RBI", bb = "BB", so = "SO"
        case doubles = "2B", triples = "3B", hr = "HR"
    }
}

struct BoxScorePitcher: Codable, Identifiable {
    let name: String?
    let ip: String?
    let h: Int?
    let r: Int?
    let er: Int?
    let bb: Int?
    let so: Int?
    let hr: Int?
    let decision: String?

    var id: String { name ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case name
        case ip = "IP", h = "H", r = "R", er = "ER", bb = "BB", so = "SO", hr = "HR"
        case decision
    }
}

struct BoxScoreLinescore: Codable {
    let innings: [Int]
    let away: [Int?]
    let home: [Int?]
    let aR: Int?
    let hR: Int?
    let aH: Int?
    let hH: Int?
    let aE: Int?
    let hE: Int?

    enum CodingKeys: String, CodingKey {
        case innings, away, home
        case aR = "a_r", hR = "h_r", aH = "a_h", hH = "h_h", aE = "a_e", hE = "h_e"
    }
}
