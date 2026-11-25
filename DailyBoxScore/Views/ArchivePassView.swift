import StoreKit
import SwiftUI

/// The Archive Pass screen: what it includes, the price, Apple's
/// required subscription terms, Restore Purchases, and the tip jar.
struct ArchivePassView: View {
    @EnvironmentObject var store: StoreManager
    @State private var showingManage = false

    private static let termsURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
    private static let privacyURL = URL(
        string: "https://www.toolstem.com/daily-box-score/privacy.html"
    )!

    private var isSubscription: Bool {
        StoreManager.plan == .yearlySubscription
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The Archive Pass")
                        .font(.system(.title2, design: .serif).weight(.bold))
                    Text("The daily paper and every box score stay free. The pass adds the extras that make the archive fun to explore.")
                        .font(.system(.body, design: .serif))
                }
                .padding(.vertical, 4)
                benefit("On This Day", "Every paper from today's date, back to 1901.")
                benefit("Birthday Paper", "The box scores from the day you were born, or any day you pick.")
                benefit("Print and Share", "Print, save or send any paper from the archive. This week's papers are always free to print.")
                benefit("New archive features", "Everything we add to the archive is included.")
            }

            statusSection

            if store.canSellPass {
                Section {
                    if let product = store.passProduct {
                        Button {
                            Task { await store.purchase(product) }
                        } label: {
                            HStack {
                                Spacer()
                                if store.isBusy {
                                    ProgressView()
                                } else {
                                    Text(buyLabel(product))
                                        .font(.system(.headline, design: .serif).weight(.bold))
                                }
                                Spacer()
                            }
                        }
                        .disabled(store.isBusy)
                        if isSubscription {
                            Text(subscriptionTerms(product))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if store.productsLoaded {
                        Text("The App Store isn't available right now. Please try again later.")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }

            Section {
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .font(.system(.body, design: .serif))
                .disabled(store.isBusy)
                Link("Terms of Use", destination: Self.termsURL)
                    .font(.system(.body, design: .serif))
                Link("Privacy Policy", destination: Self.privacyURL)
                    .font(.system(.body, design: .serif))
            }

            if store.switches.tipsEnabled && !store.tipProducts.isEmpty {
                Section {
                    ForEach(store.tipProducts) { tip in
                        Button {
                            Task { await store.purchase(tip) }
                        } label: {
                            HStack {
                                Text(tip.displayName)
                                    .font(.system(.body, design: .serif))
                                Spacer()
                                Text(tip.displayPrice)
                                    .font(.system(.body, design: .serif))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(store.isBusy)
                    }
                    Text("A tip is a one-time thank you. It doesn't unlock anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SectionHeading(text: "Support the Paper")
                }
            }
        }
        .navigationTitle("Archive Pass")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showingManage)
        .alert("Archive Pass", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.message ?? "")
        }
        .task {
            if !store.productsLoaded {
                await store.loadProducts()
            }
            await store.refreshEntitlements()
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if store.ownsPass {
            Section {
                Label("Your Archive Pass is active", systemImage: "checkmark.seal")
                    .font(.system(.body, design: .serif))
                if let expiry = store.passExpiration {
                    Text("Paid through \(expiry.formatted(date: .long, time: .omitted)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Manage Subscription") { showingManage = true }
                        .font(.system(.body, design: .serif))
                }
            }
        } else if store.switches.passMode == .free {
            Section {
                Text("Archive Pass features are free for everyone right now.")
                    .font(.system(.body, design: .serif))
            }
        }
    }

    private func benefit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.headline, design: .serif))
            Text(detail)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func buyLabel(_ product: Product) -> String {
        isSubscription
            ? "Subscribe for \(product.displayPrice) a year"
            : "Buy for \(product.displayPrice), one time"
    }

    /// Apple's required disclosure for an auto-renewing subscription:
    /// title, length, price, and how renewal and cancelling work.
    private func subscriptionTerms(_ product: Product) -> String {
        "Archive Pass, 1 year, \(product.displayPrice). Payment is charged to your Apple Account when you confirm. The subscription renews each year at the same price unless you turn off auto-renew at least 24 hours before the end of the current year. Manage or cancel it anytime in your Apple Account settings."
    }
}

/// The Archive Pass screen presented modally (from the PDF reader),
/// with its own navigation bar and a Done button. Inside an existing
/// navigation stack, push ArchivePassView directly instead.
struct ArchivePassSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ArchivePassView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// A small "Archive Pass" tag for locked rows.
struct PassTag: View {
    var body: some View {
        Text("ARCHIVE PASS")
            .font(.system(.caption2, design: .serif).weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}
