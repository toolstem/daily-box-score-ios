import Foundation

/// The user's favorite teams, persisted on-device.
/// Favorite teams' box scores are shown first in every edition.
@MainActor
class FavoritesStore: ObservableObject {
    private static let storageKey = "favoriteTeams"

    @Published var favoriteAbbrevs: [String] {
        didSet {
            UserDefaults.standard.set(favoriteAbbrevs, forKey: Self.storageKey)
        }
    }

    init() {
        self.favoriteAbbrevs = UserDefaults.standard.stringArray(
            forKey: Self.storageKey
        ) ?? []
    }

    var favoriteTeams: [MLBTeam] {
        favoriteAbbrevs.compactMap(MLBTeam.team(abbrev:))
    }

    func isFavorite(_ team: MLBTeam) -> Bool {
        favoriteAbbrevs.contains(team.abbrev)
    }

    func toggle(_ team: MLBTeam) {
        if isFavorite(team) {
            favoriteAbbrevs.removeAll { $0 == team.abbrev }
        } else {
            favoriteAbbrevs.append(team.abbrev)
        }
    }
}
