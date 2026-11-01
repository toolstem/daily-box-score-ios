import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: StoreManager
    @EnvironmentObject var feed: FeedService
    @AppStorage("dailyReminderEnabled") private var reminderEnabled = true
    @AppStorage("dailyReminderHour") private var reminderHour = 7
    @AppStorage("dailyReminderMinute") private var reminderMinute = 30

    /// The chosen reminder time as a Date, for the time picker.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents(
                    [.year, .month, .day], from: Date()
                )
                components.hour = reminderHour
                components.minute = reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents(
                    [.hour, .minute], from: newValue
                )
                reminderHour = parts.hour ?? 7
                reminderMinute = parts.minute ?? 30
            }
        )
    }

    /// The chosen time in short form, e.g. "7:30 AM".
    private var reminderTimeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: reminderTime.wrappedValue)
    }

    /// Re-checks the MLB schedule for the coming week and puts reminders
    /// on the calendar for the mornings after game days, at the chosen
    /// time. Mornings with no game the day before get no reminder.
    private func refreshReminder() {
        Task {
            await NotificationManager.shared.refreshReminders(using: feed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The Daily Box Score delivers complete Major League box scores in the classic newspaper style, every morning.")
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
                            if newValue {
                                refreshReminder()
                            } else {
                                NotificationManager.shared.cancelDailyReminder()
                            }
                        }
                    if reminderEnabled {
                        DatePicker(
                            "Reminder time",
                            selection: reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .font(.system(.body, design: .serif))
                        .onChange(of: reminderHour) { _, _ in
                            refreshReminder()
                        }
                        .onChange(of: reminderMinute) { _, _ in
                            refreshReminder()
                        }
                    }
                    Text("A notification at \(reminderTimeText) when there's a new edition.")
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
