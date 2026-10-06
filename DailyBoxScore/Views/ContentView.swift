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
    @State private var selectedYear: Int?
    @State private var selectedMonth: Int?

    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }

    /// Years with editions, newest first.
    private var years: [Int] {
        let ys = Set(feed.editions.map { Int($0.date.prefix(4)) ?? 0 })
        return ys.filter { $0 > 0 }.sorted(by: >)
    }

    private var monthSymbols: [String] {
        DateFormatter().shortMonthSymbols
    }

    /// Months (1-12) with editions in the selected year.
    private func months(for year: Int) -> [Int] {
        let prefix = "\(year)-"
        let ms = Set(feed.editions
            .filter { $0.date.hasPrefix(prefix) }
            .compactMap { Int($0.date.dropFirst(5).prefix(2)) })
        return ms.sorted()
    }

    private var filteredEditions: [Edition] {
        guard let y = selectedYear, let m = selectedMonth else { return feed.editions }
        let prefix = String(format: "%d-%02d", y, m)
        return feed.editions.filter { $0.date.hasPrefix(prefix) }
    }

    /// Year strip + month strip for jumping through the archive.
    @ViewBuilder
    private var yearMonthPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(years, id: \.self) { y in
                        Button("\(y)") {
                            selectedYear = y
                            // Keep the month if it exists in the new year, else pick the latest.
                            let ms = months(for: y)
                            if let m = selectedMonth, ms.contains(m) {
                                // keep
                            } else {
                                selectedMonth = ms.last
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedYear == y ? .accentColor : .secondary)
                    }
                }
            }
            if let y = selectedYear {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(months(for: y), id: \.self) { m in
                            Button(monthSymbols[m - 1]) { selectedMonth = m }
                                .buttonStyle(.bordered)
                                .tint(selectedMonth == m ? .accentColor : .secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
                            yearMonthPicker
                        } header: {
                            SectionHeading(text: "Browse by Month")
                        }
                        Section {
                            ForEach(filteredEditions) { edition in
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
                let cal = Calendar.current
                let y = cal.component(.year, from: d)
                let m = cal.component(.month, from: d)
                selectedYear = y
                selectedMonth = m
            }
        }
    }
}
