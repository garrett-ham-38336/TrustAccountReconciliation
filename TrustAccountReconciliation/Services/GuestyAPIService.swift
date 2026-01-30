import Foundation
import CoreData

/// Service for integrating with Guesty API to sync reservation data
class GuestyAPIService {
    static let shared = GuestyAPIService()

    private let baseURL = "https://open-api.guesty.com/v1"
    private let session: URLSession

    // Keychain keys
    private let keychainClientId = "com.trustaccounting.guesty.clientId"
    private let keychainClientSecret = "com.trustaccounting.guesty.clientSecret"
    private let keychainAccessToken = "com.trustaccounting.guesty.accessToken"
    private let keychainTokenExpiry = "com.trustaccounting.guesty.tokenExpiry"

    private var accessToken: String?
    private var tokenExpiry: Date?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        // Load cached token
        loadCachedToken()
    }

    // MARK: - Credential Management

    /// Stores Guesty API credentials securely in Keychain
    func saveCredentials(clientId: String, clientSecret: String) throws {
        try KeychainService.shared.save(key: keychainClientId, value: clientId)
        try KeychainService.shared.save(key: keychainClientSecret, value: clientSecret)
        // Clear any existing token when credentials change
        try? KeychainService.shared.delete(key: keychainAccessToken)
        try? KeychainService.shared.delete(key: keychainTokenExpiry)
        accessToken = nil
        tokenExpiry = nil
    }

    /// Retrieves stored credentials
    func getCredentials() -> (clientId: String, clientSecret: String)? {
        guard let clientId = try? KeychainService.shared.retrieve(key: keychainClientId),
              let clientSecret = try? KeychainService.shared.retrieve(key: keychainClientSecret) else {
            return nil
        }
        return (clientId, clientSecret)
    }

    /// Checks if credentials are configured
    var hasCredentials: Bool {
        getCredentials() != nil
    }

    /// Clears stored credentials
    func clearCredentials() throws {
        try KeychainService.shared.delete(key: keychainClientId)
        try KeychainService.shared.delete(key: keychainClientSecret)
        try? KeychainService.shared.delete(key: keychainAccessToken)
        try? KeychainService.shared.delete(key: keychainTokenExpiry)
        accessToken = nil
        tokenExpiry = nil
    }

    /// Tests authentication by getting a valid token
    func authenticate() async throws {
        _ = try await getValidToken()
    }

    // MARK: - Authentication

    private func loadCachedToken() {
        if let token = try? KeychainService.shared.retrieve(key: keychainAccessToken),
           let expiryString = try? KeychainService.shared.retrieve(key: keychainTokenExpiry),
           let expiryInterval = Double(expiryString) {
            let expiry = Date(timeIntervalSince1970: expiryInterval)
            if expiry > Date() {
                self.accessToken = token
                self.tokenExpiry = expiry
            }
        }
    }

    private func saveToken(_ token: String, expiry: Date) {
        try? KeychainService.shared.save(key: keychainAccessToken, value: token)
        try? KeychainService.shared.save(key: keychainTokenExpiry, value: String(expiry.timeIntervalSince1970))
        self.accessToken = token
        self.tokenExpiry = expiry
    }

    /// Gets a valid access token, refreshing if needed
    private func getValidToken() async throws -> String {
        // Check if we have a valid cached token (with 60 second buffer before expiry)
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            logDebug("Using cached token (expires: \(expiry))")
            return token
        }

        logDebug("Token missing or expired, requesting new token...")

        // Need to get a new token
        guard let credentials = getCredentials() else {
            throw GuestyError.notConfigured
        }

        let tokenURL = URL(string: "https://open-api.guesty.com/oauth2/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=client_credentials&scope=open-api&client_id=\(credentials.clientId)&client_secret=\(credentials.clientSecret)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GuestyError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logDebug("Token request failed with status: \(httpResponse.statusCode)")
            throw GuestyError.authenticationFailed(httpResponse.statusCode)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        saveToken(tokenResponse.accessToken, expiry: expiry)
        logDebug("New token obtained, expires: \(expiry)")

        return tokenResponse.accessToken
    }

    // MARK: - API Requests

    private func makeRequest<T: Decodable>(_ endpoint: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let token = try await getValidToken()

        var components = URLComponents(string: "\(baseURL)\(endpoint)")!
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GuestyError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // Log the error response
            let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
            logDebug("API Error from \(endpoint): HTTP \(httpResponse.statusCode)\nResponse: \(rawResponse)")

            if let errorResponse = try? JSONDecoder().decode(GuestyErrorResponse.self, from: data) {
                throw GuestyError.apiError(errorResponse.message ?? rawResponse)
            }
            throw GuestyError.apiError("HTTP \(httpResponse.statusCode): \(rawResponse)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try multiple date formats
            let formatters: [DateFormatter] = {
                let formats = [
                    "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                    "yyyy-MM-dd'T'HH:mm:ssZ",
                    "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                    "yyyy-MM-dd'T'HH:mm:ss'Z'",
                    "yyyy-MM-dd"
                ]
                return formats.map { format in
                    let formatter = DateFormatter()
                    formatter.dateFormat = format
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    return formatter
                }
            }()

            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }

            // Try ISO8601DateFormatter as fallback
            let iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601.date(from: dateString) {
                return date
            }
            iso8601.formatOptions = [.withInternetDateTime]
            if let date = iso8601.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Debug: log raw response on decode failure
            if let jsonString = String(data: data, encoding: .utf8) {
                logDebug("Failed to decode response from \(endpoint)")
                logDebug("Error: \(error)")
                logDebug("Raw JSON (first 3000 chars): \(String(jsonString.prefix(3000)))")
            }
            throw error
        }
    }

    // MARK: - Debug Logging

    private func logDebug(_ message: String) {
        print("GUESTY DEBUG: \(message)")
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TrustAccountReconciliation/debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        if let existing = try? String(contentsOf: logURL, encoding: .utf8) {
            try? (existing + logMessage).write(to: logURL, atomically: true, encoding: .utf8)
        } else {
            try? logMessage.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Fetch Listings (Properties)

    func fetchListings() async throws -> [GuestyListing] {
        logDebug("Starting fetchListings()")

        struct ListingsResponse: Decodable {
            let results: [GuestyListing]
            let count: Int?
            let limit: Int?
            let skip: Int?

            // Handle both "results" and "data" wrappers
            enum CodingKeys: String, CodingKey {
                case results, data, count, limit, skip
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let results = try? container.decode([GuestyListing].self, forKey: .results) {
                    self.results = results
                } else if let data = try? container.decode([GuestyListing].self, forKey: .data) {
                    self.results = data
                } else {
                    self.results = []
                }
                self.count = try? container.decode(Int.self, forKey: .count)
                self.limit = try? container.decode(Int.self, forKey: .limit)
                self.skip = try? container.decode(Int.self, forKey: .skip)
            }
        }

        var allListings: [GuestyListing] = []
        var skip = 0
        let limit = 100

        repeat {
            logDebug("Fetching listings batch: skip=\(skip), limit=\(limit)")
            let response: ListingsResponse = try await makeRequest(
                "/listings",
                queryItems: [
                    URLQueryItem(name: "fields", value: "_id nickname title active address"),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "skip", value: String(skip))
                ]
            )
            logDebug("Got \(response.results.count) listings in this batch")
            allListings.append(contentsOf: response.results)
            skip += limit

            if response.results.count < limit {
                break
            }
        } while true

        logDebug("Total listings fetched: \(allListings.count)")
        return allListings
    }

    // MARK: - Fetch Reservations

    func fetchReservations(checkInFrom: Date? = nil, checkOutFrom: Date? = nil) async throws -> [GuestyReservation] {
        logDebug("Starting fetchReservations(checkInFrom: \(checkInFrom?.description ?? "nil"), checkOutFrom: \(checkOutFrom?.description ?? "nil"))")

        struct ReservationsResponse: Decodable {
            let results: [GuestyReservation]
            let count: Int?
            let limit: Int?
            let skip: Int?

            enum CodingKeys: String, CodingKey {
                case results, data, count, limit, skip
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let results = try? container.decode([GuestyReservation].self, forKey: .results) {
                    self.results = results
                } else if let data = try? container.decode([GuestyReservation].self, forKey: .data) {
                    self.results = data
                } else {
                    self.results = []
                }
                self.count = try? container.decode(Int.self, forKey: .count)
                self.limit = try? container.decode(Int.self, forKey: .limit)
                self.skip = try? container.decode(Int.self, forKey: .skip)
            }
        }

        var allReservations: [GuestyReservation] = []
        var skip = 0
        let limit = 100

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        // Build filters array using Guesty's filter syntax
        var filters: [[String: Any]] = []

        if let checkInFrom = checkInFrom {
            filters.append([
                "operator": "$gte",
                "field": "checkInDateLocalized",
                "value": dateFormatter.string(from: checkInFrom)
            ])
        }

        if let checkOutFrom = checkOutFrom {
            filters.append([
                "operator": "$gte",
                "field": "checkOutDateLocalized",
                "value": dateFormatter.string(from: checkOutFrom)
            ])
        }

        // Convert filters to JSON string
        var filtersJSON: String? = nil
        if !filters.isEmpty {
            if let jsonData = try? JSONSerialization.data(withJSONObject: filters),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                filtersJSON = jsonString
                logDebug("Using filters: \(jsonString)")
            }
        }

        // Fields to request - must explicitly include money fields
        let fields = [
            "_id", "confirmationCode", "listingId", "listing",
            "checkIn", "checkOut", "checkInDateLocalized", "checkOutDateLocalized",
            "nightsCount", "status", "source",
            "guest.fullName", "guest.firstName", "guest.lastName", "guest.email", "guest.phone",
            // Financial totals
            "money.hostPayout", "money.totalPaid", "money.balanceDue",
            "money.fareAccommodation", "money.fareCleaning", "money.totalTaxes",
            "money.hostServiceFee", "money.guestServiceFee", "money.subTotalPrice",
            // Detailed invoice items (includes tax breakdown)
            "money.invoiceItems",
            // Tax definitions
            "money.taxes",
            // Payment details
            "money.payments.amount", "money.payments.status", "money.payments.paidAt", "money.payments.currency"
        ].joined(separator: " ")

        repeat {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "skip", value: String(skip)),
                URLQueryItem(name: "sort", value: "-checkInDateLocalized"),
                URLQueryItem(name: "fields", value: fields)
            ]

            // Add filters if present
            if let filtersJSON = filtersJSON {
                queryItems.append(URLQueryItem(name: "filters", value: filtersJSON))
            }

            logDebug("Fetching reservations batch: skip=\(skip), limit=\(limit)")
            let response: ReservationsResponse = try await makeRequest(
                "/reservations",
                queryItems: queryItems
            )
            logDebug("Got \(response.results.count) reservations in this batch")
            allReservations.append(contentsOf: response.results)
            skip += limit

            // Stop if we got fewer than limit (no more results)
            if response.results.count < limit {
                break
            }
        } while true

        logDebug("Total reservations fetched: \(allReservations.count)")
        return allReservations
    }

    // MARK: - Sync Data to Core Data

    @MainActor
    func syncReservations(context: NSManagedObjectContext, progressHandler: ((String) -> Void)? = nil) async throws -> SyncResult {
        var result = SyncResult()
        let startTime = Date()

        logDebug("Starting syncReservations")
        progressHandler?("Fetching listings from Guesty...")

        // First sync listings (properties)
        let listings = try await fetchListings()
        logDebug("Processing \(listings.count) listings...")
        progressHandler?("Processing \(listings.count) listings...")

        for listing in listings {
            // Debug: log nickname and title for each listing
            logDebug("Listing ID: \(listing.id) | nickname: '\(listing.nickname ?? "nil")' | title: '\(listing.title ?? "nil")' | using: '\(listing.nickname ?? listing.title ?? "Unknown")'")

            if let existing = Property.findByGuestyId(listing.id, in: context) {
                // Update existing
                existing.name = listing.nickname ?? listing.title ?? "Unknown"
                existing.address = listing.address?.full
                existing.city = listing.address?.city
                existing.state = listing.address?.state
                existing.zipCode = listing.address?.zipcode
                existing.updatedAt = Date()
                result.propertiesUpdated += 1
            } else {
                // Create new
                let property = Property(context: context)
                property.id = UUID()
                property.guestyListingId = listing.id
                property.name = listing.nickname ?? listing.title ?? "Unknown"
                property.address = listing.address?.full
                property.city = listing.address?.city
                property.state = listing.address?.state
                property.zipCode = listing.address?.zipcode
                property.isActive = listing.active ?? true
                property.createdAt = Date()
                property.updatedAt = Date()
                result.propertiesCreated += 1
            }
        }

        logDebug("Saving properties to Core Data...")
        do {
            try context.save()
            logDebug("Properties saved successfully")
        } catch {
            logDebug("ERROR saving properties: \(error)")
            throw error
        }

        progressHandler?("Fetching reservations from Guesty...")

        // Fetch all reservations where checkout is 30+ days ago or later
        // This captures: past 30 days, in-progress, and all future reservations
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        logDebug("Fetching reservations with checkOut >= \(thirtyDaysAgo)")
        let reservations = try await fetchReservations(checkOutFrom: thirtyDaysAgo)

        logDebug("Processing \(reservations.count) reservations...")
        progressHandler?("Processing \(reservations.count) reservations...")

        for (index, guestyRes) in reservations.enumerated() {
            if let existing = Reservation.findByGuestyId(guestyRes.id, in: context) {
                // Update existing reservation
                updateReservation(existing, from: guestyRes, in: context)
                result.reservationsUpdated += 1
            } else {
                // Create new reservation
                let reservation = Reservation(context: context)
                reservation.id = UUID()
                reservation.guestyReservationId = guestyRes.id
                reservation.createdAt = Date()
                updateReservation(reservation, from: guestyRes, in: context)
                result.reservationsCreated += 1
            }

            // Log progress every 50 reservations
            if index > 0 && index % 50 == 0 {
                logDebug("Processed \(index) reservations...")
            }
        }

        logDebug("Saving reservations to Core Data...")
        do {
            try context.save()
            logDebug("Reservations saved successfully")
        } catch {
            logDebug("ERROR saving reservations: \(error)")
            // Log more details about validation errors
            if let nsError = error as NSError? {
                logDebug("Error domain: \(nsError.domain), code: \(nsError.code)")
                if let validationErrors = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                    for (i, validationError) in validationErrors.enumerated() {
                        logDebug("Validation error \(i): \(validationError)")
                        if let key = validationError.userInfo[NSValidationKeyErrorKey] {
                            logDebug("  Key: \(key)")
                        }
                        if let object = validationError.userInfo[NSValidationObjectErrorKey] {
                            logDebug("  Object: \(object)")
                        }
                    }
                }
            }
            throw error
        }

        logDebug("Creating sync log...")
        // Log the sync
        let syncLog = SyncLog(context: context)
        syncLog.id = UUID()
        syncLog.syncDate = Date()
        syncLog.syncType = "full"
        syncLog.recordsCreated = Int32(result.reservationsCreated + result.propertiesCreated)
        syncLog.recordsUpdated = Int32(result.reservationsUpdated + result.propertiesUpdated)
        syncLog.status = "success"
        syncLog.durationSeconds = Date().timeIntervalSince(startTime)

        do {
            try context.save()
            logDebug("Sync log saved successfully")
        } catch {
            logDebug("ERROR saving sync log: \(error)")
            throw error
        }

        result.duration = Date().timeIntervalSince(startTime)
        logDebug("Sync complete! Created: \(result.reservationsCreated), Updated: \(result.reservationsUpdated)")
        progressHandler?("Sync complete! \(result.reservationsCreated + result.reservationsUpdated) reservations processed.")

        return result
    }

    private func updateReservation(_ reservation: Reservation, from guesty: GuestyReservation, in context: NSManagedObjectContext) {
        reservation.confirmationCode = guesty.confirmationCode ?? "N/A"
        reservation.guestName = guesty.guest?.fullName ?? "Unknown Guest"
        reservation.guestEmail = guesty.guest?.email
        reservation.guestPhone = guesty.guest?.phone
        reservation.checkInDate = guesty.checkIn
        reservation.checkOutDate = guesty.checkOut
        reservation.nightCount = Int16(guesty.nightsCount ?? 0)
        reservation.status = guesty.status ?? "unknown"
        reservation.source = guesty.source ?? "unknown"

        // Financial data
        if let money = guesty.money {
            // Total amount = subtotal (accommodation + cleaning + taxes)
            let total = (money.subTotalPrice ?? 0) > 0 ? money.subTotalPrice! :
                        ((money.fareAccommodation ?? 0) + (money.fareCleaning ?? 0) + (money.totalTaxes ?? 0))
            reservation.totalAmount = NSDecimalNumber(value: total)
            reservation.accommodationFare = NSDecimalNumber(value: money.fareAccommodation ?? 0)
            reservation.cleaningFee = NSDecimalNumber(value: money.fareCleaning ?? 0)
            reservation.taxAmount = NSDecimalNumber(value: money.totalTaxes ?? 0)
            reservation.hostServiceFee = NSDecimalNumber(value: money.hostServiceFee ?? 0)
            reservation.guestServiceFee = NSDecimalNumber(value: money.guestServiceFee ?? 0)

            // Deposit received = totalPaid from Guesty
            reservation.depositReceived = NSDecimalNumber(value: money.totalPaid ?? 0)
            reservation.isFullyPaid = (money.balanceDue ?? 0) <= 0
        }

        // Calculate owner payout and management fee
        reservation.managementFee = reservation.calculateManagementFee() as NSDecimalNumber
        reservation.ownerPayout = reservation.calculateOwnerPayout() as NSDecimalNumber

        // Cancellation
        reservation.isCancelled = guesty.status == "canceled" || guesty.status == "cancelled"
        if reservation.isCancelled, reservation.cancellationDate == nil {
            reservation.cancellationDate = Date()
        }

        // Link to property
        if let listingId = guesty.listingId,
           let property = Property.findByGuestyId(listingId, in: context) {
            reservation.property = property
        }

        reservation.lastSyncedAt = Date()
        reservation.updatedAt = Date()
    }

    struct SyncResult {
        var propertiesCreated = 0
        var propertiesUpdated = 0
        var reservationsCreated = 0
        var reservationsUpdated = 0
        var duration: TimeInterval = 0

        var totalProcessed: Int {
            propertiesCreated + propertiesUpdated + reservationsCreated + reservationsUpdated
        }
    }
}

// MARK: - API Response Models

struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct GuestyErrorResponse: Decodable {
    let error: String?
    let message: String?
}

struct GuestyListing: Decodable {
    let id: String
    let title: String?
    let nickname: String?
    let active: Bool?
    let address: GuestyAddress?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case altId = "id"
        case title, nickname, active, address
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try _id first, then id
        if let id = try? container.decode(String.self, forKey: .id) {
            self.id = id
        } else if let id = try? container.decode(String.self, forKey: .altId) {
            self.id = id
        } else {
            throw DecodingError.keyNotFound(CodingKeys.id, DecodingError.Context(codingPath: container.codingPath, debugDescription: "No id found"))
        }
        self.title = try? container.decode(String.self, forKey: .title)
        self.nickname = try? container.decode(String.self, forKey: .nickname)
        self.active = try? container.decode(Bool.self, forKey: .active)
        self.address = try? container.decode(GuestyAddress.self, forKey: .address)
    }
}

struct GuestyAddress: Decodable {
    let full: String?
    let street: String?
    let city: String?
    let state: String?
    let zipcode: String?
    let country: String?
}

struct GuestyReservation: Decodable {
    let id: String
    let confirmationCode: String?
    let listingId: String?
    let checkIn: Date?
    let checkOut: Date?
    let nightsCount: Int?
    let status: String?
    let source: String?
    let guest: GuestyGuest?
    let money: GuestyMoney?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case altId = "id"
        case confirmationCode, listingId, listing
        case checkIn, checkInDateLocalized
        case checkOut, checkOutDateLocalized
        case nightsCount, nights
        case status, source, guest, money
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try _id first, then id
        if let id = try? container.decode(String.self, forKey: .id) {
            self.id = id
        } else if let id = try? container.decode(String.self, forKey: .altId) {
            self.id = id
        } else {
            throw DecodingError.keyNotFound(CodingKeys.id, DecodingError.Context(codingPath: container.codingPath, debugDescription: "No id found"))
        }

        self.confirmationCode = try? container.decode(String.self, forKey: .confirmationCode)

        // listingId might be in listingId or listing._id
        if let listingId = try? container.decode(String.self, forKey: .listingId) {
            self.listingId = listingId
        } else if let listing = try? container.decode([String: String].self, forKey: .listing),
                  let listingId = listing["_id"] ?? listing["id"] {
            self.listingId = listingId
        } else {
            self.listingId = nil
        }

        // Dates - try multiple fields
        if let checkIn = try? container.decode(Date.self, forKey: .checkIn) {
            self.checkIn = checkIn
        } else if let checkInStr = try? container.decode(String.self, forKey: .checkInDateLocalized) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self.checkIn = formatter.date(from: checkInStr)
        } else {
            self.checkIn = nil
        }

        if let checkOut = try? container.decode(Date.self, forKey: .checkOut) {
            self.checkOut = checkOut
        } else if let checkOutStr = try? container.decode(String.self, forKey: .checkOutDateLocalized) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self.checkOut = formatter.date(from: checkOutStr)
        } else {
            self.checkOut = nil
        }

        // nightsCount might be nightsCount or nights
        if let nights = try? container.decode(Int.self, forKey: .nightsCount) {
            self.nightsCount = nights
        } else if let nights = try? container.decode(Int.self, forKey: .nights) {
            self.nightsCount = nights
        } else {
            self.nightsCount = nil
        }

        self.status = try? container.decode(String.self, forKey: .status)
        self.source = try? container.decode(String.self, forKey: .source)
        self.guest = try? container.decode(GuestyGuest.self, forKey: .guest)
        self.money = try? container.decode(GuestyMoney.self, forKey: .money)
    }
}

struct GuestyGuest: Decodable {
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case fullName, firstName, lastName, email, phone, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.firstName = try? container.decode(String.self, forKey: .firstName)
        self.lastName = try? container.decode(String.self, forKey: .lastName)
        self.email = try? container.decode(String.self, forKey: .email)
        self.phone = try? container.decode(String.self, forKey: .phone)

        // fullName might be in fullName or name, or constructed from firstName + lastName
        if let name = try? container.decode(String.self, forKey: .fullName) {
            self.fullName = name
        } else if let name = try? container.decode(String.self, forKey: .name) {
            self.fullName = name
        } else if let first = self.firstName, let last = self.lastName {
            self.fullName = "\(first) \(last)"
        } else {
            self.fullName = self.firstName ?? self.lastName
        }
    }
}

struct GuestyMoney: Decodable {
    let fareAccommodation: Double?
    let fareCleaning: Double?
    let totalTaxes: Double?
    let totalPaid: Double?
    let hostPayout: Double?
    let hostServiceFee: Double?
    let guestServiceFee: Double?
    let balanceDue: Double?
    let subTotalPrice: Double?
    let payments: [GuestyPayment]?
    let invoiceItems: [GuestyInvoiceItem]?

    enum CodingKeys: String, CodingKey {
        case fareAccommodation, fareCleaning, totalTaxes, totalPaid, hostPayout
        case hostServiceFee, guestServiceFee, balanceDue, payments
        case subTotalPrice, totalPrice, netIncome, invoiceItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.fareAccommodation = Self.decodeDouble(from: container, forKey: .fareAccommodation)
        self.fareCleaning = Self.decodeDouble(from: container, forKey: .fareCleaning)
        self.totalTaxes = Self.decodeDouble(from: container, forKey: .totalTaxes)
        self.totalPaid = Self.decodeDouble(from: container, forKey: .totalPaid)
        self.hostServiceFee = Self.decodeDouble(from: container, forKey: .hostServiceFee)
        self.guestServiceFee = Self.decodeDouble(from: container, forKey: .guestServiceFee)
        self.balanceDue = Self.decodeDouble(from: container, forKey: .balanceDue)
        self.subTotalPrice = Self.decodeDouble(from: container, forKey: .subTotalPrice)

        // hostPayout might be hostPayout or netIncome
        if let payout = Self.decodeDouble(from: container, forKey: .hostPayout) {
            self.hostPayout = payout
        } else {
            self.hostPayout = Self.decodeDouble(from: container, forKey: .netIncome)
        }

        self.payments = try? container.decode([GuestyPayment].self, forKey: .payments)
        self.invoiceItems = try? container.decode([GuestyInvoiceItem].self, forKey: .invoiceItems)
    }

    /// Get tourism/occupancy tax amount from invoice items
    var tourismTax: Double {
        invoiceItems?.filter { item in
            let title = item.title?.lowercased() ?? ""
            let type = item.type?.lowercased() ?? ""
            return title.contains("tourism") || title.contains("occupancy") ||
                   title.contains("lodging") || title.contains("transient") ||
                   type.contains("tax") || type.contains("city_tax") ||
                   type.contains("local_tax") || type.contains("tourism")
        }.reduce(0.0) { $0 + ($1.amount ?? 0) } ?? 0
    }

    private static func decodeDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decode(String.self, forKey: key), let doubleValue = Double(value) {
            return doubleValue
        }
        return nil
    }
}

struct GuestyInvoiceItem: Decodable {
    let title: String?
    let amount: Double?
    let currency: String?
    let type: String?
    let normalType: String?

    enum CodingKeys: String, CodingKey {
        case title, amount, currency, type, normalType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try? container.decode(String.self, forKey: .title)
        self.currency = try? container.decode(String.self, forKey: .currency)
        self.type = try? container.decode(String.self, forKey: .type)
        self.normalType = try? container.decode(String.self, forKey: .normalType)

        // Amount might be Double, Int, or String
        if let value = try? container.decode(Double.self, forKey: .amount) {
            self.amount = value
        } else if let value = try? container.decode(Int.self, forKey: .amount) {
            self.amount = Double(value)
        } else if let value = try? container.decode(String.self, forKey: .amount), let doubleValue = Double(value) {
            self.amount = doubleValue
        } else {
            self.amount = nil
        }
    }
}

struct GuestyPayment: Decodable {
    let amount: Double?
    let currency: String?
    let status: String?
    let paidAt: Date?

    enum CodingKeys: String, CodingKey {
        case amount, currency, status, paidAt, paymentDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Amount might be Double, Int, or String
        if let value = try? container.decode(Double.self, forKey: .amount) {
            self.amount = value
        } else if let value = try? container.decode(Int.self, forKey: .amount) {
            self.amount = Double(value)
        } else if let value = try? container.decode(String.self, forKey: .amount), let doubleValue = Double(value) {
            self.amount = doubleValue
        } else {
            self.amount = nil
        }

        self.currency = try? container.decode(String.self, forKey: .currency)
        self.status = try? container.decode(String.self, forKey: .status)

        // paidAt might be paidAt or paymentDate
        if let date = try? container.decode(Date.self, forKey: .paidAt) {
            self.paidAt = date
        } else if let date = try? container.decode(Date.self, forKey: .paymentDate) {
            self.paidAt = date
        } else {
            self.paidAt = nil
        }
    }
}

// MARK: - Errors

enum GuestyError: LocalizedError {
    case notConfigured
    case authenticationFailed(Int)
    case requestFailed(Int)
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Guesty API credentials not configured. Please enter your Client ID and Secret in Settings."
        case .authenticationFailed(let code):
            return "Authentication failed (HTTP \(code)). Please check your credentials."
        case .requestFailed(let code):
            return "API request failed (HTTP \(code))."
        case .invalidResponse:
            return "Invalid response from Guesty API."
        case .apiError(let message):
            return "Guesty API error: \(message)"
        }
    }
}
