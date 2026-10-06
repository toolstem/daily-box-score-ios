import SwiftUI

/// One edition: the full box score PDF plus a per-game index.
/// Games involving the user's favorite teams are listed first and
/// jump straight to the right page of the PDF.
struct EditionDetailView: View {
    let edition: Edition

    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var favorites: FavoritesStore

    @State private var games: [GameEntry] = []
    @State private var isLoadingGames = true
    @State private var pdfURL: URL?
    @State private var pdfPage = 1
    @State private var showingPDF = false
    @State private var isDownloading = false
    @State private var downloadError: String?

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
            isLoadingGames = false
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
            pdfPage = game.page ?? 1
            openPDF()
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
