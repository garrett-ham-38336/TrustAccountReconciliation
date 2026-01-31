import WidgetKit
import SwiftUI

/// Timeline entry for the Trust Account widget
struct ReconciliationEntry: TimelineEntry {
    let date: Date
    let status: ReconciliationStatus
    let variance: Decimal
    let daysSinceLastReconciliation: Int?
    let lastReconciliationDate: Date?
}

/// Reconciliation status for display
enum ReconciliationStatus: String {
    case balanced = "Balanced"
    case variance = "Variance"
    case overdue = "Overdue"
    case neverReconciled = "Not Started"

    var color: Color {
        switch self {
        case .balanced: return .green
        case .variance: return .orange
        case .overdue: return .red
        case .neverReconciled: return .gray
        }
    }

    var icon: String {
        switch self {
        case .balanced: return "checkmark.circle.fill"
        case .variance: return "exclamationmark.triangle.fill"
        case .overdue: return "clock.badge.exclamationmark.fill"
        case .neverReconciled: return "questionmark.circle.fill"
        }
    }
}

/// Provider for widget timeline
struct ReconciliationTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> ReconciliationEntry {
        ReconciliationEntry(
            date: Date(),
            status: .balanced,
            variance: 0,
            daysSinceLastReconciliation: 1,
            lastReconciliationDate: Date().addingTimeInterval(-86400)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ReconciliationEntry) -> Void) {
        // For snapshot, show sample data
        let entry = ReconciliationEntry(
            date: Date(),
            status: .balanced,
            variance: 0,
            daysSinceLastReconciliation: 1,
            lastReconciliationDate: Date().addingTimeInterval(-86400)
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReconciliationEntry>) -> Void) {
        // Fetch latest reconciliation data from shared container
        let entry = fetchLatestReconciliationData()

        // Update every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    /// Fetches the latest reconciliation data from the shared app group container
    private func fetchLatestReconciliationData() -> ReconciliationEntry {
        // Access shared UserDefaults for app group
        // Note: This requires configuring an App Group in both the main app and widget targets
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.trustaccounting.shared") else {
            return ReconciliationEntry(
                date: Date(),
                status: .neverReconciled,
                variance: 0,
                daysSinceLastReconciliation: nil,
                lastReconciliationDate: nil
            )
        }

        // Read cached reconciliation data
        let lastReconciliationTimestamp = sharedDefaults.double(forKey: "lastReconciliationDate")
        let varianceValue = sharedDefaults.double(forKey: "lastVariance")
        let isBalanced = sharedDefaults.bool(forKey: "isBalanced")
        let reconciliationThresholdDays = sharedDefaults.integer(forKey: "reconciliationThresholdDays")

        // Determine status
        let status: ReconciliationStatus
        let lastReconciliationDate: Date?
        var daysSince: Int? = nil

        if lastReconciliationTimestamp > 0 {
            lastReconciliationDate = Date(timeIntervalSince1970: lastReconciliationTimestamp)
            daysSince = Calendar.current.dateComponents([.day], from: lastReconciliationDate!, to: Date()).day

            let threshold = reconciliationThresholdDays > 0 ? reconciliationThresholdDays : 7

            if let days = daysSince, days >= threshold {
                status = .overdue
            } else if isBalanced {
                status = .balanced
            } else {
                status = .variance
            }
        } else {
            lastReconciliationDate = nil
            status = .neverReconciled
        }

        return ReconciliationEntry(
            date: Date(),
            status: status,
            variance: Decimal(varianceValue),
            daysSinceLastReconciliation: daysSince,
            lastReconciliationDate: lastReconciliationDate
        )
    }
}

/// Small widget view
struct TrustAccountWidgetSmallView: View {
    var entry: ReconciliationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            HStack {
                Image(systemName: entry.status.icon)
                    .foregroundColor(entry.status.color)
                    .font(.title2)
                Spacer()
                Text("Trust")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status
            Text(entry.status.rawValue)
                .font(.headline)
                .foregroundColor(entry.status.color)

            // Variance if applicable
            if entry.status == .variance {
                Text(formatCurrency(entry.variance))
                    .font(.title3.bold())
                    .foregroundColor(.orange)
            }

            // Days since last reconciliation
            if let days = entry.daysSinceLastReconciliation {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(daysText(days))
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            } else {
                Text("No reconciliation yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    private func daysText(_ days: Int) -> String {
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}

/// The widget configuration
struct TrustAccountWidget: Widget {
    let kind: String = "TrustAccountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReconciliationTimelineProvider()) { entry in
            TrustAccountWidgetSmallView(entry: entry)
        }
        .configurationDisplayName("Trust Account")
        .description("Shows reconciliation status at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

struct TrustAccountWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TrustAccountWidgetSmallView(entry: ReconciliationEntry(
                date: Date(),
                status: .balanced,
                variance: 0,
                daysSinceLastReconciliation: 1,
                lastReconciliationDate: Date().addingTimeInterval(-86400)
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Balanced")

            TrustAccountWidgetSmallView(entry: ReconciliationEntry(
                date: Date(),
                status: .variance,
                variance: 1234.56,
                daysSinceLastReconciliation: 3,
                lastReconciliationDate: Date().addingTimeInterval(-259200)
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Variance")

            TrustAccountWidgetSmallView(entry: ReconciliationEntry(
                date: Date(),
                status: .overdue,
                variance: 0,
                daysSinceLastReconciliation: 14,
                lastReconciliationDate: Date().addingTimeInterval(-1209600)
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Overdue")

            TrustAccountWidgetSmallView(entry: ReconciliationEntry(
                date: Date(),
                status: .neverReconciled,
                variance: 0,
                daysSinceLastReconciliation: nil,
                lastReconciliationDate: nil
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Never Reconciled")
        }
    }
}
