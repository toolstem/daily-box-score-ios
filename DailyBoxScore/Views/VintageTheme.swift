import SwiftUI

/// Shared vintage newspaper styling: serif type, thin rules, no decoration.
enum Vintage {
    /// Classic section heading, e.g. "YOUR TEAMS".
    static func sectionFont() -> Font {
        .system(.caption, design: .serif).weight(.semibold)
    }
}

/// A thin newspaper rule used as a divider.
struct ThinRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.45))
            .frame(height: 1)
    }
}

/// Uppercase, letter-spaced section heading in the agate style.
struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Vintage.sectionFont())
            .tracking(2.5)
            .foregroundStyle(.secondary)
    }
}

/// The nameplate shown at the top of the edition list.
struct NameplateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("The Daily Box Score")
                .font(.system(.title, design: .serif).weight(.bold))
                .multilineTextAlignment(.center)
            ThinRule()
            ThinRule()
            Text("Complete MLB Box Scores")
                .font(.system(.subheadline, design: .serif).italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
}
