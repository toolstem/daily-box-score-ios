import SwiftUI

/// "From the Archive" rows for the Editions tab. Locked rows open the
/// Archive Pass screen; hidden features (remote switch "off") don't show.
struct ArchiveFeaturesSection: View {
    @EnvironmentObject var store: StoreManager

    var body: some View {
        let onThisDay = store.entryAccess(.onThisDay)
        let birthday = store.entryAccess(.birthdayPaper)
        if onThisDay != .hidden || birthday != .hidden {
            Section {
                if onThisDay != .hidden {
                    row(
                        title: "On This Day",
                        detail: "Papers from today's date, back to 1901",
                        access: onThisDay
                    ) { OnThisDayView() }
                }
                if birthday != .hidden {
                    row(
                        title: "Birthday Paper",
                        detail: "The box scores from the day you were born",
                        access: birthday
                    ) { BirthdayPaperView() }
                }
            } header: {
                SectionHeading(text: "From the Archive")
            }
        }
    }

    @ViewBuilder
    private func row<Destination: View>(
        title: String, detail: String, access: StoreManager.Access,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        let label = VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.headline, design: .serif))
            Text(detail)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
            if access == .needsPass {
                PassTag()
            }
        }
        .padding(.vertical, 4)
        if access == .allowed {
            NavigationLink(destination: destination()) { label }
        } else {
            NavigationLink(destination: ArchivePassView()) { label }
        }
    }
}

/// Shared helpers for the archive features.
enum ArchiveDates {
    static let posix: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { posix.string(from: date) }

    /// "MM-dd" of a date in the user's calendar.
    static func monthDay(_ date: Date) -> String {
        String(string(date).dropFirst(5))
    }

    static func monthDayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM d")
        return f.string(from: date)
    }
}

/// Every paper from one calendar day across the years (default today).
struct OnThisDayView: View {
    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var store: StoreManager
    @State private var day = Date()

    private var matches: [Edition] {
        let md = ArchiveDates.monthDay(day)
        return feed.editions.filter { $0.date.dropFirst(5) == md }
    }

    private var unlocked: [Edition] {
        matches.filter {
            store.access(.onThisDay, year: StoreManager.year($0.date)) == .allowed
        }
    }

    private var lockedCount: Int {
        matches.filter {
            store.access(.onThisDay, year: StoreManager.year($0.date)) == .needsPass
        }.count
    }

    var body: some View {
        List {
            Section {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .font(.system(.body, design: .serif))
            } footer: {
                Text("Only the month and day count. Change it to see any day in history.")
            }

            Section {
                if unlocked.isEmpty && lockedCount == 0 {
                    Text("No papers from \(ArchiveDates.monthDayLabel(day)). Baseball doesn't play in the winter, so pick a day between April and October.")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                }
                ForEach(unlocked) { edition in
                    NavigationLink(destination: EditionDetailView(edition: edition)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(edition.date.prefix(4)))
                                .font(.system(.title3, design: .serif).weight(.bold))
                            Text("\(edition.label) · \(edition.games) \(edition.games == 1 ? "game" : "games")")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                if lockedCount > 0 {
                    NavigationLink(destination: ArchivePassView()) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(lockedCount) more \(lockedCount == 1 ? "paper" : "papers") from this day")
                                .font(.system(.headline, design: .serif))
                            PassTag()
                        }
                    }
                }
            } header: {
                SectionHeading(text: ArchiveDates.monthDayLabel(day))
            }
        }
        .navigationTitle("On This Day")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if feed.editions.isEmpty { await feed.load() }
        }
    }
}

/// The paper from one exact date, or the nearest game days around it.
struct BirthdayPaperView: View {
    @EnvironmentObject var feed: FeedService
    @EnvironmentObject var store: StoreManager
    @State private var day = Calendar.current.date(
        from: DateComponents(year: 1975, month: 7, day: 27)
    ) ?? Date()

    private var allowedEditions: [Edition] {
        feed.editions.filter {
            store.access(.birthdayPaper, year: StoreManager.year($0.date)) == .allowed
        }
    }

    /// Exact match, else the closest paper before and after.
    private var results: (exact: Edition?, before: Edition?, after: Edition?) {
        let target = ArchiveDates.string(day)
        let eds = allowedEditions
        if let exact = eds.first(where: { $0.date == target }) {
            return (exact, nil, nil)
        }
        // Dates sort as strings in YYYY-MM-DD form.
        let before = eds.filter { $0.date < target }.max { $0.date < $1.date }
        let after = eds.filter { $0.date > target }.min { $0.date < $1.date }
        return (nil, before, after)
    }

    private var range: ClosedRange<Date> {
        let first = Calendar.current.date(
            from: DateComponents(year: 1901, month: 1, day: 1)
        ) ?? Date.distantPast
        return first...Date()
    }

    var body: some View {
        List {
            Section {
                DatePicker("Date", selection: $day, in: range, displayedComponents: .date)
                    .font(.system(.body, design: .serif))
            } footer: {
                Text("Pick a birthday, an anniversary, or any day since 1901.")
            }

            let r = results
            Section {
                if let exact = r.exact {
                    editionLink(exact, note: "The paper from that day")
                } else {
                    Text("No games were played that day.")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                    if let before = r.before {
                        editionLink(before, note: "The day before you picked")
                    }
                    if let after = r.after {
                        editionLink(after, note: "The next day with games")
                    }
                }
                if store.access(.birthdayPaper, year: StoreManager.year(ArchiveDates.string(day))) == .needsPass {
                    NavigationLink(destination: ArchivePassView()) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Papers from that year need the Archive Pass")
                                .font(.system(.subheadline, design: .serif))
                            PassTag()
                        }
                    }
                }
            } header: {
                SectionHeading(text: "Your Paper")
            }
        }
        .navigationTitle("Birthday Paper")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if feed.editions.isEmpty { await feed.load() }
        }
    }

    private func editionLink(_ edition: Edition, note: String) -> some View {
        NavigationLink(destination: EditionDetailView(edition: edition)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(edition.label)
                    .font(.system(.headline, design: .serif))
                Text("\(note) · \(edition.games) \(edition.games == 1 ? "game" : "games")")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}
