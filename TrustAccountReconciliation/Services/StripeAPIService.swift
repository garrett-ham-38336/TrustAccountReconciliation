import Foundation
import CoreData

/// Service for integrating with Stripe API to fetch balance data
class StripeAPIService {
    static let shared = StripeAPIService()

    private let baseURL = "https://api.stripe.com/v1"
    private let session: URLSession

    // Keychain key for secret key
    private let keychainSecretKey = "com.trustaccounting.stripe.secretKey"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Credential Management

    /// Stores Stripe API secret key securely in Keychain
    func saveCredentials(secretKey: String) throws {
        try KeychainService.shared.save(key: keychainSecretKey, value: secretKey)
    }

    /// Retrieves stored secret key
    func getCredentials() -> String? {
        try? KeychainService.shared.retrieve(key: keychainSecretKey)
    }

    /// Checks if credentials are configured
    var hasCredentials: Bool {
        guard let key = getCredentials() else { return false }
        return !key.isEmpty
    }

    /// Clears stored credentials
    func clearCredentials() throws {
        try KeychainService.shared.delete(key: keychainSecretKey)
    }

    /// Tests authentication by fetching balance
    func authenticate() async throws {
        _ = try await fetchBalance()
    }

    // MARK: - API Methods

    /// Fetches the current Stripe balance
    func fetchBalance() async throws -> StripeBalance {
        guard let secretKey = getCredentials(), !secretKey.isEmpty else {
            throw StripeError.notConfigured
        }

        let url = URL(string: "\(baseURL)/balance")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logDebug("Fetching balance from Stripe...")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw StripeError.invalidCredentials
        case 403:
            throw StripeError.insufficientPermissions
        default:
            let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
            logDebug("Stripe API Error: HTTP \(httpResponse.statusCode)\nResponse: \(rawResponse)")
            throw StripeError.requestFailed(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let balance = try decoder.decode(StripeBalance.self, from: data)
            logDebug("Balance fetched successfully - Available: \(balance.availableTotal), Pending: \(balance.pendingTotal)")
            return balance
        } catch {
            let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
            logDebug("Failed to decode balance response: \(error)\nRaw: \(rawResponse)")
            throw StripeError.parseError(error.localizedDescription)
        }
    }

    /// Fetches recent payouts (optional, for reference)
    func fetchPayouts(limit: Int = 10) async throws -> [StripePayout] {
        guard let secretKey = getCredentials(), !secretKey.isEmpty else {
            throw StripeError.notConfigured
        }

        var components = URLComponents(string: "\(baseURL)/payouts")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logDebug("Fetching payouts from Stripe...")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw StripeError.invalidCredentials
        case 403:
            throw StripeError.insufficientPermissions
        default:
            throw StripeError.requestFailed(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        struct PayoutsResponse: Decodable {
            let data: [StripePayout]
        }

        let payoutsResponse = try decoder.decode(PayoutsResponse.self, from: data)
        logDebug("Fetched \(payoutsResponse.data.count) payouts")
        return payoutsResponse.data
    }

    // MARK: - Sync Method

    /// Syncs balance from Stripe and saves to Core Data
    @MainActor
    func syncBalance(context: NSManagedObjectContext) async throws -> StripeSnapshot {
        let balance = try await fetchBalance()

        // Convert amounts from cents to dollars
        let availableDecimal = Decimal(balance.availableTotal) / 100
        let pendingDecimal = Decimal(balance.pendingTotal) / 100
        let reserveDecimal = Decimal(balance.connectReservedTotal) / 100

        // Create snapshot
        let snapshot = StripeSnapshot.create(
            in: context,
            availableBalance: availableDecimal,
            pendingBalance: pendingDecimal,
            reserveBalance: reserveDecimal
        )

        try context.save()

        logDebug("Stripe balance synced - Available: \(availableDecimal), Pending: \(pendingDecimal), Reserve: \(reserveDecimal)")

        return snapshot
    }

    // MARK: - Debug Logging

    private func logDebug(_ message: String) {
        print("STRIPE DEBUG: \(message)")
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TrustAccountReconciliation/debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] STRIPE: \(message)\n"
        if let existing = try? String(contentsOf: logURL, encoding: .utf8) {
            try? (existing + logMessage).write(to: logURL, atomically: true, encoding: .utf8)
        } else {
            try? logMessage.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Response Models

struct StripeBalance: Decodable {
    let available: [StripeBalanceAmount]
    let pending: [StripeBalanceAmount]
    let connectReserved: [StripeBalanceAmount]?
    let livemode: Bool?
    let object: String?

    /// Total available balance in cents (USD only, or first currency)
    var availableTotal: Int {
        available.first(where: { $0.currency == "usd" })?.amount ?? available.first?.amount ?? 0
    }

    /// Total pending balance in cents (USD only, or first currency)
    var pendingTotal: Int {
        pending.first(where: { $0.currency == "usd" })?.amount ?? pending.first?.amount ?? 0
    }

    /// Total connect reserved balance in cents (USD only, or first currency)
    var connectReservedTotal: Int {
        connectReserved?.first(where: { $0.currency == "usd" })?.amount ?? connectReserved?.first?.amount ?? 0
    }

    /// Total holdback (pending + reserve) in cents
    var holdbackTotal: Int {
        pendingTotal + connectReservedTotal
    }
}

struct StripeBalanceAmount: Decodable {
    let amount: Int      // In cents
    let currency: String
    let sourceTypes: SourceTypes?

    struct SourceTypes: Decodable {
        let card: Int?
        let bankAccount: Int?
    }
}

struct StripePayout: Decodable {
    let id: String
    let amount: Int          // In cents
    let currency: String
    let status: String       // paid, pending, in_transit, canceled, failed
    let arrivalDate: Int     // Unix timestamp
    let created: Int         // Unix timestamp
    let description: String?
    let method: String?      // standard, instant

    var arrivalDateFormatted: Date {
        Date(timeIntervalSince1970: TimeInterval(arrivalDate))
    }

    var createdDateFormatted: Date {
        Date(timeIntervalSince1970: TimeInterval(created))
    }

    var amountDecimal: Decimal {
        Decimal(amount) / 100
    }
}

// MARK: - Errors

enum StripeError: LocalizedError {
    case notConfigured
    case invalidCredentials
    case insufficientPermissions
    case requestFailed(Int)
    case invalidResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Stripe API key not configured. Please enter your secret key in Settings."
        case .invalidCredentials:
            return "Invalid API key. Please check your Stripe secret key."
        case .insufficientPermissions:
            return "API key lacks required permissions. Ensure it has balance read scope."
        case .requestFailed(let code):
            return "Stripe API request failed (HTTP \(code))."
        case .invalidResponse:
            return "Invalid response from Stripe API."
        case .parseError(let message):
            return "Failed to parse Stripe response: \(message)"
        }
    }
}
