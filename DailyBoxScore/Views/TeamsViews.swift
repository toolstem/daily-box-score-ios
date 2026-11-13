import SwiftUI

/// All 30 clubs grouped by league and division, with favorites pinned to
/// the top. The standard Teams tab: one tab, no separate My Teams tab.
/// A star on every row toggles the favorite; tapping a favorite row
/// opens that team's game on the picked date, or the season log when
/// it did not play.
struct TeamsListView: View {
    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var favorites: FavoritesStore

    /// The edition whose games the Favorites section shows, one row per
    /// favorite team. Defaults to the latest edition.
    @State private var selectedEdition: Edition?
    @State private var showingEditionPicker = false
    @State private var displayGames: [GameEntry] = []
    @State private var displayBoxScores: [BoxScoreGame] = []
    @State private var selectedGameEntry: GameEntry?
    @State private var selectedBoxScore: BoxScoreGame?
    @State private var selectedTeamDetail: MLBTeam?
    @State private var isLoadingGames = false

    private var favoriteTeams: [MLBTeam] { favorites.favoriteTeams }

    var body: some View {
        NavigationStack {
            Group {
                if feed.isLoadingTeams && feed.teamEntries.isEmpty {
                    ProgressView("Loading teams…")
                } else if feed.teamEntries.isEmpty {
                    VStack(spacing: 12) {
                        Text("Couldn't load teams")
                            .font(.system(.headline, design: .serif))
                        Text(feed.teamsErrorMessage ?? "Check your connection and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await feed.loadTeams() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    List {
                        if !favoriteTeams.isEmpty {
                            Section {
                                Button {
                                    showingEditionPicker = true
                                } label: {
                                    HStack {
                                        Text(selectedEdition?.label ?? "Choose date")
                                            .font(.system(.headline, design: .serif))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                ForEach(favoriteTeams) { team in
                                    favoriteRow(team)
                                }
                            } header: {
                                SectionHeading(text: "Favorites")
                            }
                        }
                        ForEach(MLBTeam.standingsGroups, id: \.title) { group in
                            Section {
                                ForEach(group.teams) { team in
                                    teamRow(team)
                                }
                            } header: {
                                SectionHeading(text: group.title)
                            }
                        }
                    }
                    .refreshable {
                        feed.teamEntries = []
                        await feed.loadTeams()
                        if let edition = selectedEdition {
                            await loadGames(for: edition)
                        }
                    }
                }
            }
            .navigationTitle("Teams")
            .sheet(isPresented: $showingEditionPicker) {
                EditionPickerSheet(selectedEdition: $selectedEdition)
            }
            .onChange(of: selectedEdition) { _, newEdition in
                if let edition = newEdition {
                    Task { await loadGames(for: edition) }
                }
            }
            .navigationDestination(item: $selectedBoxScore) { boxScore in
                GameDetailView(
                    game: boxScore,
                    dateLabel: selectedEdition?.label ?? "",
                    pdfURL: selectedEdition?.pdfURL,
                    pdfPage: selectedGameEntry?.page
                )
            }
            .navigationDestination(item: $selectedTeamDetail) { team in
                TeamDetailView(abbrev: team.abbrev)
            }
        }
        .task {
            await feed.loadTeams()
            if feed.editions.isEmpty {
                await feed.load()
            }
            if selectedEdition == nil {
                selectedEdition = feed.editions.first
            }
            if let edition = selectedEdition {
                await loadGames(for: edition)
            }
        }
    }

    /// The edition's games and native box scores for the Favorites
    /// rows. A failed fetch leaves an empty list, so every favorite
    /// shows "No game" rather than stale games.
    private func loadGames(for edition: Edition) async {
        isLoadingGames = true
        defer { isLoadingGames = false }
        displayGames = (try? await feed.games(for: edition)) ?? []
        displayBoxScores = (try? await feed.boxScores(for: edition)) ?? []
    }

    /// One favorite row: team name, season record, star toggle, and the
    /// team's game on the selected edition date. Tapping opens that
    /// game's box score; with no game that day it opens the season log.
    @ViewBuilder
    private func favoriteRow(_ team: MLBTeam) -> some View {
        Button {
            if let game = displayGames.first(where: { $0.involves(abbrev: team.abbrev) }) {
                selectedGameEntry = game
                selectedBoxScore = displayBoxScores.first {
                    $0.away.abbrev == game.awayAbbrev
                        && $0.home.abbrev == game.homeAbbrev
                }
                // No native box score for this game; fall back to the log.
                if selectedBoxScore == nil {
                    selectedTeamDetail = team
                }
            } else if !isLoadingGames {
                selectedTeamDetail = team
            }
            // While the edition's games are still loading and none are
            // shown yet, a tap does nothing.
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(team.abbrev)
                        .font(.system(.body, design: .serif).weight(.bold))
                        .frame(width: 44, alignment: .leading)
                    Text(team.fullName)
                        .font(.system(.body, design: .serif))
                    Spacer()
                    if let record = feed.team(abbrev: team.abbrev)?.record {
                        Text(record)
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        favorites.toggle(team)
                    } label: {
                        Image(systemName: favorites.isFavorite(team) ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(
                        favorites.isFavorite(team)
                            ? "Remove \(team.fullName) from favorites"
                            : "Add \(team.fullName) to favorites"
                    )
                }
                ForEach(gameLines(for: team), id: \.self) { line in
                    HStack {
                        Color.clear.frame(width: 44)
                        Text(line)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One favorite's games on the selected edition date, from that
    /// team's perspective, e.g. "vs Dodgers, W 5-3". "No game" when the
    /// club did not play; "Loading…" while the edition's games load.
    private func gameLines(for team: MLBTeam) -> [String] {
        if isLoadingGames && displayGames.isEmpty {
            return ["Loading…"]
        }
        let lines = displayGames
            .filter { $0.involves(abbrev: team.abbrev) }
            .map { game -> String in
                let isAway = game.awayAbbrev == team.abbrev
                let oppName = isAway
                    ? (game.homeTeam ?? game.homeAbbrev ?? "?")
                    : (game.awayTeam ?? game.awayAbbrev ?? "?")
                let ha = isAway ? "at" : "vs"
                let scored = isAway ? game.awayScore : game.homeScore
                let allowed = isAway ? game.homeScore : game.awayScore
                if let s = scored, let a = allowed {
                    let result = s > a ? "W" : (s < a ? "L" : "T")
                    return "\(ha) \(oppName), \(result) \(s)-\(a)"
                }
                return "\(ha) \(oppName)"
            }
        return lines.isEmpty ? ["No game"] : lines
    }

    private func teamRow(_ team: MLBTeam) -> some View {
        NavigationLink(destination: TeamDetailView(abbrev: team.abbrev)) {
            HStack {
                Text(team.abbrev)
                    .font(.system(.body, design: .serif).weight(.bold))
                    .frame(width: 44, alignment: .leading)
                Text(team.fullName)
                    .font(.system(.body, design: .serif))
                Spacer()
                if let record = feed.team(abbrev: team.abbrev)?.record {
                    Text(record)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(.secondary)
                }
                Button {
                    favorites.toggle(team)
                } label: {
                    Image(systemName: favorites.isFavorite(team) ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    favorites.isFavorite(team)
                        ? "Remove \(team.fullName) from favorites"
                        : "Add \(team.fullName) to favorites"
                )
            }
            .padding(.vertical, 4)
        }
    }
}

/// One club's full season game log, with an opponent filter.
/// Tapping a game opens the native box score; the edition PDF stays one tap away.
struct TeamDetailView: View {
    let abbrev: String

    @EnvironmentObject var feed: FeedService

    @State private var opponentFilter = "All"
    @State private var pdfURL: URL?
    @State private var pdfPage = 1
    @State private var showingPDF = false
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var selectedBoxScore: BoxScoreGame?
    @State private var selectedDateLabel = ""
    @State private var selectedPdfURL: URL?
    @State private var selectedPdfPage: Int?

    private var entry: TeamEntry? { feed.team(abbrev: abbrev) }

    private var opponents: [String] {
        guard let games = entry?.games else { return [] }
        return Array(Set(games.map(\.opp))).sorted()
    }

    private var games: [TeamGame] {
        guard let all = entry?.games else { return [] }
        if opponentFilter == "All" { return all }
        return all.filter { $0.opp == opponentFilter }
    }

    var body: some View {
        Group {
            if let entry = entry {
                List {
                    Section {
                        HStack {
                            if let record = entry.record {
                                Text(record)
                                    .font(.system(.title3, design: .serif).weight(.bold))
                                Text("\(entry.season) regular season")
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Opponent", selection: $opponentFilter) {
                                Text("All teams").tag("All")
                                ForEach(opponents, id: \.self) { opp in
                                    Text(opp).tag(opp)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.system(.subheadline, design: .serif))
                        }
                    }
                    Section {
                        ForEach(games) { game in
                            gameRow(game)
                        }
                    } header: {
                        SectionHeading(
                            text: "\(games.count) game\(games.count == 1 ? "" : "s")")
                    }
                }
            } else if feed.isLoadingTeams {
                ProgressView("Loading \(abbrev)…")
            } else {
                VStack(spacing: 12) {
                    Text("Couldn't load this team")
                        .font(.system(.headline, design: .serif))
                    Button("Try Again") {
                        Task { await feed.loadTeams() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .navigationTitle(entry?.name ?? abbrev)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await feed.loadTeams()
        }
        .navigationDestination(item: $selectedBoxScore) { boxScore in
            GameDetailView(
                game: boxScore,
                dateLabel: selectedDateLabel,
                pdfURL: selectedPdfURL,
                pdfPage: selectedPdfPage
            )
        }
        .fullScreenCover(isPresented: $showingPDF) {
            if let url = pdfURL {
                PDFReaderScreen(url: url, page: pdfPage)
            }
        }
        .alert("Couldn't open the PDF", isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func gameRow(_ game: TeamGame) -> some View {
        Button {
            openBoxScore(for: game)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(game.shortDate)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(.secondary)
                        Text("\(game.ha) \(game.opp)")
                            .font(.system(.body, design: .serif))
                        if let series = game.series {
                            Text(series)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                    Text(game.resultLine)
                        .font(.system(.body, design: .serif).weight(.bold))
                }
                Spacer()
                if isDownloading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
    }

    private func openBoxScore(for game: TeamGame) {
        Task {
            isDownloading = true
            defer { isDownloading = false }
            do {
                let scores = try await feed.boxScores(forDate: game.date)
                // Match by teams: ha == "vs" means we're home, else away.
                let match = scores.first {
                    game.ha == "vs"
                        ? ($0.home.abbrev == abbrev && $0.away.abbrev == game.opp)
                        : ($0.away.abbrev == abbrev && $0.home.abbrev == game.opp)
                }
                if let match {
                    selectedDateLabel = game.label
                    selectedPdfURL = game.pdfURL
                    selectedPdfPage = game.page
                    selectedBoxScore = match
                } else {
                    // No native data; fall back to the PDF on the game's page.
                    openPDF(for: game)
                }
            } catch {
                openPDF(for: game)
            }
        }
    }

    private func openPDF(for game: TeamGame) {
        Task {
            isDownloading = true
            defer { isDownloading = false }
            do {
                pdfURL = try await feed.localPDFURL(for: game)
                downloadError = nil
                showingPDF = true
            } catch {
                downloadError = "The box score couldn't be downloaded. Check your connection and try again."
            }
        }
    }
}

/// Year/month wheels plus edition list for picking a date in the Teams
/// Favorites section. Restored from the old My Teams view.
struct EditionPickerSheet: View {
    @EnvironmentObject var feed: FeedService
    @Binding var selectedEdition: Edition?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedYear: Int?
    @State private var selectedMonth: Int?

    private var monthSymbols: [String] {
        Calendar.current.shortMonthSymbols
    }

    private var years: [Int] {
        let all = feed.editions.compactMap { Int($0.date.prefix(4)) }
        return Array(Set(all)).sorted()
    }

    private func months(for year: Int) -> [Int] {
        let prefix = "\(year)-"
        let ms = feed.editions
            .filter { $0.date.hasPrefix(prefix) }
            .compactMap { Int($0.date.dropFirst(5).prefix(2)) }
        return Array(Set(ms)).sorted()
    }

    private var filteredEditions: [Edition] {
        guard let y = selectedYear, let m = selectedMonth else { return [] }
        let prefix = String(format: "%d-%02d", y, m)
        return feed.editions.filter { $0.date.hasPrefix(prefix) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(years, id: \.self) { y in
                            Text(y, format: .number.grouping(.never)).tag(Optional(y))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedYear) { _, newYear in
                        guard let y = newYear else { return }
                        let ms = months(for: y)
                        if let m = selectedMonth, ms.contains(m) {
                        } else {
                            selectedMonth = ms.last
                        }
                    }
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(months(for: selectedYear ?? 0), id: \.self) { m in
                            Text(monthSymbols[m - 1]).tag(Optional(m))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 110)
                List(filteredEditions) { edition in
                    Button {
                        selectedEdition = edition
                        dismiss()
                    } label: {
                        HStack {
                            Text(edition.label)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(edition.games) games")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if let current = selectedEdition {
                let parts = current.date.split(separator: "-").compactMap { Int($0) }
                if parts.count >= 2 {
                    selectedYear = parts[0]
                    selectedMonth = parts[1]
                }
            } else if let latest = feed.editions.first {
                let parts = latest.date.split(separator: "-").compactMap { Int($0) }
                if parts.count >= 2 {
                    selectedYear = parts[0]
                    selectedMonth = parts[1]
                }
            }
        }
    }
}
