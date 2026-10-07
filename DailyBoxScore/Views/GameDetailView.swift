import SwiftUI

/// Native single-game box score: linescore, batting and pitching tables.
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
                if game.winner != nil || game.save != nil {
                    ThinRule()
                    decisionsSection
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
            if let series = game.series, !series.isEmpty, series != "Regular Season" {
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
        if let venue = game.venue, !venue.isEmpty { details.append(venue) }
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

    private var batColumns: [String] { ["AB", "R", "H", "RBI", "BB", "SO"] }

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
                        }
                    }
                }
                .font(.system(.callout, design: .serif))
            }
        }
    }

    // MARK: - Pitching

    private var pitColumns: [String] { ["IP", "H", "R", "ER", "BB", "SO", "HR"] }

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
                        }
                    }
                }
                .font(.system(.callout, design: .serif))
            }
        }
    }

    // MARK: - Decisions

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading(text: "Decisions")
            if let w = game.winner { Text("W: \(w)").font(.system(.callout, design: .serif)) }
            if let l = game.loser { Text("L: \(l)").font(.system(.callout, design: .serif)) }
            if let s = game.save { Text("SV: \(s)").font(.system(.callout, design: .serif)) }
        }
    }

    private func num(_ v: Int?) -> String { v.map(String.init) ?? "–" }
}
