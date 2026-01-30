import Foundation
import CoreData

// MARK: - Owner Extensions

extension Owner {
    var displayName: String {
        name ?? "Unknown Owner"
    }

    var initials: String {
        guard let name = name, !name.isEmpty else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    var propertiesList: [Property] {
        guard let props = properties as? Set<Property> else { return [] }
        return props.filter { $0.isActive }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var propertyCount: Int {
        propertiesList.count
    }

    /// Calculates total unpaid owner payouts across all properties
    func totalUnpaidPayouts(in context: NSManagedObjectContext) -> Decimal {
        let request = Reservation.completedUnpaidPayouts(since: lastPayoutDate)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            request.predicate!,
            NSPredicate(format: "property.owner == %@", self)
        ])

        guard let reservations = try? context.fetch(request) else { return 0 }
        return reservations.reduce(Decimal(0)) { sum, res in
            sum + (res.ownerPayout as Decimal? ?? 0)
        }
    }

    /// Gets all unpaid reservations for this owner
    func unpaidReservations(in context: NSManagedObjectContext) -> [Reservation] {
        let request = Reservation.completedUnpaidPayouts(since: lastPayoutDate)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            request.predicate!,
            NSPredicate(format: "property.owner == %@", self)
        ])
        return (try? context.fetch(request)) ?? []
    }

    /// Days since last payout
    var daysSinceLastPayout: Int? {
        guard let lastPayout = lastPayoutDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastPayout, to: Date()).day
    }

    /// Creates a new owner
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        email: String? = nil,
        phone: String? = nil,
        managementFeePercent: Decimal = 20
    ) -> Owner {
        let owner = Owner(context: context)
        owner.id = UUID()
        owner.name = name
        owner.email = email
        owner.phone = phone
        owner.managementFeePercent = managementFeePercent as NSDecimalNumber
        owner.isActive = true
        owner.createdAt = Date()
        owner.updatedAt = Date()
        return owner
    }
}

// MARK: - Fetch Requests

extension Owner {
    static func allOwnersFetchRequest() -> NSFetchRequest<Owner> {
        let request: NSFetchRequest<Owner> = Owner.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Owner.name, ascending: true)]
        return request
    }

    static func ownersWithUnpaidPayouts(in context: NSManagedObjectContext) -> [Owner] {
        let request = allOwnersFetchRequest()
        guard let owners = try? context.fetch(request) else { return [] }

        return owners.filter { owner in
            owner.totalUnpaidPayouts(in: context) > 0
        }
    }
}
