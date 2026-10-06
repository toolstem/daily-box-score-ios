import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: StoreManager
    @AppStorage("dailyReminderEnabled") private var reminderEnabled = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The Daily Box Score delivers complete Major League box scores in the classic newspaper agate style, every morning.")
                        .font(.system(.body, design: .serif))
                    LabeledContent("Data", value: "Official MLB Stats API")
                        .font(.system(.body, design: .serif))
                    LabeledContent("Version", value: "1.0")
                        .font(.system(.body, design: .serif))
                } header: {
                    SectionHeading(text: "About")
                }

                Section {
                    Toggle("Morning reminder", isOn: $reminderEnabled)
                        .font(.system(.body, design: .serif))
                        .onChange(of: reminderEnabled) { _, newValue in
                            NotificationManager.shared.setDailyReminder(enabled: newValue)
                        }
                    Text("A notification at 7:30 AM when the new edition is ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SectionHeading(text: "Notifications")
                }

                if store.paywallEnabled {
                    Section {
                        if store.isUnlocked {
                            Label("Season Pass active", systemImage: "checkmark.seal")
                                .font(.system(.body, design: .serif))
                        } else {
                            ForEach(store.products) { product in
                                Button("Buy \(product.displayName) — \(product.displayPrice)") {
                                    Task { await store.purchase(product) }
                                }
                                .font(.system(.body, design: .serif))
                            }
                            Button("Restore Purchases") {
                                Task { await store.updatePurchasedProducts() }
                            }
                            .font(.system(.body, design: .serif))
                        }
                    } header: {
                        SectionHeading(text: "Season Pass")
                    }
                }

                Section {
                    Link(destination: URL(string: "https://www.toolstem.com/daily-box-score/")!) {
                        Text("Visit the website")
                            .font(.system(.body, design: .serif))
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            await store.loadProducts()
        }
    }
}
