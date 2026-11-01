import SwiftUI

/// Native single-game box score: linescore, batting and pitching tables
/// with totals, game notes, and decisions, matching the printed paper.
/// Replaces the "every game opens the same PDF" experience with a proper
/// mobile reading view. The full edition PDF stays one tap away.
struct GameDetailView: View {
    let game: BoxScoreGame
    let dateLabel: String
    let pdfURL: URL?
    let pdfPage: Int?

    @State private var showingPDF = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ThinRule()
                linescoreSection
                ThinRule()
                battingSection(team: game.away, title: "\(game.away.name ?? "Away") Batting")
                ThinRule()
                battingSection(team: game.home, title: "\(game.home.name ?? "Home") Batting")
                ThinRule()
                pitchingSection(team: game.away, title: "\(game.away.name ?? "Away") Pitching")
                ThinRule()
                pitchingSection(team: game.home, title: "\(game.home.name ?? "Home") Pitching")
                if game.winner != nil || game.loser != nil || game.save != nil {
                    ThinRule()
                    decisionsSection
                }
                if hasGameNotes {
                    ThinRule()
                    gameNotesSection
                }
                if pdfURL != nil {
                    ThinRule()
                    Button("View Full Edition (PDF)") { showingPDF = true }
                        .font(.system(.body, design: .serif))
                }
            }
            .padding()
        }
        .navigationTitle(game.headline)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPDF) {
            if let pdfURL {
                NavigationStack {
                    PDFReaderScreen(url: pdfURL, page: pdfPage ?? 1)
                        .navigationTitle("Full Edition")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.headline)
                .font(.system(.title2, design: .serif).weight(.bold))
            if let status = game.seriesStatus, !status.isEmpty {
                Text(status)
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(.secondary)
            } else if let series = game.series, !series.isEmpty, series != "Regular Season" {
                Text(series)
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(.secondary)
            }
            Text(dateLabel)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
            if !venueLine.isEmpty {
                Text(venueLine)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var venueLine: String {
        var details: [String] = []
        if let venue = game.venue?.trimmingCharacters(in: .init(charactersIn: ". ")),
           !venue.isEmpty {
            details.append(venue)
        }
        if let att = game.att?.trimmingCharacters(in: .init(charactersIn: ". ")), !att.isEmpty {
            details.append("Att: \(att)")
        }
        return details.joined(separator: " · ")
    }

    // MARK: - Linescore

    private var linescoreSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(text: "Linescore")
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(game.linescore.innings, id: \.self) { i in
                            Text("\(i)").font(.system(.caption, design: .serif).weight(.bold))
                        }
                        Text("R").font(.system(.caption, design: .serif).weight(.bold))
                        Text("H").font(.system(.caption, design: .serif).weight(.bold))
                        Text("E").font(.system(.caption, design: .serif).weight(.bold))
                    }
                    linescoreRow(
                        abbrev: game.away.abbrev ?? "A",
                        line: game.linescore.away,
                        r: game.linescore.aR, h: game.linescore.aH, e: game.linescore.aE
                    )
                    linescoreRow(
                        abbrev: game.home.abbrev ?? "H",
                        line: game.linescore.home,
                        r: game.linescore.hR, h: game.linescore.hH, e: game.linescore.hE
                    )
                }
                .font(.system(.body, design: .serif))
            }
        }
    }

    private func linescoreRow(abbrev: String, line: [Int?], r: Int?, h: Int?, e: Int?) -> some View {
        GridRow {
            Text(abbrev)
                .gridColumnAlignment(.leading)
                .font(.system(.body, design: .serif).weight(.semibold))
            ForEach(0..<line.count, id: \.self) { i in
                Text(line[i].map(String.init) ?? "–")
            }
            Text(r.map(String.init) ?? "–").fontWeight(.bold)
            Text(h.map(String.init) ?? "–")
            Text(e.map(String.init) ?? "–")
        }
    }

    // MARK: - Batting

    private var batColumns: [String] { ["AB", "R", "H", "RBI", "BB", "SO", "2B", "3B", "HR"] }

    private func battingSection(team: BoxScoreTeam, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(text: title)
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Batter").gridColumnAlignment(.leading)
                            .font(.system(.caption, design: .serif).weight(.bold))
                        ForEach(batColumns, id: \.self) { c in
                            Text(c).font(.system(.caption, design: .serif).weight(.bold))
                        }
                    }
                    ForEach(team.batting) { b in
                        GridRow {
                            HStack(spacing: 2) {
                                if let letter = b.subLetter, !letter.isEmpty {
                                    Text("\(letter)—")
                                        .font(.system(.callout, design: .serif).italic())
                                        .foregroundStyle(.secondary)
                                }
                                Text(b.name ?? "–")
                                if let pos = b.pos, !pos.isEmpty {
                                    Text(pos)
                                        .font(.system(.caption, design: .serif))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .gridColumnAlignment(.leading)
                            Text(num(b.ab)); Text(num(b.r)); Text(num(b.h))
                            Text(num(b.rbi)); Text(num(b.bb)); Text(num(b.so))
                            Text(num(b.doubles)); Text(num(b.triples)); Text(num(b.hr))
                        }
                    }
                    if let t = team.battingTotals, hasBattingTotals(t) {
                        GridRow {
                            Text("Totals")
                                .gridColumnAlignment(.leading)
                                .font(.system(.callout, design: .serif).weight(.bold))
                            Text(num(t.ab)).fontWeight(.bold)
                            Text(num(t.r)).fontWeight(.bold)
                            Text(num(t.h)).fontWeight(.bold)
                            Text(num(t.rbi)).fontWeight(.bold)
                            Text(num(t.bb)).fontWeight(.bold)
                            Text(num(t.so)).fontWeight(.bold)
                            Text(num(t.doubles)).fontWeight(.bold)
                            Text(num(t.triples)).fontWeight(.bold)
                            Text(num(t.hr)).fontWeight(.bold)
                        }
                    }
                }
                .font(.system(.callout, design: .serif))
            }
            if let footnotes = team.footnotes, !footnotes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(footnotes, id: \.self) { note in
                        if note.count >= 2 {
                            Text("\(note[0])—\(note[1])")
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            tableNotes(team.battingNotes)
            tableNotes(team.fieldingNotes)
        }
    }

    private func hasBattingTotals(_ t: BoxScoreTotals) -> Bool {
        t.ab != nil || t.r != nil || t.h != nil || t.rbi != nil || t.bb != nil || t.so != nil
    }

    @ViewBuilder
    private func tableNotes(_ notes: [[String]]?) -> some View {
        if let notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(notes, id: \.self) { note in
                    if note.count >= 2 {
                        (Text("\(note[0])—").fontWeight(.bold) + Text(note[1]))
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Pitching

    private var pitColumns: [String] { ["IP", "H", "R", "ER", "BB", "SO", "HR", "P-S"] }

    private func pitchingSection(team: BoxScoreTeam, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(text: title)
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Pitcher").gridColumnAlignment(.leading)
                            .font(.system(.caption, design: .serif).weight(.bold))
                        ForEach(pitColumns, id: \.self) { c in
                            Text(c).font(.system(.caption, design: .serif).weight(.bold))
                        }
                    }
                    ForEach(team.pitching) { p in
                        GridRow {
                            HStack(spacing: 2) {
                                Text(p.name ?? "–")
                                if let d = p.decision, !d.isEmpty {
                                    Text("(\(d))")
                                        .font(.system(.caption, design: .serif))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .gridColumnAlignment(.leading)
                            Text(p.ip ?? "–"); Text(num(p.h)); Text(num(p.r))
                            Text(num(p.er)); Text(num(p.bb)); Text(num(p.so)); Text(num(p.hr))
                            Text(p.ps ?? "–")
                        }
                    }
                    if let t = team.pitchingTotals, hasPitchingTotals(t) {
                        GridRow {
                            Text("Totals")
                                .gridColumnAlignment(.leading)
                                .font(.system(.callout, design: .serif).weight(.bold))
                            Text(t.ip ?? "–").fontWeight(.bold)
                            Text(num(t.h)).fontWeight(.bold)
                            Text(num(t.r)).fontWeight(.bold)
                            Text(num(t.er)).fontWeight(.bold)
                            Text(num(t.bb)).fontWeight(.bold)
                            Text(num(t.so)).fontWeight(.bold)
                            Text(num(t.hr)).fontWeight(.bold)
                            Text("–")
                        }
                    }
                }
                .font(.system(.callout, design: .serif))
            }
        }
    }

    private func hasPitchingTotals(_ t: BoxScoreTotals) -> Bool {
        t.ip != nil || t.h != nil || t.r != nil || t.er != nil
            || t.bb != nil || t.so != nil || t.hr != nil
    }

    // MARK: - Decisions

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading(text: "Decisions")
            if let w = game.winner {
                Text("W: \(w)\(recordSuffix(game.winnerRecord))")
                    .font(.system(.callout, design: .serif))
            }
            if let l = game.loser {
                Text("L: \(l)\(recordSuffix(game.loserRecord))")
                    .font(.system(.callout, design: .serif))
            }
            if let s = game.save {
                Text("SV: \(s)\(saveSuffix(game.saveNumber))")
                    .font(.system(.callout, design: .serif))
            }
        }
    }

    private func recordSuffix(_ record: String?) -> String {
        guard let record, !record.isEmpty else { return "" }
        return " (\(record))"
    }

    private func saveSuffix(_ saves: Int?) -> String {
        guard let saves else { return "" }
        return " (\(saves))"
    }

    // MARK: - Game Notes

    private var hasGameNotes: Bool {
        !gameNoteLines.isEmpty
    }

    /// Labelled note lines, in the paper's order. Only lines with
    /// content are included; a missing line is simply not shown.
    private var gameNoteLines: [(String, String)] {
        var lines: [(String, String)] = []
        if let lob = lobLine {
            lines.append(("LOB", lob))
        }
        if let v = game.notes?.hbp, !v.isEmpty {
            lines.append(("HBP", v))
        }
        if let v = game.notes?.battersFaced, !v.isEmpty {
            lines.append(("Batters faced", v))
        }
        if let v = game.notes?.inheritedRunners, !v.isEmpty {
            lines.append(("Inherited runners-scored", v))
        }
        if let v = game.notes?.umpires, !v.isEmpty {
            lines.append(("Umpires", v))
        }
        var weatherBits: [String] = []
        if let v = game.notes?.weather, !v.isEmpty {
            weatherBits.append(v)
        }
        if let v = game.notes?.wind, !v.isEmpty {
            weatherBits.append("Wind: \(v)")
        }
        if !weatherBits.isEmpty {
            lines.append(("Weather", weatherBits.joined(separator: ". ")))
        }
        if let v = game.gameTime, !v.isEmpty {
            lines.append(("Time of game", v))
        }
        if let v = game.firstPitch, !v.isEmpty {
            lines.append(("First pitch", v))
        }
        return lines
    }

    private var lobLine: String? {
        let a = game.linescore.aLob
        let h = game.linescore.hLob
        guard a != nil || h != nil else { return nil }
        let aAbbrev = game.away.abbrev ?? "A"
        let hAbbrev = game.home.abbrev ?? "H"
        return "\(aAbbrev) \(a.map(String.init) ?? "–"), \(hAbbrev) \(h.map(String.init) ?? "–")"
    }

    private var gameNotesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading(text: "Game Notes")
            ForEach(gameNoteLines, id: \.0) { line in
                (Text("\(line.0)—").fontWeight(.bold) + Text(line.1))
                    .font(.system(.callout, design: .serif))
            }
        }
    }

    private func num(_ v: Int?) -> String { v.map(String.init) ?? "–" }
}
