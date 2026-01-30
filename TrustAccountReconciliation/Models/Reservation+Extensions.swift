import Foundation
import CoreData

// MARK: - Reservation Extensions

extension Reservation {
    /// Reservation status values
    enum ReservationStatus: String, CaseIterable {
        case inquiry = "inquiry"
        case confirmed = "confirmed"
        case checkedIn = "checked_in"
        case checkedOut = "checked_out"
        case cancelled = "cancelled"

        var displayName: String {
            switch self {
            case .inquiry: return "Inquiry"
            case .confirmed: return "Confirmed"
            case .checkedIn: return "Checked In"
            case .checkedOut: return "Checked Out"
            case .cancelled: return "Cancelled"
            }
        }

        var color: String {
            switch self {
            case .inquiry: return "gray"
            case .confirmed: return "blue"
            case .checkedIn: return "green"
            case .checkedOut: return "purple"
            case .cancelled: return "red"
            }
        }
    }

    var statusValue: ReservationStatus {
        ReservationStatus(rawValue: status ?? "confirmed") ?? .confirmed
    }

    /// Whether this is a future reservation (check-in hasn't happened yet)
    var isFuture: Bool {
        guard let checkIn = checkInDate else { return false }
        return checkIn > Date() && !isCancelled
    }

    /// Whether this reservation is completed (checked out)
    var isCompleted: Bool {
        guard let checkOut = checkOutDate else { return false }
        return checkOut <= Date() && !isCancelled
    }

    /// Whether this reservation is currently active (guest is staying)
    var isActive: Bool {
        guard let checkIn = checkInDate, let checkOut = checkOutDate else { return false }
        let now = Date()
        return checkIn <= now && checkOut > now && !isCancelled
    }

    /// Date range display string
    var dateRangeString: String {
        guard let checkIn = checkInDate, let checkOut = checkOutDate else { return "No dates" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: checkIn)) - \(formatter.string(from: checkOut))"
    }

    /// Calculates the owner payout based on property management fee
    func calculateOwnerPayout() -> Decimal {
        let total = totalAmount as Decimal? ?? 0
        let taxes = taxAmount as Decimal? ?? 0
        let hostFee = hostServiceFee as Decimal? ?? 0

        // Net after taxes and host fees
        let netRevenue = total - taxes - hostFee

        // Get management fee percent (from reservation or property or default 20%)
        let mgmtFeePercent: Decimal
        if let resMgmtFee = managementFee as Decimal?, resMgmtFee > 0 {
            // If already set, calculate percent from it
            mgmtFeePercent = (resMgmtFee / netRevenue) * 100
        } else if let propFee = property?.managementFeePercent as Decimal?, propFee > 0 {
            mgmtFeePercent = propFee
        } else if let ownerFee = property?.owner?.managementFeePercent as Decimal?, ownerFee > 0 {
            mgmtFeePercent = ownerFee
        } else {
            mgmtFeePercent = 20
        }

        let mgmtFee = netRevenue * (mgmtFeePercent / 100)
        return netRevenue - mgmtFee
    }

    /// Calculates management fee
    func calculateManagementFee() -> Decimal {
        let total = totalAmount as Decimal? ?? 0
        let taxes = taxAmount as Decimal? ?? 0
        let hostFee = hostServiceFee as Decimal? ?? 0
        let netRevenue = total - taxes - hostFee

        let mgmtFeePercent: Decimal
        if let propFee = property?.managementFeePercent as Decimal?, propFee > 0 {
            mgmtFeePercent = propFee
        } else if let ownerFee = property?.owner?.managementFeePercent as Decimal?, ownerFee > 0 {
            mgmtFeePercent = ownerFee
        } else {
            mgmtFeePercent = 20
        }

        return netRevenue * (mgmtFeePercent / 100)
    }
}

// MARK: - Fetch Requests

extension Reservation {
    /// Future reservations with deposits (for trust calculation)
    static func futureReservationsWithDeposits() -> NSFetchRequest<Reservation> {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.predicate = NSPredicate(
            format: "checkInDate > %@ AND isCancelled == NO AND depositReceived > 0",
            Date() as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.checkInDate, ascending: true)]
        return request
    }

    /// Completed reservations with unpaid owner payouts
    static func completedUnpaidPayouts(since date: Date?) -> NSFetchRequest<Reservation> {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        if let sinceDate = date {
            request.predicate = NSPredicate(
                format: "checkOutDate <= %@ AND checkOutDate > %@ AND isCancelled == NO AND ownerPaidOut == NO",
                Date() as NSDate,
                sinceDate as NSDate
            )
        } else {
            request.predicate = NSPredicate(
                format: "checkOutDate <= %@ AND isCancelled == NO AND ownerPaidOut == NO",
                Date() as NSDate
            )
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.checkOutDate, ascending: true)]
        return request
    }

    /// Completed reservations with unremitted taxes
    static func completedUnremittedTaxes(since date: Date?) -> NSFetchRequest<Reservation> {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        if let sinceDate = date {
            request.predicate = NSPredicate(
                format: "checkOutDate <= %@ AND checkOutDate > %@ AND isCancelled == NO AND taxRemitted == NO AND taxAmount > 0",
                Date() as NSDate,
                sinceDate as NSDate
            )
        } else {
            request.predicate = NSPredicate(
                format: "checkOutDate <= %@ AND isCancelled == NO AND taxRemitted == NO AND taxAmount > 0",
                Date() as NSDate
            )
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.checkOutDate, ascending: true)]
        return request
    }

    /// All reservations sorted by check-in date
    static func allReservationsFetchRequest() -> NSFetchRequest<Reservation> {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.checkInDate, ascending: false)]
        return request
    }

    /// Reservations for a specific property
    static func reservationsForProperty(_ propertyId: UUID) -> NSFetchRequest<Reservation> {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.predicate = NSPredicate(format: "property.id == %@", propertyId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.checkInDate, ascending: false)]
        return request
    }

    /// Find reservation by Guesty ID
    static func findByGuestyId(_ guestyId: String, in context: NSManagedObjectContext) -> Reservation? {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.predicate = NSPredicate(format: "guestyReservationId == %@", guestyId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
