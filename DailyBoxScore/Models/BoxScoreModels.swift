import Foundation

/// Trimmed per-game box score, as published in site/feed/boxscore_<date>.json.
/// Built by trim_boxscores.py from the full games_<date>.json.
struct BoxScoreGame: Codable, Identifiable, Hashable {
    let pk: Int
    let away: BoxScoreTeam
    let home: BoxScoreTeam
    let linescore: BoxScoreLinescore
    let venue: String?
    let att: String?
    let gameTime: String?
    let firstPitch: String?
    let series: String?
    let seriesStatus: String?
    let winner: String?
    let loser: String?
    let save: String?
    let winnerRecord: String?
    let loserRecord: String?
    let saveNumber: Int?
    let notes: BoxScoreGameNotes?

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
        case pk, away, home, linescore, venue, att, series, winner, loser, save, notes
        case gameTime = "game_time"
        case firstPitch = "first_pitch"
        case seriesStatus = "series_status"
        case winnerRecord = "winner_record"
        case loserRecord = "loser_record"
        case saveNumber = "save_number"
    }
}

/// Game notes from the paper: hit by pitch, batters faced, inherited
/// runners, umpires, weather, wind. All optional; a missing line is
/// simply not shown.
struct BoxScoreGameNotes: Codable, Hashable {
    let hbp: String?
    let battersFaced: String?
    let inheritedRunners: String?
    let umpires: String?
    let weather: String?
    let wind: String?

    enum CodingKeys: String, CodingKey {
        case hbp, umpires, weather, wind
        case battersFaced = "batters_faced"
        case inheritedRunners = "inherited_runners"
    }
}

/// Team totals for one table. Batting uses AB/R/H/RBI/BB/SO/2B/3B/HR;
/// pitching uses IP/H/R/ER/BB/SO/HR. All optional so older cached
/// editions without totals still decode.
struct BoxScoreTotals: Codable, Hashable {
    let ip: String?
    let ab: Int?
    let r: Int?
    let h: Int?
    let rbi: Int?
    let bb: Int?
    let so: Int?
    let doubles: Int?
    let triples: Int?
    let hr: Int?
    let er: Int?

    enum CodingKeys: String, CodingKey {
        case ip = "IP", ab = "AB", r = "R", h = "H", rbi = "RBI"
        case bb = "BB", so = "SO", hr = "HR", er = "ER"
        case doubles = "2B", triples = "3B"
    }
}

struct BoxScoreTeam: Codable, Hashable {
    let name: String?
    let abbrev: String?
    let batting: [BoxScoreBatter]
    let pitching: [BoxScorePitcher]
    let battingTotals: BoxScoreTotals?
    let pitchingTotals: BoxScoreTotals?
    /// Substitute footnotes, as [letter, note text] pairs, e.g. ["a",
    /// "Grounded out for Williamson in the 7th."]. Letters match the paper.
    let footnotes: [[String]]?
    /// Detail lines under the batting table, as [title, text] pairs,
    /// e.g. ["2B", "Turang (4, Rasmussen); ..."].
    let battingNotes: [[String]]?
    let fieldingNotes: [[String]]?

    enum CodingKeys: String, CodingKey {
        case name, abbrev, batting, pitching, footnotes
        case battingTotals = "batting_totals"
        case pitchingTotals = "pitching_totals"
        case battingNotes = "batting_notes"
        case fieldingNotes = "fielding_notes"
    }
}

struct BoxScoreBatter: Codable, Identifiable, Hashable {
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
    let substitute: Bool?
    /// Footnote letter from the paper (a/b/c), matching the team's
    /// footnotes list. Nil for starters and unlettered substitutes.
    let subLetter: String?

    var id: String { "\(name ?? "?")-\(pos ?? "?")" }

    enum CodingKeys: String, CodingKey {
        case name, pos, substitute
        case ab = "AB", r = "R", h = "H", rbi = "RBI", bb = "BB", so = "SO"
        case doubles = "2B", triples = "3B", hr = "HR"
        case subLetter = "sub_letter"
    }
}

struct BoxScorePitcher: Codable, Identifiable, Hashable {
    let name: String?
    let ip: String?
    let h: Int?
    let r: Int?
    let er: Int?
    let bb: Int?
    let so: Int?
    let hr: Int?
    let decision: String?
    /// Pitches-strikes, e.g. "86-58". Nil when the data has no pitch counts.
    let ps: String?

    var id: String { name ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case name, ps
        case ip = "IP", h = "H", r = "R", er = "ER", bb = "BB", so = "SO", hr = "HR"
        case decision
    }
}

struct BoxScoreLinescore: Codable, Hashable {
    let innings: [Int]
    let away: [Int?]
    let home: [Int?]
    let aR: Int?
    let hR: Int?
    let aH: Int?
    let hH: Int?
    let aE: Int?
    let hE: Int?
    let aLob: Int?
    let hLob: Int?

    enum CodingKeys: String, CodingKey {
        case innings, away, home
        case aR = "a_r", hR = "h_r", aH = "a_h", hH = "h_h", aE = "a_e", hE = "h_e"
        case aLob = "a_lob", hLob = "h_lob"
    }
}
