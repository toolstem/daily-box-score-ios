import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            EditionsListView()
                .tabItem {
                    Label("Editions", systemImage: "newspaper")
                }
            TeamsListView()
                .tabItem {
                    Label("Teams", systemImage: "sportscourt")
                }
            MyTeamsView()
                .tabItem {
                    Label("My Teams", systemImage: "star")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

struct EditionsListView: View {
    @EnvironmentObject var feed: FeedService

    @State private var jumpDate = Date()
    @State private var jumpedEdition: Edition?

    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }

    var body: some View {
        NavigationStack {
            Group {
                if feed.isLoading && feed.editions.isEmpty {
                    ProgressView("Loading editions…")
                } else if feed.editions.isEmpty {
                    VStack(spacing: 12) {
                        Text("Couldn't load editions")
                            .font(.system(.headline, design: .serif))
                        Text(feed.errorMessage ?? "Check your connection and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await feed.load() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            NameplateView()
                        }
                        Section {
                            ForEach(feed.editions) { edition in
                                NavigationLink(destination: EditionDetailView(edition: edition)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(edition.label)
                                            .font(.system(.headline, design: .serif))
                                        Text("\(edition.games) games")
                                            .font(.system(.subheadline, design: .serif))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            SectionHeading(text: "Editions")
                        }
                    }
                    .refreshable {
                        await feed.load()
                    }
                }
            }
            .navigationTitle("Box Scores")
            .toolbar {
                if let range = feed.editionDateRange {
                    ToolbarItem(placement: .primaryAction) {
                        DatePicker(
                            "Jump to a date",
                            selection: $jumpDate,
                            in: range,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .onChange(of: jumpDate) { _, newDate in
                            let ds = dateFormatter.string(from: newDate)
                            jumpedEdition = feed.editions.first {
                                $0.date == ds
                            }
                        }
                    }
                }
            }
            .navigationDestination(item: $jumpedEdition) { edition in
                EditionDetailView(edition: edition)
            }
        }
        .task {
            if feed.editions.isEmpty {
                await feed.load()
            }
            if let latest = feed.editions.first,
               let d = dateFormatter.date(from: latest.date) {
                jumpDate = d
            }
        }
    }
}
