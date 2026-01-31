import Foundation
import CoreSpotlight
import CoreData
import UniformTypeIdentifiers

/// Service for indexing app content in Spotlight search
class SpotlightService {
    static let shared = SpotlightService()

    private let searchableIndex = CSSearchableIndex.default()

    // Domain identifiers for different content types
    private let ownerDomain = "com.trustaccounting.owner"
    private let propertyDomain = "com.trustaccounting.property"
    private let reservationDomain = "com.trustaccounting.reservation"

    private init() {}

    // MARK: - Index All Content

    /// Indexes all content from Core Data
    func indexAllContent(context: NSManagedObjectContext) {
        Task {
            await indexOwners(context: context)
            await indexProperties(context: context)
            await indexReservations(context: context)
        }
    }

    // MARK: - Index Owners

    /// Indexes all owners in Spotlight
    func indexOwners(context: NSManagedObjectContext) async {
        let request: NSFetchRequest<Owner> = Owner.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")

        guard let owners = try? context.fetch(request) else { return }

        var items: [CSSearchableItem] = []

        for owner in owners {
            if let item = createSearchableItem(for: owner) {
                items.append(item)
            }
        }

        do {
            try await searchableIndex.indexSearchableItems(items)
            DebugLogger.shared.log("Indexed \(items.count) owners in Spotlight")
        } catch {
            DebugLogger.shared.logError(error, context: "Spotlight owner indexing")
        }
    }

    /// Creates a searchable item for an owner
    private func createSearchableItem(for owner: Owner) -> CSSearchableItem? {
        guard let id = owner.id?.uuidString else { return nil }

        let attributes = CSSearchableItemAttributeSet(contentType: .contact)
        attributes.title = owner.name ?? "Unknown Owner"
        attributes.displayName = owner.name
        attributes.contentDescription = createOwnerDescription(owner)
        attributes.emailAddresses = owner.email.map { [$0] }
        attributes.phoneNumbers = owner.phone.map { [$0] }
        attributes.keywords = ["owner", "property owner", owner.name ?? ""].compactMap { $0 }

        let item = CSSearchableItem(
            uniqueIdentifier: "\(ownerDomain).\(id)",
            domainIdentifier: ownerDomain,
            attributeSet: attributes
        )
        item.expirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())

        return item
    }

    private func createOwnerDescription(_ owner: Owner) -> String {
        var parts: [String] = ["Property Owner"]

        if let propertyCount = owner.properties?.count, propertyCount > 0 {
            parts.append("\(propertyCount) properties")
        }

        if let email = owner.email {
            parts.append(email)
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Index Properties

    /// Indexes all properties in Spotlight
    func indexProperties(context: NSManagedObjectContext) async {
        let request: NSFetchRequest<Property> = Property.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")

        guard let properties = try? context.fetch(request) else { return }

        var items: [CSSearchableItem] = []

        for property in properties {
            if let item = createSearchableItem(for: property) {
                items.append(item)
            }
        }

        do {
            try await searchableIndex.indexSearchableItems(items)
            DebugLogger.shared.log("Indexed \(items.count) properties in Spotlight")
        } catch {
            DebugLogger.shared.logError(error, context: "Spotlight property indexing")
        }
    }

    /// Creates a searchable item for a property
    private func createSearchableItem(for property: Property) -> CSSearchableItem? {
        guard let id = property.id?.uuidString else { return nil }

        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = property.name ?? "Unknown Property"
        attributes.displayName = property.nickname ?? property.name
        attributes.contentDescription = createPropertyDescription(property)

        // Location info
        if let address = property.address {
            attributes.namedLocation = address
        }
        if let city = property.city {
            attributes.city = city
        }
        if let state = property.state {
            attributes.stateOrProvince = state
        }

        attributes.keywords = [
            "property",
            "rental",
            "vacation rental",
            property.name ?? "",
            property.nickname ?? "",
            property.city ?? "",
            property.owner?.name ?? ""
        ].filter { !$0.isEmpty }

        let item = CSSearchableItem(
            uniqueIdentifier: "\(propertyDomain).\(id)",
            domainIdentifier: propertyDomain,
            attributeSet: attributes
        )
        item.expirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())

        return item
    }

    private func createPropertyDescription(_ property: Property) -> String {
        var parts: [String] = ["Rental Property"]

        if let ownerName = property.owner?.name {
            parts.append("Owner: \(ownerName)")
        }

        if let city = property.city, let state = property.state {
            parts.append("\(city), \(state)")
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Index Reservations

    /// Indexes recent and upcoming reservations in Spotlight
    func indexReservations(context: NSManagedObjectContext) async {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()

        // Index upcoming and recent (past 30 days) reservations
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        request.predicate = NSPredicate(format: "checkOutDate >= %@ AND isCancelled == NO", thirtyDaysAgo as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.checkInDate, ascending: false)]
        request.fetchLimit = 500 // Limit to most relevant

        guard let reservations = try? context.fetch(request) else { return }

        var items: [CSSearchableItem] = []

        for reservation in reservations {
            if let item = createSearchableItem(for: reservation) {
                items.append(item)
            }
        }

        do {
            try await searchableIndex.indexSearchableItems(items)
            DebugLogger.shared.log("Indexed \(items.count) reservations in Spotlight")
        } catch {
            DebugLogger.shared.logError(error, context: "Spotlight reservation indexing")
        }
    }

    /// Creates a searchable item for a reservation
    private func createSearchableItem(for reservation: Reservation) -> CSSearchableItem? {
        guard let id = reservation.id?.uuidString else { return nil }

        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = reservation.guestName ?? "Unknown Guest"
        attributes.displayName = "\(reservation.guestName ?? "Guest") - \(reservation.property?.name ?? "Property")"
        attributes.contentDescription = createReservationDescription(reservation)

        // Dates
        attributes.startDate = reservation.checkInDate
        attributes.endDate = reservation.checkOutDate

        // Contact
        if let email = reservation.guestEmail {
            attributes.emailAddresses = [email]
        }
        if let phone = reservation.guestPhone {
            attributes.phoneNumbers = [phone]
        }

        attributes.keywords = [
            "reservation",
            "booking",
            "guest",
            reservation.guestName ?? "",
            reservation.confirmationCode ?? "",
            reservation.property?.name ?? "",
            reservation.source ?? ""
        ].filter { !$0.isEmpty }

        let item = CSSearchableItem(
            uniqueIdentifier: "\(reservationDomain).\(id)",
            domainIdentifier: reservationDomain,
            attributeSet: attributes
        )

        // Set expiration based on checkout date
        if let checkOut = reservation.checkOutDate {
            item.expirationDate = Calendar.current.date(byAdding: .month, value: 3, to: checkOut)
        }

        return item
    }

    private func createReservationDescription(_ reservation: Reservation) -> String {
        var parts: [String] = []

        if let propertyName = reservation.property?.name {
            parts.append(propertyName)
        }

        if let checkIn = reservation.checkInDate, let checkOut = reservation.checkOutDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append("\(formatter.string(from: checkIn)) - \(formatter.string(from: checkOut))")
        }

        if let code = reservation.confirmationCode {
            parts.append("Conf: \(code)")
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Update Individual Items

    /// Updates or adds a single owner to the index
    func updateOwner(_ owner: Owner) {
        guard let item = createSearchableItem(for: owner) else { return }

        searchableIndex.indexSearchableItems([item]) { error in
            if let error = error {
                DebugLogger.shared.logError(error, context: "Spotlight update owner")
            }
        }
    }

    /// Updates or adds a single property to the index
    func updateProperty(_ property: Property) {
        guard let item = createSearchableItem(for: property) else { return }

        searchableIndex.indexSearchableItems([item]) { error in
            if let error = error {
                DebugLogger.shared.logError(error, context: "Spotlight update property")
            }
        }
    }

    /// Updates or adds a single reservation to the index
    func updateReservation(_ reservation: Reservation) {
        guard let item = createSearchableItem(for: reservation) else { return }

        searchableIndex.indexSearchableItems([item]) { error in
            if let error = error {
                DebugLogger.shared.logError(error, context: "Spotlight update reservation")
            }
        }
    }

    // MARK: - Remove Items

    /// Removes an owner from the index
    func removeOwner(id: UUID) {
        let identifier = "\(ownerDomain).\(id.uuidString)"
        searchableIndex.deleteSearchableItems(withIdentifiers: [identifier]) { error in
            if let error = error {
                DebugLogger.shared.logError(error, context: "Spotlight remove owner")
            }
        }
    }

    /// Removes a property from the index
    func removeProperty(id: UUID) {
        let identifier = "\(propertyDomain).\(id.uuidString)"
        searchableIndex.deleteSearchableItems(withIdentifiers: [identifier]) { error in
            if let error = error {
                DebugLogger.shared.logError(error, context: "Spotlight remove property")
            }
        }
    }

    /// Removes a reservation from the index
    func removeReservation(id: UUID) {
        let identifier = "\(reservationDomain).\(id.uuidString)"
        searchableIndex.deleteSearchableItems(withIdentifiers: [identifier]) { error in
            if let error = error {
                DebugLogger.shared.logError(error, context: "Spotlight remove reservation")
            }
        }
    }

    // MARK: - Clear Index

    /// Clears all indexed content
    func clearAllIndexes() async {
        do {
            try await searchableIndex.deleteAllSearchableItems()
            DebugLogger.shared.log("Cleared all Spotlight indexes")
        } catch {
            DebugLogger.shared.logError(error, context: "Spotlight clear all")
        }
    }

    /// Clears index for a specific domain
    func clearDomain(_ domain: String) async {
        do {
            try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [domain])
            DebugLogger.shared.log("Cleared Spotlight index for domain: \(domain)")
        } catch {
            DebugLogger.shared.logError(error, context: "Spotlight clear domain")
        }
    }

    // MARK: - Handle Spotlight Results

    /// Parses a Spotlight activity identifier to determine the content type and ID
    /// Returns a tuple of (type: String, id: UUID) or nil if invalid
    static func parseSpotlightIdentifier(_ identifier: String) -> (type: String, id: UUID)? {
        let components = identifier.components(separatedBy: ".")

        guard components.count >= 4 else { return nil }

        // Format: com.trustaccounting.<type>.<uuid>
        let type = components[2] // "owner", "property", or "reservation"
        let uuidString = components[3]

        guard let uuid = UUID(uuidString: uuidString) else { return nil }

        return (type, uuid)
    }
}

// MARK: - NSUserActivity Extension for Spotlight

extension NSUserActivity {
    /// Creates a user activity for continuing from Spotlight
    static func spotlightActivity(for identifier: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: identifier]
        return activity
    }
}
