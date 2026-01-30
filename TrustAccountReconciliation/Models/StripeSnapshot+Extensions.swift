import Foundation
import CoreData

// MARK: - StripeSnapshot Extensions

extension StripeSnapshot {
    /// Gets the total in-transit funds (pending payouts + holdbacks)
    var totalInTransit: Decimal {
        let pending = pendingBalance as Decimal? ?? 0
        let reserve = reserveBalance as Decimal? ?? 0
        return pending + reserve
    }

    /// Gets the total available plus in-transit
    var totalProcessorFunds: Decimal {
        let available = availableBalance as Decimal? ?? 0
        return available + totalInTransit
    }

    /// Indicates if there's a holdback/reserve
    var hasReserve: Bool {
        let reserve = reserveBalance as Decimal? ?? 0
        return reserve > 0
    }

    /// Indicates if there are pending payouts
    var hasPendingPayouts: Bool {
        let pending = pendingBalance as Decimal? ?? 0
        return pending > 0
    }

    /// Formatted display of balances
    var balanceSummary: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"

        let available = availableBalance as Decimal? ?? 0
        let pending = pendingBalance as Decimal? ?? 0
        let reserve = reserveBalance as Decimal? ?? 0

        var components: [String] = []

        if let availableStr = formatter.string(from: available as NSDecimalNumber) {
            components.append("Available: \(availableStr)")
        }
        if pending > 0, let pendingStr = formatter.string(from: pending as NSDecimalNumber) {
            components.append("Pending: \(pendingStr)")
        }
        if reserve > 0, let reserveStr = formatter.string(from: reserve as NSDecimalNumber) {
            components.append("Reserve: \(reserveStr)")
        }

        return components.joined(separator: " | ")
    }

    /// Creates a new Stripe snapshot
    static func create(
        in context: NSManagedObjectContext,
        availableBalance: Decimal,
        pendingBalance: Decimal = 0,
        reserveBalance: Decimal = 0,
        reconciliation: ReconciliationSnapshot? = nil
    ) -> StripeSnapshot {
        let snapshot = StripeSnapshot(context: context)
        snapshot.id = UUID()
        snapshot.snapshotDate = Date()
        snapshot.availableBalance = availableBalance as NSDecimalNumber
        snapshot.pendingBalance = pendingBalance as NSDecimalNumber
        snapshot.reserveBalance = reserveBalance as NSDecimalNumber
        snapshot.totalBalance = (availableBalance + pendingBalance + reserveBalance) as NSDecimalNumber
        snapshot.reconciliation = reconciliation
        snapshot.createdAt = Date()

        return snapshot
    }

    /// Creates a snapshot from Stripe API response data
    static func createFromStripeData(
        in context: NSManagedObjectContext,
        available: [String: Any],
        pending: [String: Any]?,
        connectReserved: [String: Any]?,
        reconciliation: ReconciliationSnapshot? = nil
    ) -> StripeSnapshot {
        // Parse available balance (amounts are in cents)
        let availableAmount = (available["amount"] as? Int ?? 0)
        let availableDecimal = Decimal(availableAmount) / 100

        // Parse pending balance
        var pendingDecimal: Decimal = 0
        if let pending = pending, let amount = pending["amount"] as? Int {
            pendingDecimal = Decimal(amount) / 100
        }

        // Parse reserve balance
        var reserveDecimal: Decimal = 0
        if let reserved = connectReserved, let amount = reserved["amount"] as? Int {
            reserveDecimal = Decimal(amount) / 100
        }

        return create(
            in: context,
            availableBalance: availableDecimal,
            pendingBalance: pendingDecimal,
            reserveBalance: reserveDecimal,
            reconciliation: reconciliation
        )
    }

    /// Validates the snapshot
    func validate() throws {
        let available = availableBalance as Decimal? ?? 0
        let pending = pendingBalance as Decimal? ?? 0
        let reserve = reserveBalance as Decimal? ?? 0

        guard available >= 0 && pending >= 0 && reserve >= 0 else {
            throw ValidationError.invalidValue("Stripe balances cannot be negative")
        }
    }
}

// MARK: - Fetch Requests

extension StripeSnapshot {
    /// Fetch request for all snapshots sorted by date
    static func allSnapshotsFetchRequest() -> NSFetchRequest<StripeSnapshot> {
        let request: NSFetchRequest<StripeSnapshot> = StripeSnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \StripeSnapshot.snapshotDate, ascending: false)]
        return request
    }

    /// Gets the most recent Stripe snapshot
    static func mostRecent(in context: NSManagedObjectContext) -> StripeSnapshot? {
        let request: NSFetchRequest<StripeSnapshot> = StripeSnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \StripeSnapshot.snapshotDate, ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Fetch request for snapshots in a date range
    static func snapshotsInRange(from startDate: Date, to endDate: Date) -> NSFetchRequest<StripeSnapshot> {
        let request: NSFetchRequest<StripeSnapshot> = StripeSnapshot.fetchRequest()
        request.predicate = NSPredicate(
            format: "snapshotDate >= %@ AND snapshotDate <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \StripeSnapshot.snapshotDate, ascending: true)]
        return request
    }
}
