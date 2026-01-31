import Foundation
import CoreData

/// Service for integrating with Stripe API to fetch balance data
class StripeAPIService {
    static let shared = StripeAPIService()

    private let baseURL = "https://api.stripe.com/v1"
    private var session: URLSession

    // Keychain key for secret key
    private let keychainSecretKey = "com.trustaccounting.stripe.secretKey"

    /// Whether certificate pinning is enabled
    private(set) var certificatePinningEnabled: Bool = false

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Enables or disables certificate pinning for API requests
    /// - Parameter enabled: Whether to enable certificate pinning
    /// - Parameter strictMode: When true, connections fail if pins don't match. When false, falls back to system trust.
    func setCertificatePinning(enabled: Bool, strictMode: Bool = false) {
        certificatePinningEnabled = enabled

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60

        if enabled {
            let delegate = CertificatePinningConfiguration.createDefaultConfiguration(strictMode: strictMode)
            session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            logDebug("Certificate pinning enabled (strict: \(strictMode))")
        } else {
            session = URLSession(configuration: config)
            logDebug("Certificate pinning disabled")
        }
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

    /// Fetches the current Stripe balance with retry logic
    func fetchBalance() async throws -> StripeBalance {
        guard let secretKey = getCredentials(), !secretKey.isEmpty else {
            throw StripeError.notConfigured
        }

        logDebug("Fetching balance from Stripe...")

        let result = try await NetworkRetry.execute(
            configuration: .default,
            onRetry: { attempt, delay in
                await MainActor.run {
                    self.logDebug("Retry attempt \(attempt) for balance, waiting \(String(format: "%.1f", delay))s")
                }
            }
        ) {
            try await self.performBalanceRequest(secretKey: secretKey)
        }

        logDebug("Balance request succeeded after \(result.attempts) attempt(s)")
        return result.value
    }

    private func performBalanceRequest(secretKey: String) async throws -> StripeBalance {
        let url = URL(string: "\(baseURL)/balance")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

        // Log raw response for debugging
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
        logDebug("Raw Stripe response: \(rawResponse)")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let balance = try decoder.decode(StripeBalance.self, from: data)
            logDebug("Parsed - Available array count: \(balance.available.count), Pending array count: \(balance.pending.count)")
            logDebug("Available amounts: \(balance.available.map { "\($0.currency): \($0.amount)" })")
            logDebug("Instant Available amounts: \(balance.instantAvailable?.map { "\($0.currency): \($0.amount)" } ?? [])")
            logDebug("Pending amounts: \(balance.pending.map { "\($0.currency): \($0.amount)" })")
            logDebug("Balance fetched - Available: \(balance.availableTotal), InstantAvailable: \(balance.instantAvailableTotal), Pending: \(balance.pendingTotal)")
            return balance
        } catch {
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
    /// Note: Risk reserves are NOT returned by Stripe's API and must be entered manually
    func syncBalance(context: NSManagedObjectContext) async throws -> StripeSnapshot {
        let balance = try await fetchBalance()

        // Convert amounts from cents to dollars
        // Use effectiveAvailable which prefers instant_available when available is 0
        let availableDecimal = Decimal(balance.effectiveAvailable) / 100
        let pendingDecimal = Decimal(balance.pendingTotal) / 100
        let reserveDecimal = Decimal(balance.connectReservedTotal) / 100

        // Create snapshot - perform Core Data operations on context's thread
        let snapshot = StripeSnapshot.create(
            in: context,
            availableBalance: availableDecimal,
            pendingBalance: pendingDecimal,
            reserveBalance: reserveDecimal
        )

        try context.save()

        logDebug("Stripe balance synced - Available: \(availableDecimal), Pending: \(pendingDecimal), Reserve: \(reserveDecimal)")
        logDebug("NOTE: Risk reserves are not included in API response - enter manually if applicable")

        return snapshot
    }

    // MARK: - Debug Logging

    private func logDebug(_ message: String) {
        DebugLogger.shared.logStripe(message)
    }
}

// MARK: - Response Models

struct StripeBalance: Decodable {
    let available: [StripeBalanceAmount]
    let pending: [StripeBalanceAmount]
    let instantAvailable: [StripeBalanceAmount]?
    let connectReserved: [StripeBalanceAmount]?
    let livemode: Bool?
    let object: String?

    /// Total available balance in cents (USD only, or first currency)
    /// Note: This is often 0 when Stripe has a risk reserve
    var availableTotal: Int {
        available.first(where: { $0.currency == "usd" })?.amount ?? available.first?.amount ?? 0
    }

    /// Total instant available balance in cents - this is what can actually be withdrawn
    var instantAvailableTotal: Int {
        instantAvailable?.first(where: { $0.currency == "usd" })?.amount ?? instantAvailable?.first?.amount ?? 0
    }

    /// Total pending balance in cents (USD only, or first currency)
    var pendingTotal: Int {
        pending.first(where: { $0.currency == "usd" })?.amount ?? pending.first?.amount ?? 0
    }

    /// Total connect reserved balance in cents (USD only, or first currency)
    var connectReservedTotal: Int {
        connectReserved?.first(where: { $0.currency == "usd" })?.amount ?? connectReserved?.first?.amount ?? 0
    }

    /// Best "available" amount - uses instant_available if available is 0
    var effectiveAvailable: Int {
        availableTotal > 0 ? availableTotal : instantAvailableTotal
    }

    /// Total holdback (pending + reserve) in cents
    /// Note: Risk reserves are NOT included in the API - must be entered manually
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
