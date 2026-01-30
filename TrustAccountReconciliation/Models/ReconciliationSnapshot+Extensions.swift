import Foundation
import CoreData

// MARK: - ReconciliationSnapshot Extensions

extension ReconciliationSnapshot {
    /// Reconciliation status values
    enum ReconciliationStatus: String, CaseIterable {
        case draft = "draft"
        case balanced = "balanced"
        case variance = "variance"

        var displayName: String {
            switch self {
            case .draft: return "Draft"
            case .balanced: return "Balanced"
            case .variance: return "Variance Detected"
            }
        }
    }

    /// Gets the status enum value
    var statusValue: ReconciliationStatus {
        return ReconciliationStatus(rawValue: status ?? "draft") ?? .draft
    }

    /// Formatted date string
    var dateString: String {
        guard let date = reconciliationDate else { return "Unknown Date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Gets future reservations data decoded from JSON
    func getFutureReservationsData() -> [TrustCalculationService.ReservationSummary]? {
        guard let data = futureReservationsData else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([TrustCalculationService.ReservationSummary].self, from: data)
    }

    /// Gets unpaid payouts data decoded from JSON
    func getUnpaidPayoutsData() -> [TrustCalculationService.ReservationSummary]? {
        guard let data = unpaidPayoutsData else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([TrustCalculationService.ReservationSummary].self, from: data)
    }

    /// Gets unpaid taxes data decoded from JSON
    func getUnpaidTaxesData() -> [TrustCalculationService.ReservationSummary]? {
        guard let data = unpaidTaxesData else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([TrustCalculationService.ReservationSummary].self, from: data)
    }
}

// MARK: - Fetch Requests

extension ReconciliationSnapshot {
    /// Fetch request for all reconciliations sorted by date
    static func allReconciliationsFetchRequest() -> NSFetchRequest<ReconciliationSnapshot> {
        let request: NSFetchRequest<ReconciliationSnapshot> = ReconciliationSnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ReconciliationSnapshot.reconciliationDate, ascending: false)]
        return request
    }

    /// Gets the most recent reconciliation
    static func mostRecent(in context: NSManagedObjectContext) -> ReconciliationSnapshot? {
        let request: NSFetchRequest<ReconciliationSnapshot> = ReconciliationSnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ReconciliationSnapshot.reconciliationDate, ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Days since last reconciliation
    static func daysSinceLastReconciliation(in context: NSManagedObjectContext) -> Int? {
        guard let lastRecon = mostRecent(in: context),
              let reconDate = lastRecon.reconciliationDate else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: reconDate, to: Date()).day
    }
}
