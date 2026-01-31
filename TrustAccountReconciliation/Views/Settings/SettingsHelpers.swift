import SwiftUI
import CoreData

// MARK: - Settings Sections Enum

enum SettingsSection: String, CaseIterable {
    case general
    case reconciliation
    case taxRemittance
    case guesty
    case stripe
    case taxJurisdictions
    case backup
    case syncHistory

    var displayName: String {
        switch self {
        case .general: return "General"
        case .reconciliation: return "Reconciliation"
        case .taxRemittance: return "Tax Remittance"
        case .guesty: return "Guesty API"
        case .stripe: return "Stripe API"
        case .taxJurisdictions: return "Tax Jurisdictions"
        case .backup: return "Backup & Restore"
        case .syncHistory: return "Sync History"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .reconciliation: return "checkmark.circle.fill"
        case .taxRemittance: return "dollarsign.circle.fill"
        case .guesty: return "cloud.fill"
        case .stripe: return "creditcard.fill"
        case .taxJurisdictions: return "percent"
        case .backup: return "externaldrive.fill"
        case .syncHistory: return "clock.arrow.circlepath"
        }
    }

    static var configurationSections: [SettingsSection] {
        [.general, .reconciliation, .taxRemittance]
    }

    static var integrationSections: [SettingsSection] {
        [.guesty, .stripe, .taxJurisdictions]
    }

    static var dataSections: [SettingsSection] {
        [.backup, .syncHistory]
    }
}

// MARK: - Navigation Row

struct SettingsNavRow: View {
    let section: SettingsSection

    var body: some View {
        Label(section.displayName, systemImage: section.icon)
    }
}

// MARK: - Helper Views

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct SettingsTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Connection Status

enum ConnectionStatus {
    case unknown
    case testing
    case connected
    case failed(String)

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .testing: return .blue
        case .connected: return .green
        case .failed: return .red
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .testing: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var text: String {
        switch self {
        case .unknown: return "Not tested"
        case .testing: return "Testing..."
        case .connected: return "Connected"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

// MARK: - AppSettings Extension

extension AppSettings {
    static func getOrCreate(in context: NSManagedObjectContext) -> AppSettings {
        let request: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let settings = AppSettings(context: context)
        settings.id = UUID()
        settings.varianceThreshold = 100 as NSDecimalNumber
        settings.reconciliationReminderDays = 7
        settings.defaultManagementFeePercent = 20 as NSDecimalNumber
        settings.guestyIntegrationEnabled = false
        settings.createdAt = Date()
        settings.updatedAt = Date()

        try? context.save()
        return settings
    }
}

// MARK: - Decimal Extension

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
