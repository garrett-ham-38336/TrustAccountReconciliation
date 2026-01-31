import Foundation
import CoreData

/// Service for logging audit events for compliance and tracking
class AuditService {
    static let shared = AuditService()

    private init() {}

    // MARK: - Audit Actions

    enum AuditAction: String {
        case create = "CREATE"
        case update = "UPDATE"
        case delete = "DELETE"
        case reconciliation = "RECONCILIATION"
        case payout = "PAYOUT"
        case taxRemittance = "TAX_REMITTANCE"
        case sync = "SYNC"
        case backup = "BACKUP"
        case restore = "RESTORE"
    }

    enum EntityType: String {
        case owner = "Owner"
        case property = "Property"
        case reservation = "Reservation"
        case taxJurisdiction = "TaxJurisdiction"
        case reconciliation = "ReconciliationSnapshot"
        case settings = "AppSettings"
    }

    // MARK: - Log Methods

    /// Logs an audit event
    func log(
        action: AuditAction,
        entityType: EntityType,
        entityId: String? = nil,
        entityName: String? = nil,
        fieldName: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        notes: String? = nil,
        context: NSManagedObjectContext
    ) {
        let auditLog = AuditLog(context: context)
        auditLog.id = UUID()
        auditLog.timestamp = Date()
        auditLog.action = action.rawValue
        auditLog.entityType = entityType.rawValue
        auditLog.entityId = entityId
        auditLog.entityName = entityName
        auditLog.fieldName = fieldName
        auditLog.oldValue = oldValue
        auditLog.newValue = newValue
        auditLog.notes = notes

        // Don't save here - let the caller save as part of their transaction
    }

    /// Logs a create action
    func logCreate(
        entityType: EntityType,
        entityId: String,
        entityName: String,
        context: NSManagedObjectContext
    ) {
        log(
            action: .create,
            entityType: entityType,
            entityId: entityId,
            entityName: entityName,
            context: context
        )
    }

    /// Logs an update action with field changes
    func logUpdate(
        entityType: EntityType,
        entityId: String,
        entityName: String,
        fieldName: String,
        oldValue: String?,
        newValue: String?,
        context: NSManagedObjectContext
    ) {
        log(
            action: .update,
            entityType: entityType,
            entityId: entityId,
            entityName: entityName,
            fieldName: fieldName,
            oldValue: oldValue,
            newValue: newValue,
            context: context
        )
    }

    /// Logs a delete action
    func logDelete(
        entityType: EntityType,
        entityId: String,
        entityName: String,
        context: NSManagedObjectContext
    ) {
        log(
            action: .delete,
            entityType: entityType,
            entityId: entityId,
            entityName: entityName,
            context: context
        )
    }

    /// Logs a reconciliation event
    func logReconciliation(
        snapshotId: String,
        bankBalance: Decimal,
        variance: Decimal,
        isBalanced: Bool,
        context: NSManagedObjectContext
    ) {
        let notes = isBalanced
            ? "Reconciliation completed - BALANCED"
            : "Reconciliation completed - VARIANCE: \(variance.asCurrency)"

        log(
            action: .reconciliation,
            entityType: .reconciliation,
            entityId: snapshotId,
            entityName: "Reconciliation",
            notes: notes,
            context: context
        )
    }

    /// Logs an owner payout event
    func logOwnerPayout(
        ownerId: String,
        ownerName: String,
        amount: Decimal,
        reservationCount: Int,
        context: NSManagedObjectContext
    ) {
        let notes = "Payout of \(amount.asCurrency) for \(reservationCount) reservation(s)"

        log(
            action: .payout,
            entityType: .owner,
            entityId: ownerId,
            entityName: ownerName,
            notes: notes,
            context: context
        )
    }

    /// Logs a tax remittance event
    func logTaxRemittance(
        month: String,
        amount: Decimal,
        reservationCount: Int,
        context: NSManagedObjectContext
    ) {
        let notes = "Tax remittance of \(amount.asCurrency) for \(reservationCount) reservation(s) in \(month)"

        log(
            action: .taxRemittance,
            entityType: .reservation,
            notes: notes,
            context: context
        )
    }

    /// Logs a sync event
    func logSync(
        source: String,
        recordsCreated: Int,
        recordsUpdated: Int,
        context: NSManagedObjectContext
    ) {
        let notes = "\(source) sync: \(recordsCreated) created, \(recordsUpdated) updated"

        log(
            action: .sync,
            entityType: .reservation,
            notes: notes,
            context: context
        )
    }

    // MARK: - Query Methods

    /// Fetches recent audit logs
    static func recentLogs(limit: Int = 100, in context: NSManagedObjectContext) -> [AuditLog] {
        let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AuditLog.timestamp, ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    /// Fetches audit logs for a specific entity
    static func logsForEntity(
        type: EntityType,
        id: String,
        in context: NSManagedObjectContext
    ) -> [AuditLog] {
        let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "entityType == %@ AND entityId == %@",
            type.rawValue,
            id
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AuditLog.timestamp, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    /// Fetches audit logs within a date range
    static func logsInRange(
        from startDate: Date,
        to endDate: Date,
        in context: NSManagedObjectContext
    ) -> [AuditLog] {
        let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AuditLog.timestamp, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Cleanup

    /// Removes audit logs older than the specified number of days
    static func cleanupOldLogs(olderThanDays days: Int, in context: NSManagedObjectContext) throws {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return
        }

        let request: NSFetchRequest<NSFetchRequestResult> = AuditLog.fetchRequest()
        request.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)

        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
}

// MARK: - AuditLog Extensions

extension AuditLog {
    var actionDisplay: String {
        guard let action = action else { return "Unknown" }
        return action.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var formattedTimestamp: String {
        guard let timestamp = timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var changeDescription: String {
        if let fieldName = fieldName {
            let old = oldValue ?? "(empty)"
            let new = newValue ?? "(empty)"
            return "\(fieldName): \(old) -> \(new)"
        }
        return notes ?? ""
    }
}
