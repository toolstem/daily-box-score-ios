import SwiftUI

/// Favorite teams management plus each favorite's latest game.
struct MyTeamsView: View {
    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var favorites: FavoritesStore

    @State private var latestGames: [GameEntry] = []
    @State private var latestBoxScores: [BoxScoreGame] = []
    @State private var latestEdition: Edition?
    @State private var showingPicker = false
    @State private var selectedBoxScore: BoxScoreGame?

    var body: some View {
        NavigationStack {
            Group {
                if favorites.favoriteTeams.isEmpty {
                    VStack(spacing: 16) {
                        Text("Pick your teams")
                            .font(.system(.title2, design: .serif).weight(.bold))
                        Text("Your favorite clubs' box scores will appear first in every edition.")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Choose Teams") { showingPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(favorites.favoriteTeams) { team in
                            Section {
                                let teamGames = latestGames.filter {
                                    $0.involves(abbrev: team.abbrev)
                                }
                                if teamGames.isEmpty {
                                    Text("No game in the latest edition.")
                                        .foregroundStyle(.secondary)
                                        .font(.system(.body, design: .serif))
                                } else {
                                    ForEach(teamGames) { game in
                                        Button {
                                            selectedBoxScore = latestBoxScores.first {
                                                $0.away.abbrev == game.awayAbbrev
                                                    && $0.home.abbrev == game.homeAbbrev
                                            }
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(game.headline)
                                                        .font(.system(.body, design: .serif))
                                                    Text(game.matchup)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            } header: {
                                SectionHeading(text: team.fullName)
                            } footer: {
                                NavigationLink(
                                    destination: TeamDetailView(abbrev: team.abbrev)
                                ) {
                                    Text("Full season game log")
                                        .font(.system(.subheadline, design: .serif))
                                }
                            }
                        }
                    }
                    .refreshable {
                        await loadLatestGames()
                    }
                }
            }
            .navigationTitle("My Teams")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(favorites.favoriteTeams.isEmpty ? "Add" : "Edit") {
                        showingPicker = true
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                TeamPickerView()
            }
            .navigationDestination(item: $selectedBoxScore) { boxScore in
                if let edition = latestEdition {
                    GameDetailView(
                        game: boxScore,
                        dateLabel: edition.label,
                        pdfURL: edition.pdfURL,
                        pdfPage: nil
                    )
                }
            }
        }
        .task {
            if feed.editions.isEmpty {
                await feed.load()
            }
            await loadLatestGames()
        }
    }

    private func loadLatestGames() async {
        guard let latest = feed.editions.first else { return }
        latestEdition = latest
        latestGames = (try? await feed.games(for: latest)) ?? []
        latestBoxScores = (try? await feed.boxScores(for: latest)) ?? []
    }
}

struct TeamPickerView: View {
    @EnvironmentObject var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(MLBTeam.all) { team in
                Button {
                    favorites.toggle(team)
                } label: {
                    HStack {
                        Text(team.fullName)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.primary)
                        Spacer()
                        if favorites.isFavorite(team) {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Favorite Teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
