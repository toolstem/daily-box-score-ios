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

    static func team(abbrev: String) -> MLBTeam? {
        all.first { $0.abbrev == abbrev }
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
