import Foundation
import WidgetKit
import CoreData

/// Service for updating widget data through shared UserDefaults
/// Requires an App Group to be configured in both the main app and widget targets
class WidgetDataService {
    static let shared = WidgetDataService()

    /// The app group identifier - must match the widget's app group
    private let appGroupIdentifier = "group.com.trustaccounting.shared"

    /// Shared UserDefaults for app group communication
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private init() {}

    // MARK: - Update Widget Data

    /// Updates the widget with the latest reconciliation data
    /// Call this after completing a reconciliation
    func updateReconciliationData(
        lastReconciliationDate: Date,
        variance: Decimal,
        isBalanced: Bool
    ) {
        guard let defaults = sharedDefaults else {
            DebugLogger.shared.log("Widget update failed: Unable to access app group UserDefaults", prefix: "WIDGET")
            return
        }

        defaults.set(lastReconciliationDate.timeIntervalSince1970, forKey: "lastReconciliationDate")
        defaults.set(NSDecimalNumber(decimal: variance).doubleValue, forKey: "lastVariance")
        defaults.set(isBalanced, forKey: "isBalanced")

        // Trigger widget refresh
        WidgetCenter.shared.reloadTimelines(ofKind: "TrustAccountWidget")

        DebugLogger.shared.log("Widget data updated - Balanced: \(isBalanced), Variance: \(variance)", prefix: "WIDGET")
    }

    /// Updates the reconciliation threshold setting for the widget
    func updateReconciliationThreshold(days: Int) {
        sharedDefaults?.set(days, forKey: "reconciliationThresholdDays")
    }

    /// Updates widget from the latest reconciliation snapshot in Core Data
    func updateFromLatestReconciliation(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ReconciliationSnapshot> = ReconciliationSnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ReconciliationSnapshot.createdAt, ascending: false)]
        request.fetchLimit = 1

        guard let snapshot = try? context.fetch(request).first else {
            DebugLogger.shared.log("No reconciliation snapshot found for widget update", prefix: "WIDGET")
            return
        }

        let variance = snapshot.variance?.decimalValue ?? 0
        let isBalanced = abs(variance) < 1.00

        updateReconciliationData(
            lastReconciliationDate: snapshot.createdAt ?? Date(),
            variance: variance,
            isBalanced: isBalanced
        )
    }

    /// Clears all widget data (useful for logout or data reset)
    func clearWidgetData() {
        guard let defaults = sharedDefaults else { return }

        defaults.removeObject(forKey: "lastReconciliationDate")
        defaults.removeObject(forKey: "lastVariance")
        defaults.removeObject(forKey: "isBalanced")

        WidgetCenter.shared.reloadTimelines(ofKind: "TrustAccountWidget")

        DebugLogger.shared.log("Widget data cleared", prefix: "WIDGET")
    }

    // MARK: - Widget Availability

    /// Checks if widgets are available on this system
    var widgetsAvailable: Bool {
        if #available(macOS 11.0, *) {
            return true
        }
        return false
    }

    /// Forces a widget refresh
    func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
