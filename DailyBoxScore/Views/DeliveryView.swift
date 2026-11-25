import SwiftUI

/// Email delivery (and, when switched on, text links) for pass holders.
/// Nothing is sent to our server until the user taps Save.
struct DeliveryView: View {
    @EnvironmentObject var store: StoreManager

    @State private var email = ""
    @State private var phone = ""
    @State private var smsConsent = false
    @State private var status: DeliveryClient.Status?
    @State private var busy = false
    @State private var note: String?
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let status {
                Section("Now") {
                    if let e = status.email {
                        LabeledContent("Email", value: e)
                    }
                    if let p = status.emailPending {
                        Text("Check \(p) and tap the confirm link.")
                    }
                    if let ph = status.phone {
                        LabeledContent("Texts", value: status.smsConfirmed ? ph : "\(ph) (waiting)")
                    }
                }
            }

            Section {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Email")
            } footer: {
                Text("We send a confirm link first. Each email has a one-tap unsubscribe link.")
            }

            if store.textDeliveryOffered {
                Section {
                    TextField("Mobile number (US)", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Toggle(isOn: $smsConsent) {
                        Text(DeliveryClient.smsConsentText)
                            .font(.footnote)
                    }
                } header: {
                    Text("Text a link (optional)")
                }
            }

            Section {
                Button(busy ? "Saving..." : "Save") {
                    Task { await save() }
                }
                .disabled(busy || !canSave)
            }

            if let note {
                Section { Text(note) }
            }

            if status != nil {
                Section {
                    Button("Stop delivery and delete my address", role: .destructive) {
                        confirmDelete = true
                    }
                } footer: {
                    Text("Removes your email and phone number from our server right away.")
                }
            }
        }
        .navigationTitle("Delivery")
        .task { status = await DeliveryClient.status() }
        .confirmationDialog("Delete your delivery details?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
    }

    private var canSave: Bool {
        let hasEmail = !email.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPhone = !phone.trimmingCharacters(in: .whitespaces).isEmpty
        if hasPhone && !smsConsent { return false }
        return (hasEmail || hasPhone) && store.passTransactionID != nil
    }

    private func save() async {
        guard let txid = store.passTransactionID else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await DeliveryClient.subscribe(
                transactionID: txid,
                email: email.trimmingCharacters(in: .whitespaces),
                phone: store.textDeliveryOffered ? phone : nil,
                smsConsent: smsConsent
            )
            note = result.emailPending
                ? "Check your inbox and tap the confirm link."
                : "Saved."
            status = await DeliveryClient.status()
        } catch DeliveryClient.Failure.message(let text) {
            note = text
        } catch {
            note = "Couldn't reach the server. Try again."
        }
    }

    private func delete() async {
        do {
            try await DeliveryClient.deleteEverything()
            status = nil
            note = "Deleted. Nothing more will be sent."
        } catch {
            note = "Couldn't reach the server. Try again."
        }
    }
}
