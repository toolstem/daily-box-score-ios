import SwiftUI

/// League standings, matching the football app's Standings screen:
/// AL then NL, each with its East, Central and West divisions, and
/// W, L and Pct columns. Baseball has no ties, so there is no T column.
/// Built from the season records already in feed/teams.json, grouped
/// with MLBTeam.standingsGroups, so no extra feed file is needed.
struct StandingsView: View {
    @EnvironmentObject var feed: FeedService

    var body: some View {
        Group {
            if feed.teamEntries.isEmpty {
                Text("Standings have not loaded yet.")
                    .font(.system(.body, design: .serif))
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                List {
                    Section {
                        Text(StandingsView.throughLabel(feed: feed))
                            .font(.system(.caption, design: .serif))
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    ForEach(MLBTeam.standingsGroups, id: \.title) { group in
                        Section {
                            headerRow
                            ForEach(StandingsView.sortedRows(group: group, feed: feed)) { row in
                                teamRow(row)
                            }
                        } header: {
                            SectionHeading(text: group.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Standings")
        // Large, left-aligned title like the Box Scores, Teams,
        // Glossary and Settings tabs; it collapses to inline on scroll.
        .navigationBarTitleDisplayMode(.large)
        .task {
            await feed.loadTeams()
        }
    }

    private var headerRow: some View {
        HStack {
            Text("")
            Spacer()
            Text("W")
                .frame(width: 36, alignment: .trailing)
            Text("L")
                .frame(width: 36, alignment: .trailing)
            Text("Pct")
                .frame(width: 48, alignment: .trailing)
        }
        .font(.system(.footnote, design: .serif))
        .foregroundStyle(.secondary)
    }

    private func teamRow(_ row: StandingsRow) -> some View {
        HStack {
            Text(row.name)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Text("\(row.wins)")
                .frame(width: 36, alignment: .trailing)
            Text("\(row.losses)")
                .frame(width: 36, alignment: .trailing)
            Text(row.pctLabel)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.system(.subheadline, design: .serif))
    }

    /// One division's clubs, most wins first, then fewest losses,
    /// then name.
    @MainActor
    static func sortedRows(group: StandingsGroup, feed: FeedService) -> [StandingsRow] {
        let rows: [StandingsRow] = group.teams.map { team in
            let entry = feed.team(abbrev: team.abbrev)
            return StandingsRow(
                abbrev: team.abbrev,
                name: team.fullName,
                wins: entry?.wins ?? 0,
                losses: entry?.losses ?? 0
            )
        }
        return rows.sorted { a, b in
            if a.wins != b.wins { return a.wins > b.wins }
            if a.losses != b.losses { return a.losses < b.losses }
            return a.name < b.name
        }
    }

    /// "Regular season, through September 27, 2026." The records in
    /// teams.json are regular season only, so the date is the last
    /// regular-season game in the feed, not the newest edition (which
    /// can be a postseason game). Falls back to the newest edition.
    @MainActor
    static func throughLabel(feed: FeedService) -> String {
        var latest: String?
        for entry in feed.teamEntries {
            for game in entry.games where game.series == nil {
                if latest == nil || game.date > latest! {
                    latest = game.date
                }
            }
        }
        if latest == nil {
            latest = feed.editions.first?.date
        }
        guard let dateString = latest else { return "Regular season." }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US")
        output.dateFormat = "MMMM d, yyyy"
        guard let date = input.date(from: dateString) else { return "Regular season." }
        return "Regular season, through \(output.string(from: date))."
    }
}

/// One club's line in a division table.
struct StandingsRow: Identifiable {
    let abbrev: String
    let name: String
    let wins: Int
    let losses: Int

    var id: String { abbrev }

    /// Winning percentage in the paper's form, e.g. ".525" or "1.000".
    var pctLabel: String {
        let games = wins + losses
        guard games > 0 else { return ".000" }
        let pct = Double(wins) / Double(games)
        let text = String(format: "%.3f", pct)
        if text.hasPrefix("0") {
            return String(text.dropFirst())
        }
        return text
    }
}
