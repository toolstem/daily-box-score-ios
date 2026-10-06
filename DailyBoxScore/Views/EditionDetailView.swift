import SwiftUI

/// One edition: the full box score PDF plus a per-game index.
/// Games involving the user's favorite teams are listed first and
/// jump straight to the right page of the PDF.
struct EditionDetailView: View {
    let edition: Edition

    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var favorites: FavoritesStore

    @State private var games: [GameEntry] = []
    @State private var boxScores: [BoxScoreGame] = []
    @State private var isLoadingGames = true
    @State private var pdfURL: URL?
    @State private var pdfPage = 1
    @State private var showingPDF = false
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var selectedBoxScore: BoxScoreGame?

    private var favoriteGames: [GameEntry] {
        let favs = Set(favorites.favoriteAbbrevs)
        guard !favs.isEmpty else { return [] }
        return games.filter { game in
            (game.awayAbbrev.map { favs.contains($0) } ?? false)
                || (game.homeAbbrev.map { favs.contains($0) } ?? false)
        }
    }

    private var otherGames: [GameEntry] {
        let favIDs = Set(favoriteGames.map(\.id))
        return games.filter { !favIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if isLoadingGames {
                ProgressView("Loading box scores…")
            } else {
                List {
                    Section {
                        Button {
                            pdfPage = 1
                            openPDF()
                        } label: {
                            HStack {
                                Spacer()
                                if isDownloading {
                                    ProgressView()
                                } else {
                                    Text("Read Full Edition")
                                        .font(.system(.headline, design: .serif).weight(.bold))
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloading)
                    }

                    if !favoriteGames.isEmpty {
                        Section {
                            ForEach(favoriteGames) { game in
                                gameRow(game)
                            }
                        } header: {
                            SectionHeading(text: "Your Teams")
                        }
                    }

                    Section {
                        ForEach(otherGames) { game in
                            gameRow(game)
                        }
                    } header: {
                        SectionHeading(text: favoriteGames.isEmpty ? "Box Scores" : "All Games")
                    }
                }
            }
        }
        .navigationTitle(edition.shortLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                games = try await feed.games(for: edition)
            } catch {
                games = []
            }
            do {
                boxScores = try await feed.boxScores(for: edition)
            } catch {
                boxScores = []
            }
            isLoadingGames = false
        }
        .navigationDestination(item: $selectedBoxScore) { boxScore in
            GameDetailView(
                game: boxScore,
                dateLabel: edition.label,
                pdfURL: edition.pdfURL,
                pdfPage: pageFor(boxScore)
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
    private func gameRow(_ game: GameEntry) -> some View {
        Button {
            if let boxScore = boxScore(for: game) {
                selectedBoxScore = boxScore
            } else {
                // No native data; fall back to the PDF on the game's page.
                pdfPage = game.page ?? 1
                openPDF()
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

    /// Match a GameEntry to its full box score by teams. The feed arrays are
    /// parallel (same order), so the nth entry matches the nth box score
    /// with those teams — this disambiguates doubleheaders.
    private func boxScore(for game: GameEntry) -> BoxScoreGame? {
        let matches = boxScores.filter {
            $0.away.abbrev == game.awayAbbrev && $0.home.abbrev == game.homeAbbrev
        }
        guard !matches.isEmpty else { return nil }
        let entryIndex = games.filter {
            $0.awayAbbrev == game.awayAbbrev && $0.homeAbbrev == game.homeAbbrev
        }.firstIndex(where: { $0.id == game.id }) ?? 0
        return matches[min(entryIndex, matches.count - 1)]
    }

    private func pageFor(_ boxScore: BoxScoreGame) -> Int? {
        boxScores.firstIndex(where: { $0.pk == boxScore.pk })
            .flatMap { idx in games.indices.contains(idx) ? games[idx].page : nil }
    }

    private func openPDF() {
        Task {
            isDownloading = true
            defer { isDownloading = false }
            do {
                pdfURL = try await feed.localPDFURL(for: edition)
                downloadError = nil
                showingPDF = true
            } catch {
                downloadError = "The edition couldn't be downloaded. Check your connection and try again."
            }
        }
    }
}
