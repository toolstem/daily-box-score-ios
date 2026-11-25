import Foundation
import Security

/// Talks to the paper delivery server, only after the user turns
/// delivery on. Sends: the app name, Apple's transaction ID for the
/// pass, and the email or phone number the user typed. Nothing else.
///
/// The server hands back a "manage token": a random secret kept in
/// this device's Keychain. It lets the app show status and delete the
/// address. It never leaves the device except to our server.
enum DeliveryClient {
    static let baseURL = URL(string: "https://delivery.toolstem.com")!
    static let app = "baseball"

    /// Exact words shown next to the text checkbox. Version "v1" on
    /// the server stores the same words as proof of consent.
    static let smsConsentVersion = "v1"
    static let smsConsentText =
        "Text me a link to the daily paper. Up to 1 text per game day. " +
        "Msg and data rates may apply. Reply STOP to cancel, HELP for help. " +
        "Consent is not a condition of purchase."

    struct Status: Decodable {
        let email: String?
        let emailPending: String?
        let phone: String?
        let smsConfirmed: Bool
        let active: Bool
    }

    enum Failure: Error {
        case message(String)
    }

    private struct SubscribeReply: Decodable {
        let ok: Bool?
        let manageToken: String?
        let emailPending: Bool?
        let smsPending: Bool?
        let error: String?
    }

    // MARK: - Calls

    static func subscribe(
        transactionID: UInt64,
        email: String?,
        phone: String?,
        smsConsent: Bool
    ) async throws -> (emailPending: Bool, smsPending: Bool) {
        var body: [String: Any] = ["app": app, "transactionId": String(transactionID)]
        if let email, !email.isEmpty { body["email"] = email }
        if let phone, !phone.isEmpty {
            body["phone"] = phone
            body["smsConsent"] = smsConsent
            body["smsConsentVersion"] = smsConsentVersion
        }
        let (data, http) = try await post("/v1/subscribe", body)
        let reply = try? JSONDecoder().decode(SubscribeReply.self, from: data)
        if let token = reply?.manageToken { Keychain.set(token) }
        guard http.statusCode == 200, reply?.ok == true else {
            throw Failure.message(explain(reply?.error))
        }
        return (reply?.emailPending ?? false, reply?.smsPending ?? false)
    }

    static func status() async -> Status? {
        guard let token = Keychain.get() else { return nil }
        guard let result = try? await post("/v1/status", ["app": app, "manageToken": token]),
              result.1.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Status.self, from: result.0)
    }

    /// Stop delivery and delete the address on the server.
    static func deleteEverything() async throws {
        guard let token = Keychain.get() else { return }
        let (_, http) = try await post("/v1/delete", ["app": app, "manageToken": token])
        guard http.statusCode == 200 || http.statusCode == 404 else {
            throw Failure.message("Couldn't reach the server. Try again.")
        }
        Keychain.remove()
    }

    private static func post(_ path: String, _ body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request, delegate: OwnDeliveryHostOnly.shared)
        guard let http = response as? HTTPURLResponse, data.count <= 16_384 else {
            throw Failure.message("Couldn't reach the server. Try again.")
        }
        return (data, http)
    }

    private static func explain(_ code: String?) -> String {
        switch code {
        case "bad_email": return "That email address doesn't look right."
        case "bad_phone": return "Enter a 10-digit US mobile number."
        case "sms_consent_required": return "Check the box to agree to texts."
        case "no_active_pass": return "Email delivery comes with an active Archive Pass."
        case "email_blocked": return "We can't send to that address. Try another one."
        case "phone_opted_out": return "That number replied STOP. Text START to us first."
        case "email_off", "sms_off": return "Delivery is paused right now."
        case "slow_down": return "Too many tries. Wait a bit and try again."
        default: return "Couldn't reach the server. Try again."
        }
    }

    // MARK: - Keychain (this device only, not synced)

    enum Keychain {
        private static let service = "com.omcollective.dailyboxscore.delivery"
        private static let account = "manageToken"

        private static var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: account]
        }

        static func set(_ token: String) {
            SecItemDelete(query as CFDictionary)
            var add = query
            add[kSecValueData as String] = Data(token.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }

        static func get() -> String? {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func remove() {
            SecItemDelete(query as CFDictionary)
        }
    }
}

/// Refuses redirects away from the delivery host, so a POST with an
/// email address can never be bounced somewhere else.
final class OwnDeliveryHostOnly: NSObject, URLSessionTaskDelegate {
    static let shared = OwnDeliveryHostOnly()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
