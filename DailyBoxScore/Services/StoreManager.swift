import Foundation
import StoreKit

/// In-app purchase scaffolding, using StoreKit 2.
///
/// HOW THE ROLLOUT WORKS
/// ---------------------
/// While `paywallEnabled` is false (the current setting), everything in the
/// app is unlocked and no store UI is shown — the app is completely free.
/// The day you want to start charging, flip `paywallEnabled` to true and
/// create the matching product in App Store Connect (see README.md).
/// From then on, `isUnlocked` reflects whether the user owns the season pass.
///
/// The product is a one-time, non-consumable "season pass" per season
/// (e.g. a new product ID each year: ...season2027, ...season2028).
@MainActor
class StoreManager: ObservableObject {
    // MARK: - Launch configuration

    /// Set to true when you're ready to start charging.
    let paywallEnabled = false

    /// The App Store Connect product ID for the current season's pass.
    static let seasonPassProductID = "com.toolstem.dailyboxscore.season2027"

    // MARK: - State

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []

    /// True while the app is free, or when the user owns the season pass.
    var isUnlocked: Bool {
        if !paywallEnabled { return true }
        return purchasedProductIDs.contains(Self.seasonPassProductID)
    }

    // MARK: - StoreKit

    func loadProducts() async {
        guard paywallEnabled else { return }
        do {
            products = try await Product.products(for: [Self.seasonPassProductID])
        } catch {
            products = []
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return }
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // Purchase failed; the store UI simply stays as-is.
        }
    }

    /// Picks up purchases the user already owns (including restores).
    func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                purchasedProductIDs.insert(transaction.productID)
            }
        }
    }
}
