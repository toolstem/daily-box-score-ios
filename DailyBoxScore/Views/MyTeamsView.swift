import SwiftUI

/// Favorite teams management plus each favorite's game from the selected edition.
struct MyTeamsView: View {
    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var favorites: FavoritesStore

    @State private var displayGames: [GameEntry] = []
    @State private var displayBoxScores: [BoxScoreGame] = []
    @State private var selectedEdition: Edition?
    @State private var showingPicker = false
    @State private var showingEditionPicker = false
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
                        } header: {
                            SectionHeading(text: "Edition Date")
                        }
                        ForEach(favorites.favoriteTeams) { team in
                            Section {
                                let teamGames = displayGames.filter {
                                    $0.involves(abbrev: team.abbrev)
                                }
                                if teamGames.isEmpty {
                                    Text("No game on this date.")
                                        .foregroundStyle(.secondary)
                                        .font(.system(.body, design: .serif))
                                } else {
                                    ForEach(teamGames) { game in
                                        Button {
                                            selectedBoxScore = displayBoxScores.first {
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
            .sheet(isPresented: $showingEditionPicker) {
                EditionPickerSheet(selectedEdition: $selectedEdition)
            }
            .onChange(of: selectedEdition) { _, newEdition in
                if let edition = newEdition {
                    Task { await loadGames(for: edition) }
                }
            }
            .navigationDestination(item: $selectedBoxScore) { boxScore in
                if let edition = selectedEdition {
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
            if selectedEdition == nil {
                selectedEdition = feed.editions.first
            }
            if let edition = selectedEdition {
                await loadGames(for: edition)
            }
        }
    }

    private func loadGames(for edition: Edition) async {
        displayGames = (try? await feed.games(for: edition)) ?? []
        displayBoxScores = (try? await feed.boxScores(for: edition)) ?? []
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

/// Year/month wheels plus edition list for picking a date in My Teams.
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
