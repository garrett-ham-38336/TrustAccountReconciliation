import Foundation
import CoreData

// MARK: - Property Extensions

extension Property {
    var displayName: String {
        name ?? "Unknown Property"
    }

    var fullAddress: String {
        var parts: [String] = []
        if let addr = address, !addr.isEmpty { parts.append(addr) }
        if let c = city, !c.isEmpty { parts.append(c) }
        if let s = state, !s.isEmpty { parts.append(s) }
        if let z = zipCode, !z.isEmpty { parts.append(z) }
        return parts.joined(separator: ", ")
    }

    var reservationsList: [Reservation] {
        guard let res = reservations as? Set<Reservation> else { return [] }
        return res.sorted { ($0.checkInDate ?? Date()) > ($1.checkInDate ?? Date()) }
    }

    var futureReservations: [Reservation] {
        reservationsList.filter { $0.isFuture }
    }

    var activeReservations: [Reservation] {
        reservationsList.filter { $0.isActive }
    }

    var completedReservations: [Reservation] {
        reservationsList.filter { $0.isCompleted }
    }

    /// Effective management fee (property-specific or owner default)
    var effectiveManagementFeePercent: Decimal {
        if let propFee = managementFeePercent as Decimal?, propFee > 0 {
            return propFee
        }
        return owner?.managementFeePercent as Decimal? ?? 20
    }

    var taxJurisdictionsList: [TaxJurisdiction] {
        guard let jurisdictions = taxJurisdictions as? Set<TaxJurisdiction> else { return [] }
        return jurisdictions.filter { $0.isActive }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Creates a new property
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        address: String? = nil,
        owner: Owner? = nil,
        guestyListingId: String? = nil
    ) -> Property {
        let property = Property(context: context)
        property.id = UUID()
        property.name = name
        property.address = address
        property.owner = owner
        property.guestyListingId = guestyListingId
        property.isActive = true
        property.createdAt = Date()
        property.updatedAt = Date()
        return property
    }

    /// Find property by Guesty listing ID
    static func findByGuestyId(_ guestyId: String, in context: NSManagedObjectContext) -> Property? {
        let request: NSFetchRequest<Property> = Property.fetchRequest()
        request.predicate = NSPredicate(format: "guestyListingId == %@", guestyId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

// MARK: - Fetch Requests

extension Property {
    static func allPropertiesFetchRequest() -> NSFetchRequest<Property> {
        let request: NSFetchRequest<Property> = Property.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Property.name, ascending: true)]
        return request
    }

    static func propertiesForOwner(_ ownerId: UUID) -> NSFetchRequest<Property> {
        let request: NSFetchRequest<Property> = Property.fetchRequest()
        request.predicate = NSPredicate(format: "owner.id == %@ AND isActive == YES", ownerId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Property.name, ascending: true)]
        return request
    }
}
