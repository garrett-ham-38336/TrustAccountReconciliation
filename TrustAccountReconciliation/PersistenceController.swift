import CoreData
import Foundation

/// PersistenceController manages the Core Data stack for the Trust Account Reconciliation system.
struct PersistenceController {
    static let shared = PersistenceController()

    /// Preview instance for SwiftUI previews
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample data for previews
        createSampleData(in: viewContext)

        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "TrustAccountModel")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Set up the persistent store with options for data integrity
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve persistent store description")
            }

            // Store in Application Support directory
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupportURL
                .appendingPathComponent("TrustAccountReconciliation", isDirectory: true)
                .appendingPathComponent("TrustAccountData.sqlite")

            // Create directory if needed
            try? FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            description.url = storeURL

            // Enable automatic migration
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

            // Enable SQLite WAL mode for better crash recovery
            description.setOption(["journal_mode": "WAL"] as NSDictionary, forKey: NSSQLitePragmasOption)
        }

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
                fatalError("Failed to load persistent store: \(error)")
            }
        }

        // Configure the view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Set up undo manager for data entry recovery
        container.viewContext.undoManager = UndoManager()
    }

    // MARK: - Data Operations

    /// Saves the context if there are changes
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Save error: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    /// Creates a background context for heavy operations
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Backup and Restore

    /// Creates a backup and returns the URL
    func createBackup() async throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupsDir = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "TrustAccountBackup_\(dateFormatter.string(from: Date())).sqlite"
        let backupURL = backupsDir.appendingPathComponent(filename)

        try backupData(to: backupURL)
        return backupURL
    }

    /// Creates a backup of the database to the specified URL
    func backupData(to url: URL) throws {
        let coordinator = container.persistentStoreCoordinator

        guard let store = coordinator.persistentStores.first,
              let storeURL = store.url else {
            throw PersistenceError.noStoreFound
        }

        // Save any pending changes first
        save()

        // Copy the SQLite files
        let fileManager = FileManager.default

        // Create backup directory
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Copy main database and WAL files
        let extensions = ["", "-wal", "-shm"]
        for ext in extensions {
            let sourceFile = URL(fileURLWithPath: storeURL.path + ext)
            let destFile = URL(fileURLWithPath: url.path + ext)

            if fileManager.fileExists(atPath: sourceFile.path) {
                if fileManager.fileExists(atPath: destFile.path) {
                    try fileManager.removeItem(at: destFile)
                }
                try fileManager.copyItem(at: sourceFile, to: destFile)
            }
        }
    }

    /// Restores from a backup URL
    func restoreBackup(from url: URL) throws {
        let coordinator = container.persistentStoreCoordinator

        guard let store = coordinator.persistentStores.first,
              let storeURL = store.url else {
            throw PersistenceError.noStoreFound
        }

        // Remove the current store
        try coordinator.remove(store)

        // Copy backup files
        let fileManager = FileManager.default
        let extensions = ["", "-wal", "-shm"]

        for ext in extensions {
            let sourceFile = URL(fileURLWithPath: url.path + ext)
            let destFile = URL(fileURLWithPath: storeURL.path + ext)

            if fileManager.fileExists(atPath: sourceFile.path) {
                if fileManager.fileExists(atPath: destFile.path) {
                    try fileManager.removeItem(at: destFile)
                }
                try fileManager.copyItem(at: sourceFile, to: destFile)
            }
        }

        // Reload the store
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
    }

    /// Verifies data integrity and returns list of issues
    func verifyDataIntegrity() -> [String] {
        var issues: [String] = []
        let context = container.viewContext

        // Check for orphaned reservations
        let reservationRequest: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        reservationRequest.predicate = NSPredicate(format: "property == nil AND isCancelled == NO")

        if let count = try? context.count(for: reservationRequest), count > 0 {
            issues.append("\(count) reservation(s) without assigned properties")
        }

        // Check for negative tax amounts
        let taxRequest: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        taxRequest.predicate = NSPredicate(format: "taxAmount < 0")

        if let count = try? context.count(for: taxRequest), count > 0 {
            issues.append("\(count) reservation(s) with negative tax amounts")
        }

        return issues
    }
}

// MARK: - Errors

enum PersistenceError: LocalizedError {
    case noStoreFound
    case backupFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .noStoreFound:
            return "No persistent store found"
        case .backupFailed(let reason):
            return "Backup failed: \(reason)"
        case .restoreFailed(let reason):
            return "Restore failed: \(reason)"
        }
    }
}

// MARK: - Sample Data for Previews

private func createSampleData(in context: NSManagedObjectContext) {
    let now = Date()

    // Create a sample owner
    let owner = Owner(context: context)
    owner.id = UUID()
    owner.name = "John Smith"
    owner.email = "john@example.com"
    owner.phone = "(555) 123-4567"
    owner.managementFeePercent = 20 as NSDecimalNumber
    owner.isActive = true
    owner.createdAt = now
    owner.updatedAt = now

    // Create a sample property
    let property = Property(context: context)
    property.id = UUID()
    property.name = "Lakehouse Cabin"
    property.address = "123 Lake Drive"
    property.city = "Hot Springs"
    property.state = "AR"
    property.zipCode = "71901"
    property.isActive = true
    property.managementFeePercent = 20 as NSDecimalNumber
    property.owner = owner
    property.createdAt = now
    property.updatedAt = now

    // Create a sample future reservation
    let reservation = Reservation(context: context)
    reservation.id = UUID()
    reservation.confirmationCode = "LAKE001"
    reservation.guestName = "Jane Doe"
    reservation.guestEmail = "jane@example.com"
    reservation.checkInDate = Calendar.current.date(byAdding: .day, value: 7, to: now)!
    reservation.checkOutDate = Calendar.current.date(byAdding: .day, value: 10, to: now)!
    reservation.nightCount = 3
    reservation.status = "confirmed"
    reservation.accommodationFare = 450 as NSDecimalNumber
    reservation.cleaningFee = 150 as NSDecimalNumber
    reservation.taxAmount = 54 as NSDecimalNumber
    reservation.totalAmount = 654 as NSDecimalNumber
    reservation.depositReceived = 654 as NSDecimalNumber
    reservation.isFullyPaid = true
    reservation.ownerPayout = 480 as NSDecimalNumber
    reservation.managementFee = 120 as NSDecimalNumber
    reservation.property = property
    reservation.createdAt = now
    reservation.updatedAt = now

    do {
        try context.save()
    } catch {
        print("Failed to create sample data: \(error)")
    }
}
