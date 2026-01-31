import Foundation
import UserNotifications
import CoreData

/// Service for managing local notifications for reconciliation reminders
class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    // Notification identifiers
    private let reconciliationReminderID = "reconciliation-reminder"
    private let varianceAlertID = "variance-alert"

    private init() {}

    // MARK: - Authorization

    /// Requests notification permission from the user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
            }
            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }

    /// Checks current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    /// Requests permission if not already determined
    func requestAuthorizationIfNeeded() async {
        let status = await checkAuthorizationStatus()
        if status == .notDetermined {
            _ = await requestAuthorization()
        }
    }

    // MARK: - Reconciliation Reminder

    /// Schedules a reminder for reconciliation if overdue
    /// - Parameters:
    ///   - lastReconciliationDate: Date of the last reconciliation
    ///   - reminderDays: Number of days after which to remind
    func scheduleReconciliationReminder(lastReconciliationDate: Date?, reminderDays: Int) {
        // Cancel any existing reminder
        center.removePendingNotificationRequests(withIdentifiers: [reconciliationReminderID])

        guard let lastDate = lastReconciliationDate else {
            // No reconciliation ever - schedule for tomorrow morning
            scheduleFirstReconciliationReminder()
            return
        }

        // Calculate when to send the reminder
        let calendar = Calendar.current
        guard let reminderDate = calendar.date(byAdding: .day, value: reminderDays, to: lastDate) else {
            return
        }

        // If reminder date is in the past, schedule for tomorrow
        let notificationDate: Date
        if reminderDate < Date() {
            notificationDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        } else {
            notificationDate = reminderDate
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Reconciliation Reminder"
        content.body = "It's been \(reminderDays) days since your last trust account reconciliation. Consider reconciling soon."
        content.sound = .default
        content.categoryIdentifier = "RECONCILIATION_REMINDER"

        // Schedule for 9 AM
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: notificationDate)
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: reconciliationReminderID, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Error scheduling reconciliation reminder: \(error)")
            } else {
                print("Reconciliation reminder scheduled for \(dateComponents)")
            }
        }
    }

    private func scheduleFirstReconciliationReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Start Reconciling"
        content.body = "You haven't performed any trust account reconciliations yet. Start your first one today!"
        content.sound = .default
        content.categoryIdentifier = "RECONCILIATION_REMINDER"

        // Schedule for tomorrow at 9 AM
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        dateComponents.day! += 1
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: reconciliationReminderID, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Error scheduling first reconciliation reminder: \(error)")
            }
        }
    }

    // MARK: - Variance Alert

    /// Shows an immediate notification for a large variance
    /// - Parameters:
    ///   - variance: The variance amount
    ///   - threshold: The threshold that was exceeded
    func showVarianceAlert(variance: Decimal, threshold: Decimal) {
        let content = UNMutableNotificationContent()
        content.title = "Reconciliation Variance Alert"
        content.body = "Your trust account has a variance of \(variance.asCurrency), which exceeds your threshold of \(threshold.asCurrency)."
        content.sound = .default
        content.categoryIdentifier = "VARIANCE_ALERT"

        // Show immediately (1 second delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "\(varianceAlertID)-\(UUID().uuidString)", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Error showing variance alert: \(error)")
            }
        }
    }

    // MARK: - Cancel Notifications

    /// Cancels all pending reconciliation reminders
    func cancelReconciliationReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [reconciliationReminderID])
    }

    /// Cancels all pending notifications
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Update from Settings

    /// Updates notification schedule based on app settings
    func updateFromSettings(context: NSManagedObjectContext) {
        let request: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()
        request.fetchLimit = 1

        guard let settings = try? context.fetch(request).first else { return }

        // Get last reconciliation date
        let reconciliationRequest: NSFetchRequest<ReconciliationSnapshot> = ReconciliationSnapshot.fetchRequest()
        reconciliationRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ReconciliationSnapshot.reconciliationDate, ascending: false)]
        reconciliationRequest.fetchLimit = 1

        let lastDate = (try? context.fetch(reconciliationRequest).first)?.reconciliationDate

        // Schedule reminder
        scheduleReconciliationReminder(
            lastReconciliationDate: lastDate,
            reminderDays: Int(settings.reconciliationReminderDays)
        )
    }

    // MARK: - Check and Notify Variance

    /// Checks if a variance exceeds threshold and shows notification
    func checkAndNotifyVariance(variance: Decimal, context: NSManagedObjectContext) {
        let request: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()
        request.fetchLimit = 1

        guard let settings = try? context.fetch(request).first else { return }
        let threshold = settings.varianceThreshold as Decimal? ?? 100

        if abs(variance) > threshold {
            showVarianceAlert(variance: variance, threshold: threshold)
        }
    }

    // MARK: - Register Categories

    /// Registers notification categories and actions
    func registerCategories() {
        // Reconciliation reminder category
        let reconcileAction = UNNotificationAction(
            identifier: "RECONCILE_ACTION",
            title: "Open Reconciliation",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "Dismiss",
            options: []
        )

        let reconciliationCategory = UNNotificationCategory(
            identifier: "RECONCILIATION_REMINDER",
            actions: [reconcileAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Variance alert category
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: [.foreground]
        )

        let varianceCategory = UNNotificationCategory(
            identifier: "VARIANCE_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([reconciliationCategory, varianceCategory])
    }
}

// MARK: - Decimal Currency Extension (if not already defined elsewhere)

extension Decimal {
    fileprivate var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }
}
