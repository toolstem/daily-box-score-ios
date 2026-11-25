import Combine
import Foundation
import StoreKit

/// The Archive Pass and the supporter tips, using StoreKit 2.
/// No accounts, no server: Apple holds the purchase, and the app reads
/// it back from StoreKit on each launch (works offline from StoreKit's
/// own on-device copy). Nothing about the user is stored or sent by us.
///
/// What is free and what needs the pass is decided in `access(...)`,
/// together with the remote switches in RemoteSwitches.
@MainActor
final class StoreManager: ObservableObject {

    // MARK: - Product plan (swap BEFORE creating products in App Store Connect)

    enum PassPlan {
        /// Auto-renewing yearly subscription (recommended).
        case yearlySubscription
        /// One-time purchase that never expires (comparison option).
        case lifetime
    }

    /// Which pass the app sells. Both product IDs always unlock, so a
    /// later switch never strands someone who bought the other kind.
    static let plan: PassPlan = .yearlySubscription

    static let yearlyID = "com.omcollective.dailyboxscore.archivepass.yearly"
    static let lifetimeID = "com.omcollective.dailyboxscore.archivepass.lifetime"
    static let passIDs: Set<String> = [yearlyID, lifetimeID]
    static var sellingID: String {
        plan == .yearlySubscription ? yearlyID : lifetimeID
    }

    /// Consumable tips. They unlock nothing (Apple allows tip jars as
    /// consumables as long as they buy no features).
    static let tipIDs = [
        "com.omcollective.dailyboxscore.tip.small",
        "com.omcollective.dailyboxscore.tip.medium",
        "com.omcollective.dailyboxscore.tip.large",
    ]

    /// Papers from 2001 on come from the MLB Stats API; 1901-2000 come
    /// from Retrosheet. The MLB switch applies from this year on.
    static let firstMLBYear = 2001

    // MARK: - State

    @Published private(set) var passProduct: Product?
    @Published private(set) var tipProducts: [Product] = []
    @Published private(set) var ownsPass = false
    /// Expiry of the current yearly pass; nil for lifetime or no pass.
    @Published private(set) var passExpiration: Date?
    /// Apple's original transaction ID for the pass. Sent only to our
    /// delivery server, and only when the user turns delivery on, so
    /// the server can ask Apple whether the pass is active.
    @Published private(set) var passTransactionID: UInt64?
    @Published private(set) var productsLoaded = false
    @Published private(set) var isBusy = false
    /// A short message for the user after a purchase or restore.
    @Published var message: String?

    let switches: RemoteSwitches
    private var updatesTask: Task<Void, Never>?
    private var switchesWatch: AnyCancellable?

    init(switches: RemoteSwitches) {
        self.switches = switches
        // Views watch the store; re-render them when a switch changes.
        switchesWatch = switches.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Purchases that finish outside the app (renewals, Ask to Buy
        // approvals, refunds) arrive here.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Access rules

    enum Access {
        case allowed
        case needsPass
        case hidden
    }

    enum Feature {
        case onThisDay
        case birthdayPaper
        case shareArchivePaper
    }

    /// Whether a pass feature may be used for a paper from `year`.
    /// `year` nil means "unknown", which is treated as MLB era (the
    /// cautious side of the MLB switch).
    func access(_ feature: Feature, year: Int?) -> Access {
        let isMLB = (year ?? Self.firstMLBYear) >= Self.firstMLBYear
        if switches.passMode == .off { return .hidden }
        if isMLB && switches.mlbFeatures == .off { return .hidden }
        if switches.passMode == .free { return .allowed }
        if isMLB && switches.mlbFeatures == .free { return .allowed }
        return ownsPass ? .allowed : .needsPass
    }

    /// The best access a feature has for any era, for its menu row.
    func entryAccess(_ feature: Feature) -> Access {
        let a = access(feature, year: Self.firstMLBYear - 1)
        let b = access(feature, year: Self.firstMLBYear)
        if a == .allowed || b == .allowed { return .allowed }
        if a == .needsPass || b == .needsPass { return .needsPass }
        return .hidden
    }

    /// Print / Share for a paper. This week's papers are always free
    /// (within `free_share_days` of the newest paper or of today);
    /// older archive papers are a pass feature.
    func shareAccess(paperDate: String?, newestPaperDate: String?) -> Access {
        if let paperDate,
           Self.isRecent(paperDate, newest: newestPaperDate,
                         days: switches.freeShareDays) {
            return .allowed
        }
        // The kill switch never hides sharing; it makes it free
        // (sharing is a plain share sheet and worked before the pass).
        let result = access(.shareArchivePaper, year: paperDate.flatMap(Self.year))
        return result == .hidden ? .allowed : result
    }

    /// Email delivery is offered when the remote flag is on and neither
    /// kill switch is "off" (current baseball comes from MLB data).
    var deliveryOffered: Bool {
        switches.emailDelivery && switches.passMode != .off && switches.mlbFeatures != .off
    }

    /// Texts: same rules, separate flag (off by default).
    var textDeliveryOffered: Bool {
        deliveryOffered && switches.smsDelivery
    }

    /// True when the purchase screen should offer the pass for sale.
    var canSellPass: Bool {
        switches.passMode == .paid && !ownsPass
    }

    // MARK: - StoreKit

    func loadProducts() async {
        do {
            let ids = [Self.sellingID] + Self.tipIDs
            let products = try await Product.products(for: ids)
            passProduct = products.first { $0.id == Self.sellingID }
            tipProducts = Self.tipIDs.compactMap { id in
                products.first { $0.id == id }
            }
        } catch {
            passProduct = nil
            tipProducts = []
        }
        productsLoaded = true
    }

    /// Reads what the user owns from StoreKit. Expired or refunded
    /// passes do not count.
    func refreshEntitlements() async {
        var owns = false
        var lifetime = false
        var expiry: Date?
        var txid: UInt64?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result,
                  Self.passIDs.contains(t.productID),
                  t.revocationDate == nil else { continue }
            // No expiry check here: currentEntitlements already leaves
            // out expired passes and keeps those in Apple's billing
            // grace period, whose date can be in the past.
            if let e = t.expirationDate {
                expiry = max(expiry ?? e, e)
            } else {
                lifetime = true
            }
            owns = true
            txid = t.originalID
        }
        ownsPass = owns
        passTransactionID = txid
        passExpiration = (owns && !lifetime) ? expiry : nil
    }

    func purchase(_ product: Product) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "Apple could not confirm that purchase. You were not given access. Please try again."
                    return
                }
                await transaction.finish()
                if Self.tipIDs.contains(transaction.productID) {
                    message = "Thank you for supporting the paper."
                } else {
                    await refreshEntitlements()
                    message = "Your Archive Pass is ready."
                }
            case .pending:
                message = "Your purchase is waiting for approval. It will unlock when it goes through."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through. Please try again."
        }
    }

    /// Restore Purchases (Apple requires a visible button). Asks the App
    /// Store to re-sync, which can prompt the user to sign in.
    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch {
            // Fall through: currentEntitlements still has local data.
        }
        await refreshEntitlements()
        message = ownsPass
            ? "Your Archive Pass is restored."
            : "No Archive Pass was found for this Apple Account."
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    // MARK: - Dates

    nonisolated static func year(_ date: String) -> Int? {
        Int(date.prefix(4))
    }

    nonisolated private static func parseDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f.date(from: text)
    }

    /// True when `date` is within `days` days of the newest paper, or of
    /// today (so the newest paper stays free in the off-season too).
    nonisolated static func isRecent(_ date: String, newest: String?, days: Int) -> Bool {
        guard let d = parseDate(date) else { return false }
        let window = TimeInterval(days) * 86_400
        if let newest, let n = parseDate(newest), d >= n.addingTimeInterval(-window) {
            return true
        }
        return d >= Date().addingTimeInterval(-window - 86_400)
    }

    /// The YYYY-MM-DD date in a paper's filename, e.g.
    /// "boxscores_1927-09-30.pdf" -> "1927-09-30".
    nonisolated static func paperDate(fromFilename name: String) -> String? {
        guard let range = name.range(
            of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression
        ) else { return nil }
        let date = String(name[range])
        return parseDate(date) == nil ? nil : date
    }
}
