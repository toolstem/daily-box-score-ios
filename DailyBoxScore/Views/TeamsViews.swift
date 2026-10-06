import SwiftUI

/// All 30 clubs, with favorites pinned to the top.
struct TeamsListView: View {
    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var favorites: FavoritesStore

    private var favoriteTeams: [MLBTeam] { favorites.favoriteTeams }

    private var otherTeams: [MLBTeam] {
        let favs = Set(favorites.favoriteAbbrevs)
        return MLBTeam.all.filter { !favs.contains($0.abbrev) }
    }

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
                                ForEach(favoriteTeams) { team in
                                    teamRow(team)
                                }
                            } header: {
                                SectionHeading(text: "Favorites")
                            }
                        }
                        Section {
                            ForEach(otherTeams) { team in
                                teamRow(team)
                            }
                        } header: {
                            SectionHeading(
                                text: favoriteTeams.isEmpty ? "Teams" : "All Teams")
                        }
                    }
                    .refreshable {
                        feed.teamEntries = []
                        await feed.loadTeams()
                    }
                }
            }
            .navigationTitle("Teams")
        }
        .task {
            await feed.loadTeams()
        }
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
                if favorites.isFavorite(team) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// One club's full season game log, with an opponent filter.
/// Tapping a game opens the box score PDF on the right page.
struct TeamDetailView: View {
    let abbrev: String

    @EnvironmentObject var feed: FeedService

    @State private var opponentFilter = "All"
    @State private var pdfURL: URL?
    @State private var pdfPage = 1
    @State private var showingPDF = false
    @State private var isDownloading = false
    @State private var downloadError: String?

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
            pdfPage = game.page ?? 1
            openPDF(for: game)
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
