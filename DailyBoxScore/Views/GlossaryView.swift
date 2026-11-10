import SwiftUI

/// Glossary tab: every abbreviation in the box scores, in plain words.
/// The box score itself stays clean; new readers tap here when they need it.
/// Every entry below appears in the app or the paper. The list was checked
/// against the real October 2026 editions, so it covers the note labels
/// the feed actually produces (GIDP, SF, SAC, SB, CS, DP, TB, RISP).
struct GlossaryView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Every abbreviation in the box scores, in plain words. The box score itself stays as printed; tap here when a letter does not make sense yet.")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.secondary)
                }
                battingSection
                pitchingSection
                linescoreSection
                decisionsSection
                notesSection
                positionsSection
                otherSection
            }
            .navigationTitle("Glossary")
        }
    }

    private var battingSection: some View {
        Section {
            GlossaryRow(abbr: "AB", meaning: "At-bats")
            GlossaryRow(abbr: "R", meaning: "Runs scored")
            GlossaryRow(abbr: "H", meaning: "Hits")
            GlossaryRow(abbr: "RBI", meaning: "Runs batted in")
            GlossaryRow(abbr: "BB", meaning: "Bases on balls (walks)")
            GlossaryRow(abbr: "SO", meaning: "Strikeouts")
            GlossaryRow(abbr: "2B", meaning: "Doubles")
            GlossaryRow(abbr: "3B", meaning: "Triples")
            GlossaryRow(abbr: "HR", meaning: "Home runs")
        } header: {
            SectionHeading(text: "Batting")
        }
    }

    private var pitchingSection: some View {
        Section {
            GlossaryRow(abbr: "IP", meaning: "Innings pitched")
            GlossaryRow(abbr: "H", meaning: "Hits allowed")
            GlossaryRow(abbr: "R", meaning: "Runs allowed")
            GlossaryRow(abbr: "ER", meaning: "Earned runs")
            GlossaryRow(abbr: "BB", meaning: "Walks allowed")
            GlossaryRow(abbr: "SO", meaning: "Strikeouts")
            GlossaryRow(abbr: "HR", meaning: "Home runs allowed")
            GlossaryRow(abbr: "P-S", meaning: "Pitches-Strikes: pitches thrown, then strikes")
        } header: {
            SectionHeading(text: "Pitching")
        }
    }

    private var linescoreSection: some View {
        Section {
            GlossaryRow(abbr: "R", meaning: "Runs")
            GlossaryRow(abbr: "H", meaning: "Hits")
            GlossaryRow(abbr: "E", meaning: "Errors")
        } header: {
            SectionHeading(text: "Linescore")
        }
    }

    private var decisionsSection: some View {
        Section {
            GlossaryRow(abbr: "W", meaning: "Winning pitcher")
            GlossaryRow(abbr: "L", meaning: "Losing pitcher")
            GlossaryRow(abbr: "SV", meaning: "Save")
            GlossaryRow(abbr: "S", meaning: "Save (shown in parentheses after a pitcher's name)")
            GlossaryRow(abbr: "WP", meaning: "Winning pitcher (paper)")
            GlossaryRow(abbr: "LP", meaning: "Losing pitcher (paper)")
        } header: {
            SectionHeading(text: "Decisions")
        }
    }

    private var notesSection: some View {
        Section {
            GlossaryRow(abbr: "2B", meaning: "Doubles: who hit them")
            GlossaryRow(abbr: "3B", meaning: "Triples: who hit them")
            GlossaryRow(abbr: "HR", meaning: "Home runs: who hit them")
            GlossaryRow(abbr: "TB", meaning: "Total bases")
            GlossaryRow(abbr: "SF", meaning: "Sacrifice flies")
            GlossaryRow(abbr: "SAC", meaning: "Sacrifice bunts (also written SH)")
            GlossaryRow(abbr: "SH", meaning: "Sacrifice hit (bunt)")
            GlossaryRow(abbr: "GIDP", meaning: "Grounded into double play")
            GlossaryRow(abbr: "SB", meaning: "Stolen bases")
            GlossaryRow(abbr: "CS", meaning: "Caught stealing")
            GlossaryRow(abbr: "DP", meaning: "Double plays turned")
            GlossaryRow(abbr: "E", meaning: "Errors")
            GlossaryRow(abbr: "HBP", meaning: "Hit by pitch")
            GlossaryRow(abbr: "LOB", meaning: "Left on base")
            GlossaryRow(abbr: "Team RISP", meaning: "Team hits with runners in scoring position, written like 3-for-8")
            GlossaryRow(abbr: "Runners left in scoring position, 2 out", meaning: "Runners still on base when the third out was made")
            GlossaryRow(abbr: "2-out RBI", meaning: "Runs batted in with two outs")
            GlossaryRow(abbr: "Outfield assists", meaning: "Throws from the outfield that put a runner out")
            GlossaryRow(abbr: "Pickoffs", meaning: "Runners picked off base")
            GlossaryRow(abbr: "PO", meaning: "Putouts")
            GlossaryRow(abbr: "Batters faced", meaning: "Batters a pitcher faced")
            GlossaryRow(abbr: "Inherited runners-scored", meaning: "Runners on base when a reliever entered, who then scored")
        } header: {
            SectionHeading(text: "Notes under the tables")
        }
    }

    private var positionsSection: some View {
        Section {
            GlossaryRow(abbr: "C", meaning: "Catcher")
            GlossaryRow(abbr: "1B", meaning: "First base")
            GlossaryRow(abbr: "2B", meaning: "Second base")
            GlossaryRow(abbr: "3B", meaning: "Third base")
            GlossaryRow(abbr: "SS", meaning: "Shortstop")
            GlossaryRow(abbr: "LF", meaning: "Left field")
            GlossaryRow(abbr: "CF", meaning: "Center field")
            GlossaryRow(abbr: "RF", meaning: "Right field")
            GlossaryRow(abbr: "DH", meaning: "Designated hitter")
            GlossaryRow(abbr: "PH", meaning: "Pinch hitter")
            GlossaryRow(abbr: "PR", meaning: "Pinch runner")
        } header: {
            SectionHeading(text: "Positions (letters after a name)")
        }
    }

    private var otherSection: some View {
        Section {
            GlossaryRow(abbr: "Att", meaning: "Attendance")
            GlossaryRow(abbr: "a, b, c", meaning: "Footnote letters marking substitute batters; the note below the table says what each one did")
        } header: {
            SectionHeading(text: "Other")
        }
    }
}

/// One glossary row: the abbreviation in bold, then its plain meaning.
private struct GlossaryRow: View {
    let abbr: String
    let meaning: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(abbr)
                .font(.system(.body, design: .serif).weight(.bold))
                .frame(minWidth: 44, alignment: .leading)
            Text(meaning)
                .font(.system(.body, design: .serif))
        }
    }
}
