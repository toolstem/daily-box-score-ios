import Foundation

/// One of the 30 Major League clubs.
/// The app deliberately uses no team logos anywhere — names and scores only.
struct MLBTeam: Identifiable, Codable, Hashable {
    /// e.g. "NYY" — matches the abbreviations published in the box score feed.
    let abbrev: String
    let city: String
    let name: String

    var id: String { abbrev }
    var fullName: String { "\(city) \(name)" }

    /// League/division groupings in display order. The single source of
    /// truth for the Teams tab's standings layout, and the pattern for
    /// the other sports' Teams tabs.
    static let standingsGroups: [StandingsGroup] = [
        StandingsGroup(league: "AL", division: "East",
                       abbrevs: ["BAL", "BOS", "NYY", "TB", "TOR"]),
        StandingsGroup(league: "AL", division: "Central",
                       abbrevs: ["CWS", "CLE", "DET", "KC", "MIN"]),
        StandingsGroup(league: "AL", division: "West",
                       abbrevs: ["HOU", "LAA", "ATH", "SEA", "TEX"]),
        StandingsGroup(league: "NL", division: "East",
                       abbrevs: ["ATL", "MIA", "NYM", "PHI", "WSH"]),
        StandingsGroup(league: "NL", division: "Central",
                       abbrevs: ["CHC", "CIN", "MIL", "PIT", "STL"]),
        StandingsGroup(league: "NL", division: "West",
                       abbrevs: ["AZ", "COL", "LAD", "SD", "SF"]),
    ]

    static func team(abbrev: String) -> MLBTeam? {
        all.first { $0.abbrev == abbrev }
    }

    /// Older team codes in the archive feed, mapped to today's club.
    /// Retrosheet codes cover 1901-2000 (e.g. BRO and LAN are the Dodgers,
    /// SLA and MLA are today's Orioles, WS1 is today's Twins, WS2 is today's
    /// Rangers). BLA, the 1901-02 Baltimore Orioles, is left out on
    /// purpose: it is a defunct franchise with no club today (the feed
    /// marks it franchise "BLA"), so it gets no "today" line. The MLB codes
    /// FLA, LA, MON, OAK and ANA appear in 2001 to 2024 editions. Each code
    /// belongs to exactly one franchise, so the mapping is unambiguous.
    static let legacyCodes: [String: String] = [
        "ANA": "LAA", "CAL": "LAA",
        "ARI": "AZ",
        "BSN": "ATL", "MLN": "ATL",
        "MLA": "BAL", "SLA": "BAL",
        "CHA": "CWS", "CHW": "CWS",
        "CHN": "CHC",
        "KCA": "KC", "KCR": "KC",
        "BRO": "LAD", "LAN": "LAD", "LA": "LAD",
        "FLO": "MIA", "FLA": "MIA",
        "SE1": "MIL",
        "WS1": "MIN",
        "NYA": "NYY",
        "NYN": "NYM",
        "PHA": "ATH", "KC1": "ATH", "OAK": "ATH",
        "SDN": "SD", "SDP": "SD",
        "NY1": "SF", "SFN": "SF", "SFG": "SF",
        "SLN": "STL",
        "TBA": "TB", "TBD": "TB",
        "WS2": "TEX",
        "MON": "WSH", "WAS": "WSH", "WSN": "WSH",
    ]

    /// Older nicknames each club has played under since 1901, from
    /// Retrosheet's team nickname history. Used to confirm that an old
    /// code really is that club: spring training and World Baseball
    /// Classic games reuse some codes (COL is also Colombia), and those
    /// must not be matched to a big-league club.
    static let formerNicknames: [String: [String]] = [
        "ATL": ["Beaneaters", "Doves", "Rustlers", "Heps", "Bees"],
        "BAL": ["Brewers", "Browns"],
        "BOS": ["Americans", "Somersets"],
        "CHC": ["Orphans"],
        "CIN": ["Redlegs"],
        "CLE": ["Blues", "Broncos", "Naps", "Indians"],
        "HOU": ["Colt .45's", "Colt .45s"],
        "LAD": ["Superbas", "Robins"],
        "MIL": ["Pilots"],
        "MIN": ["Senators", "Nationals"],
        "NYY": ["Highlanders", "Hilltoppers"],
        "PHI": ["Blue Jays"],
        "TB": ["Devil Rays"],
        "TEX": ["Senators"],
        "WSH": ["Expos"],
    ]

    /// Short forms the feed uses for today's own name, which need no
    /// "today" line.
    static let sameNameAliases: [String: [String]] = [
        "AZ": ["D-backs", "Dbacks"],
        "ATH": ["A's"],
    ]

    /// Today's club for a team as it appears in a feed. The feed's own
    /// franchise link wins when present; a franchise that is not a club
    /// today (BLA, the defunct 1901-02 Orioles) means no club, never a
    /// guess from the code. Otherwise the team code is used,
    /// directly if it is a current code or through legacyCodes, but only
    /// when the nickname fits that club, so an exhibition team that
    /// shares a code is never matched.
    static func today(code: String?, franchise: String?, nickname: String? = nil) -> MLBTeam? {
        if let franchise, !franchise.isEmpty {
            return team(abbrev: franchise)
        }
        guard let code else { return nil }
        var found = team(abbrev: code)
        if found == nil, let mapped = legacyCodes[code] {
            found = team(abbrev: mapped)
        }
        guard let club = found else { return nil }
        if let nick = nickname, !nick.isEmpty,
           !isSameName(nick, club: club),
           !(formerNicknames[club.abbrev] ?? []).contains(where: { simplified($0) == simplified(nick) }) {
            return nil
        }
        return club
    }

    /// A short caption naming today's club when the name in the paper is
    /// an older one, e.g. "Red Sox today" under the 1901 Boston Americans,
    /// or "Los Angeles Dodgers today" under the Brooklyn Dodgers. Returns
    /// nil when the old name matches today's, so nothing extra is shown.
    static func todayCaption(code: String?, franchise: String?,
                             nickname: String?, fullName: String?) -> String? {
        guard let club = today(code: code, franchise: franchise, nickname: nickname) else {
            return nil
        }
        let nick = nickname ?? ""
        if !nick.isEmpty, !isSameName(nick, club: club) {
            return "\(club.name) today"
        }
        // Same nickname: the city may have changed (Brooklyn to Los
        // Angeles). Skip names with no city, such as plain "Athletics".
        if let full = fullName, !full.isEmpty,
           simplified(full) != simplified(nick),
           simplified(full) != simplified(club.fullName) {
            return "\(club.fullName) today"
        }
        return nil
    }

    private static func isSameName(_ nickname: String, club: MLBTeam) -> Bool {
        if simplified(nickname) == simplified(club.name) {
            return true
        }
        let aliases = sameNameAliases[club.abbrev] ?? []
        return aliases.contains { simplified($0) == simplified(nickname) }
    }

    /// Letters and digits only, lowercased, so "St.Louis" matches "St. Louis".
    private static func simplified(_ text: String) -> String {
        let kept = text.lowercased().filter { $0.isLetter || $0.isNumber }
        return String(kept)
    }

    static let all: [MLBTeam] = [
        MLBTeam(abbrev: "AZ", city: "Arizona", name: "Diamondbacks"),
        MLBTeam(abbrev: "ATL", city: "Atlanta", name: "Braves"),
        MLBTeam(abbrev: "BAL", city: "Baltimore", name: "Orioles"),
        MLBTeam(abbrev: "BOS", city: "Boston", name: "Red Sox"),
        MLBTeam(abbrev: "CHC", city: "Chicago", name: "Cubs"),
        MLBTeam(abbrev: "CWS", city: "Chicago", name: "White Sox"),
        MLBTeam(abbrev: "CIN", city: "Cincinnati", name: "Reds"),
        MLBTeam(abbrev: "CLE", city: "Cleveland", name: "Guardians"),
        MLBTeam(abbrev: "COL", city: "Colorado", name: "Rockies"),
        MLBTeam(abbrev: "DET", city: "Detroit", name: "Tigers"),
        MLBTeam(abbrev: "HOU", city: "Houston", name: "Astros"),
        MLBTeam(abbrev: "KC", city: "Kansas City", name: "Royals"),
        MLBTeam(abbrev: "LAA", city: "Los Angeles", name: "Angels"),
        MLBTeam(abbrev: "LAD", city: "Los Angeles", name: "Dodgers"),
        MLBTeam(abbrev: "MIA", city: "Miami", name: "Marlins"),
        MLBTeam(abbrev: "MIL", city: "Milwaukee", name: "Brewers"),
        MLBTeam(abbrev: "MIN", city: "Minnesota", name: "Twins"),
        MLBTeam(abbrev: "NYY", city: "New York", name: "Yankees"),
        MLBTeam(abbrev: "NYM", city: "New York", name: "Mets"),
        MLBTeam(abbrev: "ATH", city: "Sacramento", name: "Athletics"),
        MLBTeam(abbrev: "PHI", city: "Philadelphia", name: "Phillies"),
        MLBTeam(abbrev: "PIT", city: "Pittsburgh", name: "Pirates"),
        MLBTeam(abbrev: "SD", city: "San Diego", name: "Padres"),
        MLBTeam(abbrev: "SF", city: "San Francisco", name: "Giants"),
        MLBTeam(abbrev: "SEA", city: "Seattle", name: "Mariners"),
        MLBTeam(abbrev: "STL", city: "St. Louis", name: "Cardinals"),
        MLBTeam(abbrev: "TB", city: "Tampa Bay", name: "Rays"),
        MLBTeam(abbrev: "TEX", city: "Texas", name: "Rangers"),
        MLBTeam(abbrev: "TOR", city: "Toronto", name: "Blue Jays"),
        MLBTeam(abbrev: "WSH", city: "Washington", name: "Nationals"),
    ].sorted { $0.fullName < $1.fullName }
}

/// One league/division grouping for the Teams tab.
struct StandingsGroup {
    let league: String
    let division: String
    let abbrevs: [String]

    /// The clubs in this group, in alphabetical order.
    var teams: [MLBTeam] {
        abbrevs.compactMap(MLBTeam.team(abbrev:))
            .sorted { $0.fullName < $1.fullName }
    }

    /// Section heading, e.g. "AL East".
    var title: String { "\(league) \(division)" }
}
